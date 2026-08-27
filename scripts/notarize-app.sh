#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${NEEDLBAR_NOTARIZE_APP_PATH:-$ROOT/dist/Needlbar.app}"
ZIP_PATH="${NEEDLBAR_NOTARIZE_ZIP_PATH:-$ROOT/dist/Needlbar-macos-arm64.zip}"
TEMP_PARENT="${NEEDLBAR_NOTARIZE_TEMP_PARENT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
work_dir=''
candidate_zip=''
original_keychains=()
keychain_search_list_replaced=0

fail() { echo "notarize-app: $*" >&2; exit 1; }

zip_parent="$(dirname "$ZIP_PATH")"

[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"
[[ -d "$zip_parent" ]] || fail "ZIP parent directory not found: $zip_parent"
[[ -f "$ZIP_PATH" ]] || fail "ZIP archive not found: $ZIP_PATH"
[[ -d "$TEMP_PARENT" ]] || fail "temporary parent directory not found: $TEMP_PARENT"

for required_command in base64 security codesign xcrun spctl zip ditto mktemp uuidgen; do
  command -v "$required_command" >/dev/null 2>&1 ||
    fail "required command not found: $required_command"
done

missing_inputs=()
for required_input in \
  DEVELOPER_ID_APPLICATION \
  DEVELOPER_ID_APPLICATION_CERTIFICATE \
  DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD \
  APPLE_ID \
  APPLE_TEAM_ID \
  APPLE_APP_SPECIFIC_PASSWORD; do
  if [[ -z "${!required_input:-}" ]]; then
    missing_inputs+=("$required_input")
  fi
done
[[ ${#missing_inputs[@]} -eq 0 ]] ||
  fail "missing required signing/notarization inputs: ${missing_inputs[*]}"

work_dir="$(mktemp -d "$TEMP_PARENT/needlbar-notarize.XXXXXX")"
p12_path="$work_dir/developer-id.p12"
keychain_path="$work_dir/signing.keychain-db"
submission_zip="$work_dir/notarization-submission.zip"
notary_output="$work_dir/notarytool-output.txt"
extract_root="$work_dir/extracted"
candidate_zip="$(mktemp "$zip_parent/.needlbar-final.XXXXXX.zip")"
rm -f -- "$candidate_zip"

cleanup() {
  local original_status=$?
  local cleanup_status=0
  trap - EXIT INT TERM
  if [[ "$keychain_search_list_replaced" -eq 1 ]]; then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || cleanup_status=1
  fi
  [[ -z "${keychain_path:-}" ]] || security delete-keychain "$keychain_path" >/dev/null 2>&1 || cleanup_status=1
  [[ -z "${work_dir:-}" ]] || rm -rf -- "$work_dir" || cleanup_status=1
  [[ -z "${candidate_zip:-}" ]] || rm -f -- "$candidate_zip" || cleanup_status=1
  if [[ "$cleanup_status" -ne 0 ]]; then
    echo "notarize-app: cleanup failed" >&2
    [[ "$original_status" -ne 0 ]] || exit "$cleanup_status"
  fi
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while IFS= read -r keychain; do
  original_keychains+=("$keychain")
done < <(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')
[[ ${#original_keychains[@]} -gt 0 ]] || fail "could not capture caller keychain search list"

printf '%s' "$DEVELOPER_ID_APPLICATION_CERTIFICATE" | base64 -D > "$p12_path"
chmod 600 "$p12_path"
keychain_password="$(uuidgen)"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$p12_path" -k "$keychain_path" \
  -P "$DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain_path"
security list-keychains -d user -s "$keychain_path" "${original_keychains[@]}"
keychain_search_list_replaced=1

identity_names="$(security find-identity -v -p codesigning "$keychain_path" \
  | sed -nE 's/^[[:space:]]*[0-9]+\) [[:xdigit:]]+ "(.*)"$/\1/p')"
identity_count="$(printf '%s\n' "$identity_names" | grep -Fxc "$DEVELOPER_ID_APPLICATION" || true)"
[[ "$identity_count" == 1 ]] || fail "identity verification failed"

codesign --force --deep --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

signing_details="$(codesign --display --verbose=4 "$APP_PATH" 2>&1)"
printf '%s\n' "$signing_details" | grep -Fx "Authority=$DEVELOPER_ID_APPLICATION" >/dev/null ||
  fail "identity verification failed"
printf '%s\n' "$signing_details" | grep -Fx "TeamIdentifier=$APPLE_TEAM_ID" >/dev/null ||
  fail "team verification failed"
printf '%s\n' "$signing_details" | grep -E '^Runtime Version=.+$' >/dev/null ||
  fail "hardened runtime verification failed"

(
  cd "$(dirname "$APP_PATH")"
  COPYFILE_DISABLE=1 zip -qryX "$submission_zip" "$(basename "$APP_PATH")"
)
if ! xcrun notarytool submit "$submission_zip" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait >"$notary_output" 2>&1; then
  fail "notarization submission failed"
fi
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

(
  cd "$(dirname "$APP_PATH")"
  COPYFILE_DISABLE=1 zip -qryX "$candidate_zip" "$(basename "$APP_PATH")"
)
ditto -x -k "$candidate_zip" "$extract_root"
extracted_app="$extract_root/$(basename "$APP_PATH")"
codesign --verify --deep --strict --verbose=2 "$extracted_app"
xcrun stapler validate "$extracted_app"
spctl --assess --type execute --verbose=4 "$extracted_app"
mv -f "$candidate_zip" "$ZIP_PATH"
candidate_zip=''
echo "Needlbar notarized archive validated: $ZIP_PATH"
