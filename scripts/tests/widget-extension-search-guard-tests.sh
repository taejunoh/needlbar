#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$ROOT/scripts/tests/widget-extension-tests.sh"
fail() { echo "widget-extension-search-guard-tests: $*" >&2; exit 1; }

[[ -x "$TARGET" ]] || fail "missing executable script: $TARGET"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-widget-search-guard-test.XXXXXX")"
cleanup() { local status=$?; trap - EXIT; rm -rf -- "$temp_root"; exit "$status"; }
trap cleanup EXIT INT TERM

tools="$temp_root/tools"
mkdir -p "$tools"
for cmd in bash dirname mktemp mkdir cp chmod rm cat grep wc tr; do
  resolved="$(command -v "$cmd" 2>/dev/null || true)"
  [[ -n "$resolved" && -x "$resolved" ]] || fail "cannot resolve required command: $cmd"
  ln -s "$resolved" "$tools/$cmd"
done

if [[ -n "$(env PATH="$tools" "$tools/bash" -c 'command -v rg' 2>/dev/null || true)" ]]; then
  fail "sanity check failed: rg is resolvable from the controlled tool directory"
fi

make_rg_dir() {
  local dir="$1" status="$2"
  mkdir -p "$dir"
  for cmd in "$tools"/*; do ln -s "$(readlink "$cmd")" "$dir/$(basename "$cmd")"; done
  printf '#!/usr/bin/env bash\nexit %s\n' "$status" > "$dir/rg"
  chmod 755 "$dir/rg"
}

run_case() {
  local name="$1" path_dir="$2" status=0
  case_out="$temp_root/$name.out"
  case_err="$temp_root/$name.err"
  env PATH="$path_dir" "$tools/bash" "$TARGET" >"$case_out" 2>"$case_err" || status=$?
  case_status=$status
}

dump_and_fail() {
  echo "--- captured stdout ---" >&2
  cat "$case_out" >&2
  echo "--- captured stderr ---" >&2
  cat "$case_err" >&2
  echo "--- exit status: $case_status ---" >&2
  fail "$1"
}

# Case A: rg missing from PATH.
run_case missing "$tools"
[[ "$case_status" -ne 0 ]] || dump_and_fail "case A: expected non-zero status when rg is missing"
grep -Fq 'required search tool not found: rg' "$case_err" || dump_and_fail "case A: stderr lacks 'required search tool not found: rg'"
passed_status=0
grep -Fq 'contract passed' "$case_out" || passed_status=$?
[[ "$passed_status" -eq 1 ]] || dump_and_fail "case A: stdout reports 'contract passed' without rg (grep status $passed_status)"

# Case B: rg exits with an execution error (2).
make_rg_dir "$temp_root/rg-error" 2
run_case error "$temp_root/rg-error"
[[ "$case_status" -ne 0 ]] || dump_and_fail "case B: expected non-zero status when rg exits 2"
grep -Fq 'rg failed with status 2' "$case_err" || dump_and_fail "case B: stderr lacks 'rg failed with status 2'"

# Case C: rg finds a forbidden match (0).
make_rg_dir "$temp_root/rg-match" 0
run_case match "$temp_root/rg-match"
[[ "$case_status" -ne 0 ]] || dump_and_fail "case C: expected non-zero status when rg reports a match"
grep -Fq 'widget source contains a host/provider dependency' "$case_err" || dump_and_fail "case C: stderr lacks host/provider dependency message"

echo "widget-extension search-guard regression passed"
