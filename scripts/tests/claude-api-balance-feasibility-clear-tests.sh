#!/bin/sh
set -eu

output_file=$(mktemp "${TMPDIR:-/tmp}/needlbar-claude-api-balance-clear.XXXXXX")
watchdog_pid=""

cleanup() {
  if [ -n "$watchdog_pid" ]; then
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  rm -f "$output_file"
}
trap cleanup EXIT HUP INT TERM

swift build --product NeedlbarClaudeAPIBalanceFeasibility >/dev/null
bin_path=$(swift build --show-bin-path)
"$bin_path/NeedlbarClaudeAPIBalanceFeasibility" --clear-claude-api-balance-feasibility-store >"$output_file" 2>&1 &
clear_pid=$!
(
  sleep 20
  if kill -0 "$clear_pid" 2>/dev/null; then
    kill -TERM "$clear_pid" 2>/dev/null || true
  fi
) &
watchdog_pid=$!

if wait "$clear_pid"; then
  clear_status=0
else
  clear_status=$?
fi
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
watchdog_pid=""

if [ "$clear_status" -ne 0 ]; then
  echo "Claude API balance feasibility clear exited with status $clear_status" >&2
  exit 1
fi

if ! grep -Fx 'CLAUDE_API_BALANCE_FEASIBILITY storeDelete=succeeded' "$output_file" >/dev/null; then
  echo "Claude API balance feasibility clear did not confirm store deletion" >&2
  exit 1
fi

echo "Claude API balance feasibility clear regression passed"
