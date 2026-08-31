#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGE_SCRIPT="$ROOT/scripts/package-app.sh"

fail() {
  echo "package-app-tests: $*" >&2
  exit 1
}

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-package-test.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$temp_root"
  exit "$status"
}
trap cleanup EXIT

fixture_root="$temp_root/repo"
fake_bin="$temp_root/bin"
mkdir -p \
  "$fixture_root/scripts" \
  "$fixture_root/Resources" \
  "$fixture_root/target/release" \
  "$fixture_root/.build/arm64-apple-macosx/release" \
  "$fake_bin"
cp "$PACKAGE_SCRIPT" "$fixture_root/scripts/package-app.sh"
cp "$ROOT/Resources/Info.plist" "$fixture_root/Resources/Info.plist"
cp "$ROOT/Resources/ThirdPartyNotices.txt" "$fixture_root/Resources/ThirdPartyNotices.txt"
mkdir -p "$fixture_root/Sources/NeedlbarWidgetSupport" "$fixture_root/WidgetExtension" "$fixture_root/.build/widget-extension"
cp "$ROOT/Sources/NeedlbarWidgetSupport/WidgetProjection.swift" "$fixture_root/Sources/NeedlbarWidgetSupport/WidgetProjection.swift"
cp "$ROOT/Sources/NeedlbarWidgetSupport/WidgetPresentation.swift" "$fixture_root/Sources/NeedlbarWidgetSupport/WidgetPresentation.swift"
cp "$ROOT/WidgetExtension/NeedlbarOverviewWidget.swift" "$fixture_root/WidgetExtension/NeedlbarOverviewWidget.swift"
cp "$ROOT/WidgetExtension/NeedlbarWidgetExtension-Info.plist" "$fixture_root/WidgetExtension/NeedlbarWidgetExtension-Info.plist"
cp "$ROOT/WidgetExtension/NeedlbarWidgetExtension.entitlements" "$fixture_root/WidgetExtension/NeedlbarWidgetExtension.entitlements"
cp "$ROOT/Resources/NeedlbarHostWidget.entitlements" "$fixture_root/Resources/NeedlbarHostWidget.entitlements"
cp "$ROOT/scripts/build-widget-extension.sh" "$fixture_root/scripts/build-widget-extension.sh"
chmod 755 "$fixture_root/scripts/package-app.sh"

cat > "$fake_bin/rustup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "target" && "${2:-}" == "list" && "${3:-}" == "--installed" ]]; then
  printf '%s\n' 'aarch64-apple-darwin'
fi
EOF

cat > "$fake_bin/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "-C" ]] || exit 2
repo_root="$2"
mkdir -p "$repo_root/target/release"
printf '%s\n' 'bridge archive' > "$repo_root/target/release/libneedlbar_bridge.a"
EOF

cat > "$fake_bin/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "build" ]]; then
  if [[ -e "$NEEDLBAR_PACKAGE_EXECUTABLE" ]]; then
    echo 'swift stub: stale executable was not removed before release build' >&2
    exit 91
  fi
  mkdir -p "$(dirname "$NEEDLBAR_PACKAGE_EXECUTABLE")"
  printf '%s\n' 'fresh executable' > "$NEEDLBAR_PACKAGE_EXECUTABLE"
fi
EOF

cat > "$fake_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "--sdk macosx --show-sdk-path" ]]; then
  printf '%s\n' /SyntheticMacOSX.sdk
  exit 0
fi
[[ "${1:-}" == swiftc ]] || { echo "unexpected xcrun argv: $*" >&2; exit 2; }
output=''
previous=''
for argument in "$@"; do
  if [[ "$previous" == -o ]]; then output="$argument"; fi
  previous="$argument"
done
[[ -n "$output" ]] || exit 3
mkdir -p "$(dirname "$output")"
printf '%s\n' synthetic-widget-extension > "$output"
chmod 755 "$output"
EOF

cat > "$fake_bin/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${@: -1}"
printf 'codesign %s %s\n' "$*" "$target" >> "$FAKE_CODESIGN_LOG"
EOF

chmod 755 "$fake_bin/rustup" "$fake_bin/make" "$fake_bin/swift" "$fake_bin/xcrun" "$fake_bin/codesign"

executable_source="$fixture_root/.build/arm64-apple-macosx/release/Needlbar"
printf '%s\n' 'stale executable' > "$executable_source"

if ! PATH="$fake_bin:$PATH" NEEDLBAR_PACKAGE_EXECUTABLE="$executable_source" \
  FAKE_CODESIGN_LOG="$temp_root/codesign.log" \
  "$fixture_root/scripts/package-app.sh"; then
  fail 'release packaging should relink when a stale executable already exists'
fi

[[ "$(<"$executable_source")" == 'fresh executable' ]] || \
  fail 'stubbed Swift build did not produce a fresh executable'
[[ "$(<"$fixture_root/dist/Needlbar.app/Contents/MacOS/Needlbar")" == 'fresh executable' ]] || \
  fail 'package did not install the freshly relinked executable'
[[ -f "$fixture_root/dist/Needlbar-macos-arm64.zip" ]] || \
  fail 'package zip was not produced'

embedded_app="$fixture_root/dist/Needlbar.app"
embedded_widget="$embedded_app/Contents/PlugIns/NeedlbarWidgetExtension.appex"
[[ -x "$embedded_widget/Contents/MacOS/NeedlbarWidgetExtension" ]] || fail 'embedded widget executable missing'
[[ "$(find "$embedded_app/Contents/PlugIns" -maxdepth 1 -type d -name '*.appex' -print | wc -l | tr -d '[:space:]')" == 1 ]] || fail 'package contains more than one extension'
grep -F 'com.apple.widgetkit-extension' "$embedded_widget/Contents/Info.plist" >/dev/null || fail 'embedded extension point missing'
grep -F 'TESTTEAMID.com.taejunoh.needlbar' "$embedded_widget/Contents/Info.plist" >/dev/null || fail 'embedded extension group missing'
grep -F 'TESTTEAMID.com.taejunoh.needlbar' "$fixture_root/dist/Needlbar.app/Contents/Info.plist" >/dev/null || fail 'host group missing'
extension_sign_line="$(grep -n 'NeedlbarWidgetExtension.appex' "$temp_root/codesign.log" | head -n 1 | cut -d: -f1)"
host_sign_line="$(grep -n 'Needlbar.app' "$temp_root/codesign.log" | head -n 1 | cut -d: -f1)"
[[ "$extension_sign_line" =~ ^[0-9]+$ && "$host_sign_line" =~ ^[0-9]+$ ]] || fail 'inner/host sign records missing'
(( extension_sign_line < host_sign_line )) || fail 'host was signed before extension'
! grep -E 'com.apple.security.app-sandbox|network|keychain' "$fixture_root/dist/.NeedlbarHostWidget.entitlements" >/dev/null || fail 'forbidden host entitlement surfaced'
! grep -E 'network|keychain' "$fixture_root/.build/widget-extension/NeedlbarWidgetExtension.entitlements" >/dev/null || fail 'forbidden extension entitlement surfaced'
grep -F 'com.apple.security.app-sandbox' "$fixture_root/.build/widget-extension/NeedlbarWidgetExtension.entitlements" >/dev/null || fail 'extension sandbox missing'

echo 'package-app relink regression passed'
