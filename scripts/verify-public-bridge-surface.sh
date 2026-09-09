#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" != 2 ]]; then
  echo 'usage: verify-public-bridge-surface.sh <bridge-archive> <public-header>' >&2
  exit 2
fi

archive="$1"
header="$2"
[[ -r "$archive" && -r "$header" ]] || {
  echo 'public bridge surface inputs are unreadable' >&2
  exit 2
}

for marker in needlbar_test_ analytics_diagnostic_probe diagnostic_probe; do
  if grep -aFq -- "$marker" "$archive" || grep -Fq -- "$marker" "$header"; then
    echo 'public bridge surface contains a prohibited nonshipping marker' >&2
    exit 1
  fi
done
