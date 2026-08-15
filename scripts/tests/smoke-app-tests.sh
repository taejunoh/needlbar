#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SMOKE_SCRIPT="$ROOT/scripts/smoke-app.sh"
FIXTURES="$ROOT/scripts/tests/fixtures"

fail() {
  echo "smoke-app-tests: $*" >&2
  exit 1
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "did not expect '$needle' in '$haystack'"
}

test_pid_reuse_never_signals_mismatched_identity() (
  # Source-only access is intentional: production calls main only when executed.
  source "$SMOKE_SCRIPT"
  APP_PID=4242
  APP_PARENT_PID="$$"
  EXECUTABLE="/bundle/Needlbar"
  APP_IDENTITY_LSTART="Fri Aug 14 23:00:20 2026"
  FAKE_COMMAND="$EXECUTABLE"
  FAKE_LSTART="$APP_IDENTITY_LSTART"
  FAKE_PPID="$APP_PARENT_PID"
  KILL_CALLS=""
  WAIT_CALLS=0

  ps() {
    printf ' %s S %s %s\n' "$FAKE_PPID" "$FAKE_LSTART" "$FAKE_COMMAND"
  }
  kill() {
    if [[ "$1" == "-0" ]]; then
      return 0
    fi
    KILL_CALLS+="$*;"
    return 0
  }
  wait() {
    WAIT_CALLS=$((WAIT_CALLS + 1))
    return 0
  }
  sleep() { :; }

  capture_child_identity || fail "fixture child identity should capture"
  FAKE_COMMAND="/unrelated/reused-pid"
  set +e
  terminate_app
  terminate_status=$?
  set -e

  [[ "$terminate_status" -eq 1 ]] || fail "identity mismatch should fail cleanup"
  [[ "$WAIT_CALLS" -eq 1 ]] || fail "identity mismatch should safely wait exactly once"
  assert_not_contains "-TERM" "$KILL_CALLS"
  assert_not_contains "-KILL" "$KILL_CALLS"
)

run_launch_signal_case() (
  local fixture="$1"
  local expected_status="$2"
  local temp_root
  local pid_file
  local child_pid
  temp_root="$(mktemp -d)"
  pid_file="$temp_root/child.pid"
  mkdir -p "$temp_root/Needlbar.app/Contents"
  touch "$temp_root/Needlbar.app/Contents/Info.plist"

  set +e
  (
    source "$SMOKE_SCRIPT"
    APP_PATH="$temp_root/Needlbar.app"
    INFO_PLIST="$APP_PATH/Contents/Info.plist"
    EXECUTABLE="$fixture"
    APP_PARENT_PID="$$"
    APP_IDENTITY_LSTART=""
    PENDING_SIGNAL=""
    PENDING_STATUS=""
    export SMOKE_APP_TEST_PID_FILE="$pid_file"

    plutil() { :; }
    codesign() { :; }
    file() { printf '%s: arm64\n' "$1"; }
    # The fixture is a shell script, so its kernel command differs from the
    # production binary. This seam isolates signal-ordering while retaining
    # real launch, kill, wait, and trap behavior.
    ps() {
      printf ' %s S Fri Aug 14 23:00:20 2026 %s\n' "$APP_PARENT_PID" "$EXECUTABLE"
    }

    main
  )
  case_status=$?
  set -e

  [[ "$case_status" -eq "$expected_status" ]] || fail "expected signal exit $expected_status, got $case_status"
  [[ -s "$pid_file" ]] || fail "fixture did not record its child PID"
  child_pid="$(<"$pid_file")"
  [[ "$child_pid" =~ ^[0-9]+$ ]] || fail "fixture recorded an invalid child PID"
  if kill -0 "$child_pid" 2>/dev/null; then
    fail "signal-window child $child_pid remained after cleanup"
  fi
)

test_launch_window_int_is_deferred_and_reaped() {
  run_launch_signal_case "$FIXTURES/signal-int-child.sh" 130
}

test_launch_window_term_is_deferred_and_reaped() {
  run_launch_signal_case "$FIXTURES/signal-term-child.sh" 143
}

test_pid_reuse_never_signals_mismatched_identity
test_launch_window_int_is_deferred_and_reaped
test_launch_window_term_is_deferred_and_reaped
echo "smoke-app cleanup regressions passed"
