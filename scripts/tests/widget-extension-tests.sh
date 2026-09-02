#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/build-widget-extension.sh"
fail() { echo "widget-extension-tests: $*" >&2; exit 1; }

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-widget-extension-test.XXXXXX")"
cleanup() { local status=$?; trap - EXIT; rm -rf -- "$temp_root"; exit "$status"; }
trap cleanup EXIT INT TERM

fixture="$temp_root/repo"
fake_bin="$temp_root/bin"
mkdir -p "$fixture/Sources/NeedlbarWidgetSupport" "$fixture/WidgetExtension" "$fixture/scripts" "$fake_bin"
cp "$SCRIPT" "$fixture/scripts/build-widget-extension.sh"
cp "$ROOT/Sources/NeedlbarWidgetSupport/WidgetProjection.swift" "$fixture/Sources/NeedlbarWidgetSupport/WidgetProjection.swift"
cp "$ROOT/Sources/NeedlbarWidgetSupport/WidgetPresentation.swift" "$fixture/Sources/NeedlbarWidgetSupport/WidgetPresentation.swift"
cp "$ROOT/WidgetExtension/NeedlbarOverviewWidget.swift" "$fixture/WidgetExtension/NeedlbarOverviewWidget.swift"
cp "$ROOT/WidgetExtension/NeedlbarWidgetExtension-Info.plist" "$fixture/WidgetExtension/NeedlbarWidgetExtension-Info.plist"
cp "$ROOT/WidgetExtension/NeedlbarWidgetExtension.entitlements" "$fixture/WidgetExtension/NeedlbarWidgetExtension.entitlements"
chmod 755 "$fixture/scripts/build-widget-extension.sh"
! rg -n 'NeedlbarCore|CNeedlbar|import[[:space:]]+NeedlbarCore|import[[:space:]]+CNeedlbar|Rust|Keychain|URLSession' \
  "$fixture/Sources/NeedlbarWidgetSupport" "$fixture/WidgetExtension/NeedlbarOverviewWidget.swift" >/dev/null ||
  fail "widget source contains a host/provider dependency"

cat > "$fake_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "--sdk macosx --show-sdk-path" ]]; then
  printf '%s\n' /SyntheticMacOSX.sdk
  exit 0
fi
[[ "${1:-}" == swiftc ]] || { echo "unexpected xcrun argv: $*" >&2; exit 2; }
argv="$*"
[[ "$argv" != *NEEDLBAR_ACCEPTANCE_DRIVER* ]] || { echo 'extension received acceptance compiler define' >&2; exit 6; }
for required in '-target arm64-apple-macosx14.0' '-swift-version 6' '-application-extension' '-Xlinker -e -Xlinker _NSExtensionMain' '-framework SwiftUI' '-framework WidgetKit' 'WidgetProjection.swift' 'WidgetPresentation.swift' 'NeedlbarOverviewWidget.swift'; do
  [[ "$argv" == *"$required"* ]] || { echo "missing swiftc argument: $required" >&2; exit 3; }
done
[[ "$argv" != *NeedlbarCore* && "$argv" != *CNeedlbar* && "$argv" != *Rust* ]] || exit 4
output=''
previous=''
for argument in "$@"; do
  if [[ "$previous" == -o ]]; then output="$argument"; fi
  previous="$argument"
done
[[ -n "$output" ]] || exit 5
mkdir -p "$(dirname "$output")"
printf '%s\n' synthetic-widget-extension > "$output"
chmod 755 "$output"
EOF

cat > "$fake_bin/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_CODESIGN_LOG"
EOF
chmod 755 "$fake_bin/xcrun" "$fake_bin/codesign"

log="$temp_root/codesign.log"
output_dir="$fixture/.build/widget-extension"
output="${output_dir}/NeedlbarWidgetExtension.appex"
if PATH="$fake_bin:$PATH" FAKE_CODESIGN_LOG="$log" \
  "$fixture/scripts/build-widget-extension.sh" >"$temp_root/stdout" 2>"$temp_root/stderr"; then
  :
else
  status=$?
  cat "$temp_root/stdout" >&2
  cat "$temp_root/stderr" >&2
  fail "builder failed with status $status"
fi

[[ -x "$output/Contents/MacOS/NeedlbarWidgetExtension" ]] || fail "extension executable missing"
[[ "$(<"$temp_root/stdout")" == *"synthetic App Group identity"* ]] || fail "synthetic identity was not reported"
grep -F 'com.apple.widgetkit-extension' "$output/Contents/Info.plist" >/dev/null || fail "wrong extension point"
grep -F 'TESTTEAMID.com.taejunoh.needlbar' "$output/Contents/Info.plist" >/dev/null || fail "wrong Info.plist group"
grep -F 'TESTTEAMID.com.taejunoh.needlbar' "$output_dir/NeedlbarWidgetExtension.entitlements" >/dev/null || fail "wrong extension group"
grep -F 'com.apple.security.app-sandbox' "$output_dir/NeedlbarWidgetExtension.entitlements" >/dev/null || fail "sandbox entitlement missing"
! grep -E 'network|keychain|file-access' "$output_dir/NeedlbarWidgetExtension.entitlements" >/dev/null || fail "forbidden entitlement present"
[[ "$(wc -l < "$log" | tr -d ' ')" == 2 ]] || fail "expected sign and verify commands"
echo 'widget-extension build/metadata contract passed'
