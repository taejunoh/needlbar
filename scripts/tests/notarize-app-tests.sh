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
    [[ "$2" == submit && -f "$3" ]] || exit 64
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

assert_private_cleanup() {
  local case_root="$1"
  local final_zip="$case_root/repo/dist/Needlbar-macos-arm64.zip"
  ! find "$case_root/private-temp" -mindepth 1 -maxdepth 1 -print -quit | grep -q . ||
    fail "temporary notarization paths remained for $case_root"
  grep -Fx 'security:restore-list' "$case_root/commands.log" >/dev/null || fail 'keychain list was not restored'
  grep -Fx 'security:delete-keychain' "$case_root/commands.log" >/dev/null || fail 'temporary keychain was not deleted'
  if [[ -f "$case_root/state/candidate-path" ]]; then
    candidate_path="$(<"$case_root/state/candidate-path")"
    [[ ! -e "$candidate_path" ]] || fail "candidate ZIP remained: $candidate_path"
  fi
  ! find "$(dirname "$final_zip")" -maxdepth 1 -name '.needlbar-final.*.zip' -print -quit | grep -q . ||
    fail 'same-directory candidate ZIP remained'
}

assert_original_zip() {
  [[ "$(<"$case_root/repo/dist/Needlbar-macos-arm64.zip")" == original-ad-hoc-zip ]] ||
    fail 'final ZIP was replaced before validation completed'
}

assert_stage_present() {
  grep -Fx "$2" "$1/commands.log" >/dev/null || fail "missing command stage: $2"
}

assert_stage_absent() {
  ! grep -Fx "$2" "$1/commands.log" >/dev/null || fail "unexpected command stage: $2"
}

assert_stage_subsequence() {
  local case_root="$1"
  local stage expected_index=0
  local expected_stages=(
    security:create-keychain
    security:import
    codesign:sign
    codesign:verify
    codesign:display
    zip:submission
    xcrun:notarytool-submit
    xcrun:stapler-staple
    xcrun:stapler-validate
    spctl:assess
    zip:final
    ditto:extract
    codesign:verify
    xcrun:stapler-validate
    spctl:assess
    security:restore-list
    security:delete-keychain
  )

  while IFS= read -r stage; do
    if [[ "$stage" == "${expected_stages[$expected_index]}" ]]; then
      expected_index=$((expected_index + 1))
      [[ "$expected_index" -lt "${#expected_stages[@]}" ]] || return 0
    fi
  done < "$case_root/commands.log"

  fail "safe command sequence did not include: ${expected_stages[$expected_index]}"
}

