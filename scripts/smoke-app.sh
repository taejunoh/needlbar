#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/dist/Needlbar.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/Needlbar"
APP_PID=""
APP_LOG=""

fail() {
  echo "smoke-app: $*" >&2
  exit 1
}

process_is_running() {
  [[ -n "$APP_PID" ]] || return 1
  kill -0 "$APP_PID" 2>/dev/null || return 1
  local state
  state="$(ps -o stat= -p "$APP_PID" 2>/dev/null | tr -d '[:space:]')"
  [[ -n "$state" && "$state" != Z* ]]
}

terminate_app() {
  [[ -n "$APP_PID" ]] || return 0

  if process_is_running; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      process_is_running || break
      sleep 0.1
    done
  fi

  if process_is_running; then
    kill -KILL "$APP_PID" 2>/dev/null || true
  fi
  wait "$APP_PID" 2>/dev/null || true
  APP_PID=""
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  terminate_app
  if [[ -n "$APP_LOG" ]]; then
    rm -f -- "$APP_LOG"
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -d "$APP_PATH" ]] || fail "missing bundle: $APP_PATH (run make package first)"
[[ -f "$INFO_PLIST" ]] || fail "missing bundle Info.plist: $INFO_PLIST"
[[ -x "$EXECUTABLE" ]] || fail "missing executable: $EXECUTABLE"

plutil -lint "$INFO_PLIST"
codesign --verify --deep --strict "$APP_PATH"
file "$EXECUTABLE" | grep -q 'arm64'

APP_LOG="$(mktemp "${TMPDIR:-/tmp}/needlbar-smoke.XXXXXX")"
"$EXECUTABLE" >"$APP_LOG" 2>&1 &
APP_PID=$!

# A native accessory app should stay alive. Detect a launch failure promptly,
# then let it run briefly enough for headless macOS CI without leaving it behind.
for _ in $(seq 1 20); do
  sleep 0.1
  if ! process_is_running; then
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
