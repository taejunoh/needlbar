#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$ROOT/dist/Needlbar.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/Needlbar"
APP_PID=""
APP_LOG=""
APP_PARENT_PID="$$"
APP_IDENTITY_LSTART=""
PENDING_SIGNAL=""
PENDING_STATUS=""

fail() {
  echo "smoke-app: $*" >&2
  exit 1
}

signal_handler() {
  if [[ -z "$PENDING_STATUS" ]]; then
    PENDING_SIGNAL="$1"
    PENDING_STATUS="$2"
  fi
}

check_pending_signal() {
  if [[ -n "$PENDING_STATUS" ]]; then
    exit "$PENDING_STATUS"
  fi
}

read_child_snapshot() {
  [[ "$APP_PID" =~ ^[0-9]+$ ]] || return 1

  local snapshot
  snapshot="$(ps -o ppid= -o stat= -o lstart= -o command= -p "$APP_PID" 2>/dev/null)" || return 1
  [[ -n "$snapshot" ]] || return 1

  read -r CHILD_PPID CHILD_STATE CHILD_WEEKDAY CHILD_MONTH CHILD_DAY CHILD_TIME CHILD_YEAR CHILD_COMMAND <<<"$snapshot"
  [[ -n "${CHILD_PPID:-}" && -n "${CHILD_STATE:-}" && -n "${CHILD_COMMAND:-}" ]] || return 1
  CHILD_LSTART="$CHILD_WEEKDAY $CHILD_MONTH $CHILD_DAY $CHILD_TIME $CHILD_YEAR"
}

capture_child_identity() {
  read_child_snapshot || return 1
  [[ "$CHILD_PPID" == "$APP_PARENT_PID" ]] || return 1
  [[ "$CHILD_STATE" != Z* ]] || return 1
  [[ "$CHILD_COMMAND" == "$EXECUTABLE" ]] || return 1
  kill -0 "$APP_PID" 2>/dev/null || return 1
  APP_IDENTITY_LSTART="$CHILD_LSTART"
}

# Return 0 only for the child launched by this shell, 1 for an exited child,
# and 2 if the PID has a different identity and must never be signalled.
current_child_identity() {
  read_child_snapshot || return 1
  [[ "$CHILD_PPID" == "$APP_PARENT_PID" ]] || return 2
  # BSD ps marks a just-terminated child with E and can replace its command
  # with a parenthesized process name while it is being reaped. It is not a
  # reused PID and must not be treated as one.
  [[ "$CHILD_STATE" != Z* && "$CHILD_STATE" != *E* ]] || return 1
  [[ "$CHILD_COMMAND" == "$EXECUTABLE" ]] || return 2
  [[ "$CHILD_LSTART" == "$APP_IDENTITY_LSTART" ]] || return 2
  kill -0 "$APP_PID" 2>/dev/null || return 1
}

safe_wait_for_child() {
  [[ -n "$APP_PID" ]] || return 0
  wait "$APP_PID" 2>/dev/null || true
}

report_identity_mismatch() {
  echo "smoke-app: refusing to signal PID $APP_PID because its identity changed" >&2
}

clear_tracked_child() {
  APP_PID=""
  APP_IDENTITY_LSTART=""
}

terminate_app() {
  [[ -n "$APP_PID" ]] || return 0

  local identity_status
  if current_child_identity; then
    kill -TERM "$APP_PID" 2>/dev/null || true
  else
    identity_status=$?
    if [[ "$identity_status" -eq 2 ]]; then
      report_identity_mismatch
      clear_tracked_child
      return 1
    fi
    safe_wait_for_child
    clear_tracked_child
    return 0
  fi

  for _ in $(seq 1 20); do
    if current_child_identity; then
      sleep 0.1
      continue
    else
      identity_status=$?
      if [[ "$identity_status" -eq 2 ]]; then
        report_identity_mismatch
        clear_tracked_child
        return 1
      fi
      safe_wait_for_child
      clear_tracked_child
      return 0
    fi
  done

  # Re-check the complete identity directly before an uncatchable signal.
  if current_child_identity; then
    kill -KILL "$APP_PID" 2>/dev/null || true
  else
    identity_status=$?
    if [[ "$identity_status" -eq 2 ]]; then
      report_identity_mismatch
      clear_tracked_child
      return 1
    fi
  fi

  safe_wait_for_child
  clear_tracked_child
}

cleanup() {
  local status=$?
  local cleanup_status=0
  trap - EXIT INT TERM

  terminate_app || cleanup_status=1
  if [[ -n "$APP_LOG" ]]; then
    rm -f -- "$APP_LOG" || cleanup_status=1
  fi

  # A deferred signal keeps its conventional exit status even if the child
  # identity was lost before cleanup could safely signal it.
  if [[ "$status" -eq 130 || "$status" -eq 143 ]]; then
    exit "$status"
  fi
  if [[ "$status" -eq 0 && "$cleanup_status" -ne 0 ]]; then
    exit "$cleanup_status"
  fi
  exit "$status"
}

main() {
  trap cleanup EXIT
  trap 'signal_handler INT 130' INT
  trap 'signal_handler TERM 143' TERM

  [[ -d "$APP_PATH" ]] || fail "missing bundle: $APP_PATH (run make package first)"
  [[ -f "$INFO_PLIST" ]] || fail "missing bundle Info.plist: $INFO_PLIST"
  [[ -x "$EXECUTABLE" ]] || fail "missing executable: $EXECUTABLE"

  plutil -lint "$INFO_PLIST"
  codesign --verify --deep --strict "$APP_PATH"
  file "$EXECUTABLE" | grep -q 'arm64'

  APP_LOG="$(mktemp "${TMPDIR:-/tmp}/needlbar-smoke.XXXXXX")"
  "$EXECUTABLE" >"$APP_LOG" 2>&1 &
  APP_PID=$!

  # The signal handlers above only record a signal. Always assign the PID and
  # capture its full identity before honoring it, so cleanup cannot race launch.
  if ! capture_child_identity; then
    if [[ -n "$PENDING_STATUS" ]]; then
      check_pending_signal
    fi
    fail "could not capture the launched Needlbar child identity"
  fi
  check_pending_signal

  # A native accessory app should stay alive. Detect a launch failure promptly,
  # then let it run briefly enough for headless macOS CI without leaving it behind.
  for _ in $(seq 1 20); do
    sleep 0.1
    check_pending_signal
    if current_child_identity; then
      :
    else
      identity_status=$?
      if [[ "$identity_status" -eq 2 ]]; then
        report_identity_mismatch
        clear_tracked_child
        fail "Needlbar child identity changed during smoke"
      fi
      set +e
      wait "$APP_PID"
      app_status=$?
      set -e
      APP_PID=""
      cat "$APP_LOG" >&2 || true
      if [[ "$app_status" -ne 0 ]]; then
        fail "Needlbar exited immediately with status $app_status"
      fi
      fail "Needlbar exited before the smoke interval completed"
    fi
  done

  terminate_app
  echo "Needlbar app-bundle smoke passed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