assert_no_value() {
  local scan_root="$1"
  local value="$2"
  ! grep -R -F -- "$value" "$scan_root" >/dev/null 2>&1 ||
    fail "sensitive value surfaced: $value"
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

run_signing_check_case() {
  local variable_name="$1"
  local variable_value="$2"
  local expected_copy="$3"

  new_case
  export "$variable_name=$variable_value"
  if invoke_case; then
    fail "$variable_name case unexpectedly succeeded"
  fi
  unset "$variable_name"
  [[ "$status" -ne 0 ]] || fail "$variable_name case must fail"
  grep -F "$expected_copy" "$case_root/output.txt" >/dev/null ||
    fail "$variable_name failure did not identify the safe validation phase"
  assert_stage_absent "$case_root" xcrun:notarytool-submit
  assert_original_zip
  assert_private_cleanup "$case_root"
  assert_no_canary "$case_root"
}

run_signing_check_case \
  FAKE_SECURITY_IDENTITIES \
  'Developer ID Application: Different Signer (3BMF4LM6TM)' \
  identity
run_signing_check_case FAKE_CODESIGN_TEAM_ID WRONGTEAMID team
run_signing_check_case FAKE_CODESIGN_RUNTIME '' 'hardened runtime'

new_case
export FAKE_EMPTY_KEYCHAIN_LIST=1
if invoke_case; then
  fail 'empty keychain list case unexpectedly succeeded'
fi
unset FAKE_EMPTY_KEYCHAIN_LIST
[[ "$status" -ne 0 ]] || fail 'empty keychain list case must fail'
grep -F 'could not capture caller keychain search list' "$case_root/output.txt" >/dev/null ||
  fail 'empty keychain list was not rejected safely'
assert_stage_absent "$case_root" security:create-keychain
assert_stage_absent "$case_root" security:set-list
assert_stage_absent "$case_root" security:restore-list
assert_original_zip
! find "$case_root/private-temp" -mindepth 1 -print -quit | grep -q . ||
  fail 'empty keychain list preflight left private temp child'
! find "$(dirname "$case_root/repo/dist/Needlbar-macos-arm64.zip")" -maxdepth 1 \
  -name '.needlbar-final.*.zip' -print -quit | grep -q . ||
  fail 'empty keychain list preflight left candidate ZIP'
assert_no_canary "$case_root"

run_notary_failure_case() {
  local variable_name="$1"
  local variable_value="$2"
  local required_stage="$3"
  local forbidden_stage="$4"

  new_case
  export "$variable_name=$variable_value"
  if invoke_case; then
    fail "$variable_name case unexpectedly succeeded"
  fi
  unset "$variable_name"
  [[ "$status" -ne 0 ]] || fail "$variable_name case must fail"
  assert_stage_present "$case_root" "$required_stage"
  assert_stage_absent "$case_root" "$forbidden_stage"
  assert_stage_absent "$case_root" zip:final
  assert_original_zip
  assert_private_cleanup "$case_root"
  assert_no_canary "$case_root"
}

new_case
export FAKE_NOTARY_FAIL=1
export FAKE_NOTARY_STDERR_CANARY='NOTARY-STDERR-CANARY-DO-NOT-LOG'
if invoke_case; then
  fail 'notary failure case unexpectedly succeeded'
fi
unset FAKE_NOTARY_FAIL
unset FAKE_NOTARY_STDERR_CANARY
[[ "$status" -ne 0 ]] || fail 'notary failure case must fail'
assert_stage_present "$case_root" zip:submission
assert_stage_present "$case_root" xcrun:notarytool-submit
assert_stage_absent "$case_root" xcrun:stapler-staple
assert_stage_absent "$case_root" zip:final
assert_original_zip
assert_private_cleanup "$case_root"
assert_no_canary "$case_root"
assert_no_value "$case_root" NOTARY-STDERR-CANARY-DO-NOT-LOG

run_notary_failure_case \
  FAKE_STAPLE_FAIL 1 xcrun:stapler-staple xcrun:stapler-validate
run_notary_failure_case \
  FAKE_STAPLER_VALIDATE_FAIL 1 xcrun:stapler-validate spctl:assess

new_case
export FAKE_SPCTL_FAIL=1
if invoke_case; then
  fail 'spctl failure case unexpectedly succeeded'
fi
unset FAKE_SPCTL_FAIL
[[ "$status" -ne 0 ]] || fail 'spctl failure case must fail'
assert_stage_present "$case_root" xcrun:stapler-validate
assert_stage_present "$case_root" spctl:assess
assert_stage_absent "$case_root" zip:final
assert_original_zip
assert_private_cleanup "$case_root"
assert_no_canary "$case_root"

new_case
export FAKE_EXTRACTED_SPCTL_FAIL=1
if invoke_case; then
  fail 'extracted spctl failure case unexpectedly succeeded'
fi
unset FAKE_EXTRACTED_SPCTL_FAIL
[[ "$status" -ne 0 ]] || fail 'extracted spctl failure case must fail'
assert_stage_present "$case_root" zip:final
assert_stage_present "$case_root" ditto:extract
assert_stage_present "$case_root" spctl:assess
assert_original_zip
assert_private_cleanup "$case_root"
assert_no_canary "$case_root"

run_signal_case() {
  local signal_name="$1"
  local expected_status="$2"
  new_case
  export FAKE_NOTARY_SIGNAL="$signal_name"
  if invoke_case; then
    fail "signal case unexpectedly succeeded: $signal_name"
  fi
  unset FAKE_NOTARY_SIGNAL
  [[ "$status" -eq "$expected_status" ]] || fail "unexpected $signal_name status: $status"
  [[ "$(<"$case_root/repo/dist/Needlbar-macos-arm64.zip")" == original-ad-hoc-zip ]] ||
    fail 'signal case replaced final ZIP'
  assert_private_cleanup "$case_root"
  assert_no_canary "$case_root"
}
run_signal_case INT 130
run_signal_case TERM 143

new_case
if ! invoke_case; then
  fail "success case failed with status $status"
fi
[[ "$(<"$case_root/repo/dist/Needlbar-macos-arm64.zip")" != original-ad-hoc-zip ]] ||
  fail 'success case did not replace final ZIP'
assert_stage_subsequence "$case_root"
assert_private_cleanup "$case_root"
assert_no_canary "$case_root"

echo 'notarize-app shell contracts passed'
