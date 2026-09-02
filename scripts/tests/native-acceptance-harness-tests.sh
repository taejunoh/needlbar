#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "native-acceptance-harness-tests: $*" >&2; exit 1; }
[[ -x "$ROOT/scripts/native-acceptance-run.sh" ]] || fail "missing native acceptance harness"

temp_root="$(mktemp -d /Users/taejunoh/Developer/LFG/native-acceptance-harness-test.XXXXXX)"
cleanup() { local status=$?; trap - EXIT INT TERM; rm -rf -- "$temp_root"; exit "$status"; }
trap cleanup EXIT INT TERM

mkdir -p "$temp_root/public" "$temp_root/acceptance/Needlbar.app/Contents/MacOS" "$temp_root/inputs" "$temp_root/evidence"
touch "$temp_root/public/Needlbar-macos-arm64.zip" "$temp_root/acceptance/Needlbar.app/Contents/MacOS/Needlbar"

if bash "$ROOT/scripts/native-acceptance-run.sh" \
  --public-zip "$temp_root/public/Needlbar-macos-arm64.zip" \
  --acceptance-app "$temp_root/acceptance/Needlbar.app" \
  --fixtures-root "$temp_root/inputs" \
  --evidence-root "$temp_root/evidence" \
  --case parser-malformed >/dev/null 2>&1; then
  fail "harness unexpectedly accepted an empty fixture root"
fi

echo 'native acceptance harness contract passed'
