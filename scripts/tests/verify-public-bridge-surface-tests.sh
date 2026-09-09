#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$ROOT/scripts/verify-public-bridge-surface.sh"

fail() {
  echo "verify-public-bridge-surface-tests: $*" >&2
  exit 1
}

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-public-bridge-surface.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$temp_root"
  exit "$status"
}
trap cleanup EXIT

archive="$temp_root/libneedlbar_bridge.a"
header="$temp_root/needlbar.h"
printf '%s\n' 'public bridge archive' > "$archive"
printf '%s\n' 'const char *needlbar_usage_snapshot_json(void);' > "$header"

"$VERIFY" "$archive" "$header" || fail 'ordinary public bridge surface was rejected'

for marker in needlbar_test_ analytics_diagnostic_probe diagnostic_probe; do
  printf '%s\n' "$marker" > "$archive"
  if "$VERIFY" "$archive" "$header" >/dev/null 2>&1; then
    fail "archive marker was accepted: $marker"
  fi
  printf '%s\n' 'public bridge archive' > "$archive"

  printf '%s\n' "$marker" > "$header"
  if "$VERIFY" "$archive" "$header" >/dev/null 2>&1; then
    fail "header marker was accepted: $marker"
  fi
  printf '%s\n' 'const char *needlbar_usage_snapshot_json(void);' > "$header"
done

echo 'public bridge surface contract passed'
