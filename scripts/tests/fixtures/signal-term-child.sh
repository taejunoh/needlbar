#!/usr/bin/env bash
if [[ -n "${SMOKE_APP_TEST_PID_FILE:-}" ]]; then
  printf '%s\n' "$$" > "$SMOKE_APP_TEST_PID_FILE"
fi
kill -TERM "$PPID"
while :; do
  sleep 1
done
