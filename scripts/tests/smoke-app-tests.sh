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

test_live_identity_mismatch_never_waits_or_signals() {
  # Source-only access is intentional: production calls main only when executed.
  source "$SMOKE_SCRIPT"
  EXECUTABLE="$ROOT/dist/Needlbar.app/Contents/MacOS/Needlbar"
  [[ -x "$EXECUTABLE" ]] || fail "package the app before running smoke cleanup tests"
  APP_PARENT_PID="$$"
  KILL_CALLS=""
  WAIT_CALLS=0
  LIVE_CHILD_PID=""
  LIVE_CHILD_PPID=""
  LIVE_CHILD_COMMAND=""
  LIVE_CHILD_LSTART=""

  read_live_child_identity() {
    local snapshot
    snapshot="$(command ps -o ppid= -o stat= -o lstart= -o command= -p "$LIVE_CHILD_PID" 2>/dev/null)" || return 1
    [[ -n "$snapshot" ]] || return 1
    read -r OBSERVED_PPID OBSERVED_STATE OBSERVED_WEEKDAY OBSERVED_MONTH OBSERVED_DAY OBSERVED_TIME OBSERVED_YEAR OBSERVED_COMMAND <<<"$snapshot"
    [[ -n "${OBSERVED_PPID:-}" && -n "${OBSERVED_STATE:-}" && -n "${OBSERVED_COMMAND:-}" ]] || return 1
    OBSERVED_LSTART="$OBSERVED_WEEKDAY $OBSERVED_MONTH $OBSERVED_DAY $OBSERVED_TIME $OBSERVED_YEAR"
  }
  capture_live_child_identity() {
    read_live_child_identity || return 1
    [[ "$OBSERVED_PPID" == "$$" && "$OBSERVED_COMMAND" == "$EXECUTABLE" ]] || return 1
    [[ "$OBSERVED_STATE" != Z* && "$OBSERVED_STATE" != *E* ]] || return 1
    LIVE_CHILD_PPID="$OBSERVED_PPID"
    LIVE_CHILD_COMMAND="$OBSERVED_COMMAND"
    LIVE_CHILD_LSTART="$OBSERVED_LSTART"
  }
  live_child_identity_matches() {
    read_live_child_identity || return 1
    [[ "$OBSERVED_PPID" == "$LIVE_CHILD_PPID" ]] || return 2
    [[ "$OBSERVED_COMMAND" == "$LIVE_CHILD_COMMAND" && "$OBSERVED_COMMAND" == "$EXECUTABLE" ]] || return 2
    [[ "$OBSERVED_LSTART" == "$LIVE_CHILD_LSTART" ]] || return 2
    [[ "$OBSERVED_STATE" != Z* && "$OBSERVED_STATE" != *E* ]] || return 1
  }

  cleanup_live_child() {
    if [[ "$LIVE_CHILD_PID" =~ ^[0-9]+$ ]] && live_child_identity_matches; then
      /bin/kill -TERM "$LIVE_CHILD_PID" 2>/dev/null || true
      for _ in $(seq 1 20); do
        if live_child_identity_matches; then
          sleep 0.1
          continue
        else
          identity_status=$?
          [[ "$identity_status" -eq 1 ]] && builtin wait "$LIVE_CHILD_PID" 2>/dev/null || true
          break
        fi
      done
    fi
  }
  finish_live_child() {
    local cleanup_status=$?
    trap - EXIT INT TERM
    cleanup_live_child
    exit "$cleanup_status"
  }
  trap finish_live_child EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  "$EXECUTABLE" >/dev/null 2>&1 &
  LIVE_CHILD_PID=$!
  capture_live_child_identity || fail "live child cleanup identity should capture"

  APP_PID="$LIVE_CHILD_PID"
  capture_child_identity || fail "live child identity should capture"

  ps() {
    printf ' 999999 S Sat Aug 15 00:00:00 2026 /unrelated/reused-pid\n'
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

  SECONDS=0
  set +e
  terminate_app
  terminate_status=$?
  set -e

  [[ "$terminate_status" -eq 1 ]] || fail "identity mismatch should fail cleanup"
  [[ "$SECONDS" -le 1 ]] || fail "identity mismatch cleanup was not bounded"
  [[ "$WAIT_CALLS" -eq 0 ]] || fail "identity mismatch must not synchronously wait"
  assert_not_contains "-TERM" "$KILL_CALLS"
  assert_not_contains "-KILL" "$KILL_CALLS"
  [[ -z "$APP_PID" && -z "$APP_IDENTITY_LSTART" ]] || fail "mismatch must clear tracked child identity"
  expected_live_command="$LIVE_CHILD_COMMAND"
  LIVE_CHILD_COMMAND="/unrelated/reused-pid"
  cleanup_live_child
  /bin/kill -0 "$LIVE_CHILD_PID" 2>/dev/null || fail "cleanup signalled a mismatched live child"
  LIVE_CHILD_COMMAND="$expected_live_command"
  cleanup_live_child
  trap - EXIT INT TERM
  unset -f ps kill wait sleep
}

run_launch_signal_case() (
  local fixture="$1"
  local expected_status="$2"
  local temp_root=""
  local temp_root_valid=0
  local temp_candidate=""
  local pid_file=""
  local child_pid=""

  cleanup_signal_case() {
    local cleanup_status=$?
    trap - EXIT INT TERM
    # The nested smoke runner owns and verifies the fixture child. This outer
    # scope never signals a PID it did not identity-capture at spawn time.
    if [[ "$temp_root_valid" -eq 1 && "$temp_root" == "${TMPDIR:-/tmp}/needlbar-smoke-test."* ]]; then
      rm -rf -- "$temp_root"
    fi
    exit "$cleanup_status"
  }
  trap cleanup_signal_case EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  temp_candidate="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-smoke-test.XXXXXX")"
  if [[ "$temp_candidate" != "${TMPDIR:-/tmp}/needlbar-smoke-test."* ]]; then
    rmdir -- "$temp_candidate" 2>/dev/null || true
    fail "unexpected test directory: $temp_candidate"
  fi
  temp_root="$temp_candidate"
  temp_root_valid=1
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
  for _ in $(seq 1 20); do
    kill -0 "$child_pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$child_pid" 2>/dev/null; then
    child_state="$(ps -o ppid= -o stat= -o command= -p "$child_pid" 2>/dev/null || true)"
    fail "signal-window child $child_pid remained after cleanup: $child_state"
  fi
)

test_launch_window_int_is_deferred_and_reaped() {
  run_launch_signal_case "$FIXTURES/signal-int-child.sh" 130
}

test_launch_window_term_is_deferred_and_reaped() {
  run_launch_signal_case "$FIXTURES/signal-term-child.sh" 143
}

count_fixture_directories() {
  find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'needlbar-smoke-test.*' -print | wc -l | tr -d '[:space:]'
}

fixture_dirs_before="$(count_fixture_directories)"
test_live_identity_mismatch_never_waits_or_signals
test_launch_window_int_is_deferred_and_reaped
test_launch_window_term_is_deferred_and_reaped
fixture_dirs_after="$(count_fixture_directories)"
[[ "$fixture_dirs_after" == "$fixture_dirs_before" ]] || fail "signal fixtures left temporary directories behind"
echo "smoke-app cleanup regressions passed"
