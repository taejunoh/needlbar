#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/install-ci-ripgrep.sh"
fail() { echo "install-ci-ripgrep-tests: $*" >&2; exit 1; }

readonly PINNED_SHA=24ad76777745fbff131c8fbc466742b011f925bfa4fffa2ded6def23b5b937be
readonly RG_NAME=ripgrep-14.1.1-aarch64-apple-darwin
readonly RG_URL="https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/$RG_NAME.tar.gz"

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-install-ci-ripgrep-test.XXXXXX")"
cleanup() { local status=$?; trap - EXIT; rm -rf -- "$temp_root"; exit "$status"; }
trap cleanup EXIT INT TERM

fake_bin="$temp_root/bin"
logs="$temp_root/logs"
mkdir -p "$fake_bin" "$logs"

# Real tarball served by the fake curl.
tarball_src="$temp_root/tarball-src"
mkdir -p "$tarball_src/$RG_NAME"
cat > "$tarball_src/$RG_NAME/rg" <<'RG'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then echo "ripgrep 14.1.1"; fi
RG
chmod 755 "$tarball_src/$RG_NAME/rg"
fake_tarball="$temp_root/fake-ripgrep.tar.gz"
tar -czf "$fake_tarball" -C "$tarball_src" "$RG_NAME"

cat > "$fake_bin/curl" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG_DIR/curl.log"
status="${FAKE_CURL_STATUS:-0}"
[[ "$status" == "0" ]] || exit "$status"
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then out="$2"; shift; fi
  shift
done
[[ -n "$out" ]] || exit 2
cp "$FAKE_TARBALL" "$out"
FAKE
cat > "$fake_bin/shasum" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG_DIR/shasum.log"
cat > "$FAKE_LOG_DIR/shasum.stdin"
exit "${FAKE_SHASUM_STATUS:-0}"
FAKE
cat > "$fake_bin/brew" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG_DIR/brew.log"
echo "HOMEBREW_NO_AUTO_UPDATE=${HOMEBREW_NO_AUTO_UPDATE:-}" >> "$FAKE_LOG_DIR/brew.env"
case "$*" in
  "install ripgrep") exit "${FAKE_BREW_STATUS:-0}" ;;
  "--prefix ripgrep") echo "$FAKE_BREW_PREFIX" ;;
  *) exit 99 ;;
esac
FAKE
chmod 755 "$fake_bin/curl" "$fake_bin/shasum" "$fake_bin/brew"

out_file=""
err_file=""
run_status=0
case_dir=""
github_path=""
install_dir=""

# run_case NAME [with_github_path=1] — env vars for fakes come from the caller's environment.
run_case() {
  local name="$1" with_gp="${2:-1}"
  case_dir="$temp_root/case-$name"
  mkdir -p "$case_dir/logs"
  install_dir="$case_dir/install"
  github_path="$case_dir/github_path"
  : > "$github_path"
  out_file="$case_dir/stdout"
  err_file="$case_dir/stderr"
  run_status=0
  if [[ "$with_gp" == "1" ]]; then
    env PATH="$fake_bin:$PATH" FAKE_LOG_DIR="$case_dir/logs" FAKE_TARBALL="$fake_tarball" \
      GITHUB_PATH="$github_path" "$SCRIPT" "$install_dir" >"$out_file" 2>"$err_file" || run_status=$?
  else
    env -u GITHUB_PATH PATH="$fake_bin:$PATH" FAKE_LOG_DIR="$case_dir/logs" FAKE_TARBALL="$fake_tarball" \
      "$SCRIPT" "$install_dir" >"$out_file" 2>"$err_file" || run_status=$?
  fi
}

check_fail() {
  echo "--- case dir: $case_dir (status $run_status) ---" >&2
  echo "--- stdout ---" >&2; cat "$out_file" >&2
  echo "--- stderr ---" >&2; cat "$err_file" >&2
  echo "--- GITHUB_PATH ---" >&2; cat "$github_path" >&2 2>/dev/null || true
  for f in "$case_dir"/logs/*; do
    [[ -f "$f" ]] || continue
    echo "--- $(basename "$f") ---" >&2; cat "$f" >&2
  done
  fail "$1"
}

log() { echo "$case_dir/logs/$1"; }
expect_status_zero() { [[ "$run_status" -eq 0 ]] || check_fail "expected status 0, got $run_status"; }
expect_status_nonzero() { [[ "$run_status" -ne 0 ]] || check_fail "expected non-zero status"; }
expect_contains() { grep -Fq -- "$2" "$1" || check_fail "expected $1 to contain: $2"; }
expect_no_log() { [[ ! -e "$(log "$1")" ]] || check_fail "expected $1 not to exist (tool was invoked)"; }
expect_gp_empty() { [[ ! -s "$github_path" ]] || check_fail "expected GITHUB_PATH to stay empty"; }
expect_gp_exact() {
  [[ "$(wc -l < "$github_path" | tr -d ' ')" == "1" ]] || check_fail "expected exactly one GITHUB_PATH line"
  [[ "$(cat "$github_path")" == "$1" ]] || check_fail "expected GITHUB_PATH line: $1"
}

# 1. Pinned success.
FAKE_CURL_STATUS=0 FAKE_SHASUM_STATUS=0 run_case pinned-success
expect_status_zero
expect_contains "$(log curl.log)" "--proto =https"
expect_contains "$(log curl.log)" "--tlsv1.2"
expect_contains "$(log curl.log)" "-f"
expect_contains "$(log curl.log)" "$RG_URL"
expect_contains "$(log shasum.stdin)" "$PINNED_SHA"
expect_contains "$(log shasum.stdin)" "$install_dir/$RG_NAME.tar.gz"
expect_gp_exact "$install_dir/$RG_NAME"
expect_no_log brew.log
expect_contains "$out_file" "ripgrep 14.1.1"

# 2. Checksum mismatch: fail, no Homebrew fallback.
FAKE_CURL_STATUS=0 FAKE_SHASUM_STATUS=1 run_case checksum-mismatch
expect_status_nonzero
expect_contains "$err_file" "checksum mismatch"
expect_no_log brew.log
expect_gp_empty

# 3. Download failure: Homebrew fallback succeeds.
brew_prefix="$temp_root/brew-prefix"
mkdir -p "$brew_prefix/bin"
cp "$tarball_src/$RG_NAME/rg" "$brew_prefix/bin/rg"
chmod 755 "$brew_prefix/bin/rg"
FAKE_CURL_STATUS=22 FAKE_BREW_STATUS=0 FAKE_BREW_PREFIX="$brew_prefix" run_case brew-fallback
expect_status_zero
expect_contains "$err_file" "falling back to Homebrew"
expect_contains "$(log brew.log)" "install ripgrep"
expect_contains "$(log brew.env)" "HOMEBREW_NO_AUTO_UPDATE=1"
expect_gp_exact "$brew_prefix/bin"

# 4. Download failure and Homebrew failure.
FAKE_CURL_STATUS=22 FAKE_BREW_STATUS=1 FAKE_BREW_PREFIX="$brew_prefix" run_case brew-fails
expect_status_nonzero
expect_gp_empty

# 5. Missing GITHUB_PATH.
FAKE_CURL_STATUS=0 run_case missing-github-path 0
expect_status_nonzero
expect_contains "$err_file" "GITHUB_PATH"
expect_no_log curl.log

echo "install-ci-ripgrep regression passed"
