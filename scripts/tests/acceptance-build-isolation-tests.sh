#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "acceptance-build-isolation-tests: $*" >&2; exit 1; }

[[ -x "$ROOT/scripts/package-app.sh" ]] || fail "missing public package script"
[[ -x "$ROOT/scripts/package-acceptance-app.sh" ]] || fail "missing acceptance package script"

! NEEDLBAR_ACCEPTANCE_DRIVER=1 "$ROOT/scripts/package-app.sh" >/tmp/needlbar-public.out 2>/tmp/needlbar-public.err ||
  fail "public package unexpectedly accepted acceptance mode"
grep -F -- 'acceptance driver is forbidden in public packaging' /tmp/needlbar-public.err >/dev/null ||
  fail "public package rejection was not explicit"

! grep -F -- '--acceptance-fixture' "$ROOT/.github/workflows/release.yml" >/dev/null || fail "release workflow exposes acceptance fixture"
! grep -F -- 'package-acceptance-app.sh' "$ROOT/.github/workflows/release.yml" >/dev/null || fail "release workflow selects acceptance package"
! grep -F -- 'AcceptanceFixture' "$ROOT/WidgetExtension/NeedlbarOverviewWidget.swift" >/dev/null || fail "widget source exposes acceptance fixture"

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-acceptance-isolation.XXXXXX")"
cleanup() { local status=$?; trap - EXIT; rm -rf -- "$temp_root" /tmp/needlbar-public.out /tmp/needlbar-public.err; exit "$status"; }
trap cleanup EXIT INT TERM

fake_bin="$temp_root/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == build ]] || exit 0
count=0
for argument in "$@"; do [[ "$argument" == -DNEEDLBAR_ACCEPTANCE_DRIVER ]] && count=$((count + 1)); done
[[ "$count" == 1 ]] || exit 2
repo=''; previous=''
for argument in "$@"; do if [[ "$previous" == --package-path ]]; then repo="$argument"; fi; previous="$argument"; done
printf 'swift:%s:%s\n' "$count" "$*" >> "$FAKE_LOG"
mkdir -p "$repo/.build/arm64-apple-macosx/release"
printf '%s\n' --acceptance-fixture > "$repo/.build/arm64-apple-macosx/release/Needlbar"
EOF
cat > "$fake_bin/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == -C ]] || exit 2
mkdir -p "$2/target/release"
printf '%s\n' synthetic-bridge > "$2/target/release/libneedlbar_bridge.a"
EOF
cat > "$fake_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == '--sdk macosx --show-sdk-path' ]]; then printf '%s\n' /SyntheticMacOSX.sdk; exit 0; fi
[[ "${1:-}" == swiftc ]] || exit 2
[[ "$*" != *NEEDLBAR_ACCEPTANCE_DRIVER* ]] || exit 3
printf 'xcrun:%s\n' "$*" >> "$FAKE_LOG"
output=''; previous=''
for argument in "$@"; do if [[ "$previous" == -o ]]; then output="$argument"; fi; previous="$argument"; done
mkdir -p "$(dirname "$output")"
printf '%s\n' synthetic-widget-extension > "$output"
chmod 755 "$output"
EOF
cat > "$fake_bin/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${@: -1}"
printf 'codesign:%s\n' "$*" >> "$FAKE_LOG"
if [[ "${1:-}" == --force && "$target" == *Needlbar.app ]]; then [[ "$*" == *'--options runtime'* ]] || exit 4; fi
EOF
chmod 755 "$fake_bin/swift" "$fake_bin/make" "$fake_bin/xcrun" "$fake_bin/codesign"

acceptance_output="$ROOT/.build/acceptance-build-isolation-test"
rm -rf -- "$acceptance_output"
PATH="$fake_bin:$PATH" FAKE_LOG="$temp_root/tool.log" \
  NEEDLBAR_ACCEPTANCE_OUTPUT_ROOT="$acceptance_output" \
  NEEDLBAR_CODESIGN_IDENTITY='Developer ID Application: Test (TEAM123)' \
  NEEDLBAR_TEAM_ID='TEAM123' \
  NEEDLBAR_APP_GROUP_IDENTIFIER='TEAM123.com.taejunoh.needlbar' \
  "$ROOT/scripts/package-acceptance-app.sh" >/dev/null

[[ -x "$acceptance_output/Needlbar.app/Contents/MacOS/Needlbar" ]] || fail 'acceptance host executable missing'
grep -F -- '--acceptance-fixture' "$acceptance_output/Needlbar.app/Contents/MacOS/Needlbar" >/dev/null || fail 'acceptance parser missing from host'
! grep -F -- '--acceptance-fixture' "$acceptance_output/Needlbar.app/Contents/PlugIns/NeedlbarWidgetExtension.appex/Contents/MacOS/NeedlbarWidgetExtension" >/dev/null || fail 'acceptance parser entered extension'
[[ "$(grep -c '^swift:1:' "$temp_root/tool.log")" == 1 ]] || fail 'host acceptance define count was not exactly one'
! grep -F 'NEEDLBAR_ACCEPTANCE_DRIVER' "$temp_root/tool.log" | grep -F 'xcrun:' >/dev/null || fail 'extension received acceptance define'
extension_sign="$(grep -n 'NeedlbarWidgetExtension.appex' "$temp_root/tool.log" | head -n 1 | cut -d: -f1)"
host_sign="$(grep -n 'Needlbar.app' "$temp_root/tool.log" | head -n 1 | cut -d: -f1)"
[[ "$extension_sign" =~ ^[0-9]+$ && "$host_sign" =~ ^[0-9]+$ && "$extension_sign" -lt "$host_sign" ]] || fail 'extension was not signed before host'
grep -F -- '--options runtime' "$temp_root/tool.log" >/dev/null || fail 'host did not request hardened runtime'
! find "$acceptance_output" -type f \( -name '*.zip' -o -name '*.sha256' \) -print -quit | grep -q . || fail 'acceptance package created release artifact'
rm -rf -- "$acceptance_output" "$ROOT/.build/widget-extension"

echo 'acceptance build isolation contract passed'
