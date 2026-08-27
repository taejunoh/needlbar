#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SCRIPT_UNDER_TEST="$ROOT/scripts/notarize-app.sh"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-notarize-test.XXXXXX")"
fake_bin="$temp_root/fake-bin"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  rm -rf -- "$temp_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -x "$SCRIPT_UNDER_TEST" ]] || {
  echo "notarize-app-tests: missing executable script: $SCRIPT_UNDER_TEST" >&2
  exit 1
}

fail() {
  echo "notarize-app-tests: $*" >&2
  exit 1
}

mkdir -p "$fake_bin"

cat > "$fake_bin/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

case "$1" in
  list-keychains)
    if [[ "${FAKE_EMPTY_KEYCHAIN_LIST:-}" == 1 ]]; then exit 0; fi
    if [[ " $* " == *' -s '* && " $* " == *'signing.keychain-db'* ]]; then record_stage security:set-list
    elif [[ " $* " == *' -s '* ]]; then record_stage security:restore-list
    else printf '    "/fake/original.keychain-db"\n'; fi ;;
  create-keychain) record_stage security:create-keychain ;;
  import) record_stage security:import ;;
  delete-keychain) record_stage security:delete-keychain ;;
  find-identity)
    printf '  1) ABCDEF0123456789 "%s"\n' \
      "${FAKE_SECURITY_IDENTITIES:-Developer ID Application: Test Signer (3BMF4LM6TM)}" ;;
  set-keychain-settings|unlock-keychain|set-key-partition-list) : ;;
  *) exit 64 ;;
esac
EOF

cat > "$fake_bin/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

case "$1" in
  --force) record_stage codesign:sign ;;
  --verify) record_stage codesign:verify ;;
  --display)
    record_stage codesign:display
    printf 'Authority=Developer ID Application: Test Signer (3BMF4LM6TM)\n'
    printf 'TeamIdentifier=%s\n' "${FAKE_CODESIGN_TEAM_ID-3BMF4LM6TM}"
    printf 'Runtime Version=%s\n' "${FAKE_CODESIGN_RUNTIME-14.0.0}" ;;
  *) exit 64 ;;
esac
EOF

cat > "$fake_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

case "$1" in
  notarytool)
    record_stage xcrun:notarytool-submit
    [[ "${FAKE_NOTARY_STDERR_CANARY:-}" == '' ]] || printf '%s\n' "$FAKE_NOTARY_STDERR_CANARY" >&2
    [[ "${FAKE_NOTARY_FAIL:-}" != 1 ]] || exit 71
    if [[ -n "${FAKE_NOTARY_SIGNAL:-}" ]]; then
      case "$FAKE_NOTARY_SIGNAL" in
        INT|TERM) kill "-$FAKE_NOTARY_SIGNAL" "$PPID" ;;
        *) exit 64 ;;
      esac
    fi ;;
  stapler)
    if [[ "$2" == staple ]]; then record_stage xcrun:stapler-staple; [[ "${FAKE_STAPLE_FAIL:-}" != 1 ]] || exit 72
    elif [[ "$2" == validate ]]; then record_stage xcrun:stapler-validate; [[ "${FAKE_STAPLER_VALIDATE_FAIL:-}" != 1 ]] || exit 73
    else exit 64; fi ;;
  *) exit 64 ;;
esac
EOF

cat > "$fake_bin/spctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

count=0; [[ ! -f "$FAKE_STATE_DIR/spctl-count" ]] || count="$(<"$FAKE_STATE_DIR/spctl-count")"
count=$((count + 1)); printf '%s\n' "$count" > "$FAKE_STATE_DIR/spctl-count"
record_stage spctl:assess
if [[ "${FAKE_SPCTL_FAIL:-}" == 1 ]] || { [[ "${FAKE_EXTRACTED_SPCTL_FAIL:-}" == 1 ]] && [[ "$count" -eq 2 ]]; }; then
  exit 74
fi
EOF

cat > "$fake_bin/zip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

[[ "$1" == '-qryX' && "$3" == 'Needlbar.app' ]] || exit 64
output_path="$2"
case "$output_path" in
  */notarization-submission.zip) record_stage zip:submission ;;
  */.needlbar-final.*.zip)
    record_stage zip:final
    printf '%s\n' "$output_path" > "$FAKE_STATE_DIR/candidate-path" ;;
  *) exit 64 ;;
esac
printf '%s\n' "$PWD/Needlbar.app" > "$output_path"
EOF

cat > "$fake_bin/ditto" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

[[ "$1" == '-x' && "$2" == '-k' ]] || exit 64
archive_path="$3"
destination="$4"
record_stage ditto:extract
source_app="$(<"$archive_path")"
mkdir -p "$destination"
cp -R "$source_app" "$destination/Needlbar.app"
EOF

