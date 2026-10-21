#!/usr/bin/env bash
set -euo pipefail

readonly RG_VERSION=14.1.1
readonly RG_SHA256=24ad76777745fbff131c8fbc466742b011f925bfa4fffa2ded6def23b5b937be
readonly RG_NAME="ripgrep-${RG_VERSION}-aarch64-apple-darwin"
readonly RG_URL="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/${RG_NAME}.tar.gz"

fail() { echo "install-ci-ripgrep: $*" >&2; exit 1; }

[[ -n "${GITHUB_PATH:-}" ]] || fail "GITHUB_PATH is not set"
install_root="${1:-${RUNNER_TEMP:?RUNNER_TEMP is not set}/ripgrep}"
archive="$install_root/$RG_NAME.tar.gz"
mkdir -p "$install_root"

if curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$archive" "$RG_URL"; then
  printf '%s  %s\n' "$RG_SHA256" "$archive" | shasum -a 256 -c - >/dev/null ||
    fail "checksum mismatch for $RG_NAME.tar.gz"
  tar -xzf "$archive" -C "$install_root"
  rg_dir="$install_root/$RG_NAME"
else
  echo "install-ci-ripgrep: pinned download failed; falling back to Homebrew (unpinned)" >&2
  HOMEBREW_NO_AUTO_UPDATE=1 brew install ripgrep || fail "Homebrew fallback failed"
  rg_prefix="$(brew --prefix ripgrep)" || fail "cannot resolve Homebrew ripgrep prefix"
  rg_dir="$rg_prefix/bin"
fi

[[ -x "$rg_dir/rg" ]] || fail "rg executable missing in $rg_dir"
"$rg_dir/rg" --version
printf '%s\n' "$rg_dir" >> "$GITHUB_PATH"
