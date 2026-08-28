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

cat > "$fake_bin/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF

chmod 755 "$fake_bin/rustup" "$fake_bin/make" "$fake_bin/swift" "$fake_bin/codesign"

executable_source="$fixture_root/.build/arm64-apple-macosx/release/Needlbar"
printf '%s\n' 'stale executable' > "$executable_source"

if ! PATH="$fake_bin:$PATH" NEEDLBAR_PACKAGE_EXECUTABLE="$executable_source" \
  "$fixture_root/scripts/package-app.sh"; then
  fail 'release packaging should relink when a stale executable already exists'
fi

[[ "$(<"$executable_source")" == 'fresh executable' ]] || \
  fail 'stubbed Swift build did not produce a fresh executable'
[[ "$(<"$fixture_root/dist/Needlbar.app/Contents/MacOS/Needlbar")" == 'fresh executable' ]] || \
  fail 'package did not install the freshly relinked executable'
[[ -f "$fixture_root/dist/Needlbar-macos-arm64.zip" ]] || \
  fail 'package zip was not produced'

echo 'package-app relink regression passed'