cat > "$fake_bin/base64" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

cat
EOF

cat > "$fake_bin/uuidgen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

printf '%s\n' '00000000-0000-0000-0000-000000000000'
EOF

chmod 755 "$fake_bin/security" "$fake_bin/codesign" "$fake_bin/xcrun" \
  "$fake_bin/spctl" "$fake_bin/zip" "$fake_bin/ditto" "$fake_bin/base64" "$fake_bin/uuidgen"

new_case() {
  case_root="$(mktemp -d "$temp_root/case.XXXXXX")"
  mkdir -p "$case_root/repo/scripts" "$case_root/repo/dist/Needlbar.app/Contents/MacOS" \
    "$case_root/private-temp" "$case_root/state"
  cp "$SCRIPT_UNDER_TEST" "$case_root/repo/scripts/notarize-app.sh"
  chmod 755 "$case_root/repo/scripts/notarize-app.sh"
  : > "$case_root/repo/dist/Needlbar.app/Contents/MacOS/Needlbar"
  printf '%s\n' 'original-ad-hoc-zip' > "$case_root/repo/dist/Needlbar-macos-arm64.zip"
  : > "$case_root/commands.log"
}

run_case_exec() {
  local omitted_name="${1:-}"
  cd "$ROOT"
  export PATH="$fake_bin:$PATH"
  export FAKE_COMMAND_LOG="$case_root/commands.log"
  export FAKE_STATE_DIR="$case_root/state"
  export NEEDLBAR_NOTARIZE_APP_PATH="$case_root/repo/dist/Needlbar.app"
  export NEEDLBAR_NOTARIZE_ZIP_PATH="$case_root/repo/dist/Needlbar-macos-arm64.zip"
  export NEEDLBAR_NOTARIZE_TEMP_PARENT="$case_root/private-temp"
  export DEVELOPER_ID_APPLICATION='Developer ID Application: Test Signer (3BMF4LM6TM)'
  export DEVELOPER_ID_APPLICATION_CERTIFICATE='P12-CANARY-DO-NOT-LOG'
  export DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD='P12-PASSWORD-CANARY-DO-NOT-LOG'
  export APPLE_ID='APPLE-ID-CANARY-DO-NOT-LOG'
  export APPLE_TEAM_ID='3BMF4LM6TM'
  export APPLE_APP_SPECIFIC_PASSWORD='NOTARY-PASSWORD-CANARY-DO-NOT-LOG'
  if [[ -n "$omitted_name" ]]; then unset "$omitted_name"; fi
  exec "$case_root/repo/scripts/notarize-app.sh"
}

invoke_case() {
  local omitted_name="${1:-}"
  set +e
  ( run_case_exec "$omitted_name" ) > "$case_root/output.txt" 2>&1
  status=$?
  set -e
  return "$status"
}

assert_no_canary() {
  local scan_root="$1"
  local canary
  for canary in \
    'P12-CANARY-DO-NOT-LOG' \
    'P12-PASSWORD-CANARY-DO-NOT-LOG' \
    'APPLE-ID-CANARY-DO-NOT-LOG' \
    'NOTARY-PASSWORD-CANARY-DO-NOT-LOG'; do
    ! grep -R -F -- "$canary" "$scan_root" >/dev/null 2>&1 ||
      fail "credential canary surfaced: $canary"
  done
}

for missing_name in \
  DEVELOPER_ID_APPLICATION \
  DEVELOPER_ID_APPLICATION_CERTIFICATE \
  DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD \
  APPLE_ID \
  APPLE_TEAM_ID \
  APPLE_APP_SPECIFIC_PASSWORD; do
  new_case
  command_log="$case_root/commands.log"
  final_zip="$case_root/repo/dist/Needlbar-macos-arm64.zip"
  output_file="$case_root/output.txt"

  if invoke_case "$missing_name"; then
    fail "missing $missing_name unexpectedly succeeded"
  fi
  [[ "$status" -ne 0 ]] || fail "missing $missing_name must fail"
  grep -F "$missing_name" "$output_file" >/dev/null || fail "missing name not reported"
  ! grep -Fx 'security:create-keychain' "$command_log" >/dev/null || fail 'keychain created before preflight'
  [[ "$(<"$final_zip")" == 'original-ad-hoc-zip' ]] || fail 'preflight replaced final ZIP'
  assert_no_canary "$case_root"
  ! find "$case_root/private-temp" -mindepth 1 -print -quit | grep -q . ||
    fail 'missing-secret preflight left private temp child'
  ! find "$(dirname "$final_zip")" -maxdepth 1 -name '.needlbar-final.*.zip' -print -quit | grep -q . ||
    fail 'missing-secret preflight left candidate ZIP'
done

echo 'notarize-app missing-secret contract passed'
