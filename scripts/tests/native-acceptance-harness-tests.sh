#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "native-acceptance-harness-tests: $*" >&2; exit 1; }
[[ -x "$ROOT/scripts/native-acceptance-run.sh" ]] || fail "missing native acceptance harness"

temp_root="$(mktemp -d /Users/taejunoh/Developer/LFG/native-acceptance-harness-test.XXXXXX)"
cleanup() { local status=$?; trap - EXIT INT TERM; rm -rf -- "$temp_root"; exit "$status"; }
trap cleanup EXIT INT TERM

mkdir -p "$temp_root/public" "$temp_root/acceptance/Needlbar.app/Contents/MacOS" "$temp_root/inputs" "$temp_root/evidence" "$temp_root/bin"
touch "$temp_root/public/Needlbar-macos-arm64.zip"
cat > "$temp_root/acceptance/Needlbar.app/Contents/MacOS/Needlbar" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' fixtureMalformedJSON >&2
exit 64
EOF
chmod 755 "$temp_root/acceptance/Needlbar.app/Contents/MacOS/Needlbar"
cat > "$temp_root/bin/sw_vers" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 14.6.1
EOF
cat > "$temp_root/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' arm64
EOF
cat > "$temp_root/bin/networksetup" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -listallnetworkservices ]]; then printf '%s\n' 'An asterisk (*) denotes that a network service is disabled.' 'Test Wi-Fi'; else printf '%s\n' Disabled; fi
EOF
chmod 755 "$temp_root/bin/sw_vers" "$temp_root/bin/uname" "$temp_root/bin/networksetup"

PATH="$temp_root/bin:$PATH" bash "$ROOT/scripts/native-acceptance-run.sh" \
  --public-zip "$temp_root/public/Needlbar-macos-arm64.zip" \
  --acceptance-app "$temp_root/acceptance/Needlbar.app" \
  --fixtures-root "$temp_root/inputs" \
  --evidence-root "$temp_root/evidence" \
  --case parser-malformed >/dev/null 2>&1
grep -F $'parser\tfixtureMalformedJSON\t64' "$temp_root/evidence/manifest.tsv" >/dev/null || fail "stable parser failure was not recorded"
[[ ! -e "$temp_root/evidence/parser.stderr" ]] || fail "raw parser stderr was retained"
[[ ! -e "$temp_root/inputs/runtime-parser-malformed.json" ]] || fail "generated fixture was not cleaned"

rm -rf -- "$temp_root/evidence"; mkdir -p "$temp_root/evidence"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" 15.0\n' > "$temp_root/bin/sw_vers"; chmod 755 "$temp_root/bin/sw_vers"
if PATH="$temp_root/bin:$PATH" bash "$ROOT/scripts/native-acceptance-run.sh" \
  --public-zip "$temp_root/public/Needlbar-macos-arm64.zip" \
  --acceptance-app "$temp_root/acceptance/Needlbar.app" \
  --fixtures-root "$temp_root/inputs" \
  --evidence-root "$temp_root/evidence" \
  --case parser-malformed >/dev/null 2>&1; then
  fail "unsupported macOS was accepted"
fi
grep -F $'preflight\tnativeUnsupportedOS\t70' "$temp_root/evidence/manifest.tsv" >/dev/null || fail "unsupported OS code was not recorded"

rm -rf -- "$temp_root/evidence"; mkdir -p "$temp_root/evidence"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" 14.6.1\n' > "$temp_root/bin/sw_vers"; chmod 755 "$temp_root/bin/sw_vers"
cat > "$temp_root/bin/networksetup" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -listallnetworkservices ]]; then printf '%s\n' 'Test Wi-Fi'; else printf '%s\n' Enabled; fi
EOF
chmod 755 "$temp_root/bin/networksetup"
if PATH="$temp_root/bin:$PATH" bash "$ROOT/scripts/native-acceptance-run.sh" \
  --public-zip "$temp_root/public/Needlbar-macos-arm64.zip" \
  --acceptance-app "$temp_root/acceptance/Needlbar.app" \
  --fixtures-root "$temp_root/inputs" \
  --evidence-root "$temp_root/evidence" \
  --case parser-malformed >/dev/null 2>&1; then
  fail "enabled network was accepted"
fi
grep -F $'preflight\tnativeNetworkEnabled\t72' "$temp_root/evidence/manifest.tsv" >/dev/null || fail "network guard code was not recorded"

echo 'native acceptance harness contract passed'
