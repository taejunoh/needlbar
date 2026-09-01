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
    else
      printf '    "/fake/original.keychain-db"\n'
      [[ "${FAKE_MALFORMED_KEYCHAIN_LIST:-}" != 1 ]] || printf 'malformed keychain record\n'
    fi ;;
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

record_stage() { printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"; }
if [[ "${1:-}" == --force ]]; then
  [[ "$*" == *'--options runtime --timestamp'* ]] || exit 81
  [[ "$*" == *'--entitlements'* ]] || exit 82
  target="${@: -1}"
  entitlements=''
  previous=''
  for argument in "$@"; do
    if [[ "$previous" == --entitlements ]]; then entitlements="$argument"; fi
    previous="$argument"
  done
  [[ -f "$entitlements" ]] || exit 83
  record_stage codesign:sign
  record_stage "codesign:sign:$target"
  if [[ "$target" == *NeedlbarWidgetExtension.appex ]]; then
    cp "$entitlements" "$FAKE_STATE_DIR/widget-entitlements"
  elif [[ "$target" == *Needlbar.app ]]; then
    cp "$entitlements" "$FAKE_STATE_DIR/host-entitlements"
  else
    exit 84
  fi
elif [[ "${1:-}" == --verify ]]; then
  record_stage codesign:verify
elif [[ "${1:-}" == --display ]]; then
  record_stage codesign:display
  printf 'Authority=Developer ID Application: Test Signer (3BMF4LM6TM)\n'
  printf 'TeamIdentifier=%s\n' "${FAKE_CODESIGN_TEAM_ID-3BMF4LM6TM}"
  printf 'Runtime Version=%s\n' "${FAKE_CODESIGN_RUNTIME-14.0.0}"
else
  exit 64
fi
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

cat > "$fake_bin/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

[[ "${1:-}" == '-a' && "${2:-}" == '256' ]] || exit 64
if [[ "${3:-}" == '-c' ]]; then
  check_file="${4:-}"
  [[ -f "$check_file" ]] || exit 64
  line="$(cat "$check_file")"
  [[ "$line" =~ ^([[:xdigit:]]{64})[[:space:]][[:space:]](.+)$ ]] || exit 65
  [[ "${BASH_REMATCH[1],,}" == "$(printf '%064x' 0)" ]] || exit 66
  [[ -f "$(dirname "$check_file")/${BASH_REMATCH[2]}" ]] || exit 67
  record_stage shasum:check
  printf '%s: OK\n' "${BASH_REMATCH[2]}"
else
  archive_path="${3:-}"
  [[ -f "$archive_path" ]] || exit 64
  [[ "$archive_path" != */Needlbar-macos-arm64.zip ]] || exit 68
  record_stage shasum:sha256
  printf '%064x  %s\n' 0 "$(basename "$archive_path")"
fi
EOF

cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}

destination="${@: -1}"
case "$destination" in
  */Needlbar-macos-arm64.zip) record_stage install:zip ;;
  */Needlbar-macos-arm64.zip.sha256) record_stage install:checksum ;;
esac
exec /bin/mv "$@"
EOF

chmod 755 "$fake_bin/security" "$fake_bin/codesign" "$fake_bin/xcrun" \
  "$fake_bin/spctl" "$fake_bin/zip" "$fake_bin/ditto" "$fake_bin/base64" "$fake_bin/uuidgen" \
  "$fake_bin/shasum" "$fake_bin/mv"

for fake_tool in "$fake_bin"/*; do
  bash -n "$fake_tool" || fail "generated fake tool failed syntax check: $fake_tool"
done

fake_bin_without_shasum="$temp_root/fake-bin-without-shasum"
mkdir -p "$fake_bin_without_shasum"
for fake_tool in "$fake_bin"/*; do
  [[ "$(basename "$fake_tool")" == shasum ]] && continue
  ln -s "$fake_tool" "$fake_bin_without_shasum/$(basename "$fake_tool")"
done
ln -s /usr/bin/mktemp "$fake_bin_without_shasum/mktemp"
ln -s "$(command -v bash)" "$fake_bin_without_shasum/bash"
ln -s "$(command -v dirname)" "$fake_bin_without_shasum/dirname"
ln -s "$(command -v rm)" "$fake_bin_without_shasum/rm"
for real_tool in cat cp chmod sed grep awk; do
  ln -s "$(command -v "$real_tool")" "$fake_bin_without_shasum/$real_tool"
done

fake_checksum_input="$temp_root/fake.zip"
fake_checksum_sidecar="$temp_root/fake.zip.sha256"
fake_checksum_log="$temp_root/fake-shasum.log"
printf '%s\n' fake-archive > "$fake_checksum_input"
: > "$fake_checksum_log"
generated_checksum="$(FAKE_COMMAND_LOG="$fake_checksum_log" "$fake_bin/shasum" -a 256 "$fake_checksum_input" | awk '{print $1}')"
[[ "$generated_checksum" =~ ^[[:xdigit:]]{64}$ ]] || fail 'fake shasum did not generate a 64-hex digest'
printf '%s  fake.zip\n' "$generated_checksum" > "$fake_checksum_sidecar"
FAKE_COMMAND_LOG="$fake_checksum_log" "$fake_bin/shasum" -a 256 -c "$fake_checksum_sidecar" >/dev/null ||
  fail 'fake shasum checksum verification fixture failed'
grep -Fx shasum:sha256 "$fake_checksum_log" >/dev/null || fail 'fake shasum generation stage was not logged'
grep -Fx shasum:check "$fake_checksum_log" >/dev/null || fail 'fake shasum check stage was not logged'

new_case() {
  case_root="$(mktemp -d "$temp_root/case.XXXXXX")"
  mkdir -p "$case_root/repo/scripts" "$case_root/repo/dist/Needlbar.app/Contents/MacOS" \
    "$case_root/repo/Resources" \
    "$case_root/repo/WidgetExtension" \
    "$case_root/repo/dist/Needlbar.app/Contents/PlugIns/NeedlbarWidgetExtension.appex/Contents/MacOS" \
    "$case_root/private-temp" "$case_root/state"
  cp "$SCRIPT_UNDER_TEST" "$case_root/repo/scripts/notarize-app.sh"
  cp "$ROOT/Resources/NeedlbarHostWidget.entitlements" "$case_root/repo/Resources/NeedlbarHostWidget.entitlements"
  cp "$ROOT/WidgetExtension/NeedlbarWidgetExtension.entitlements" "$case_root/repo/WidgetExtension/NeedlbarWidgetExtension.entitlements"
  chmod 755 "$case_root/repo/scripts/notarize-app.sh"
  : > "$case_root/repo/dist/Needlbar.app/Contents/MacOS/Needlbar"
  cat > "$case_root/repo/dist/Needlbar.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>NeedlbarAppGroupIdentifier</key><string>TESTTEAMID.com.taejunoh.needlbar</string>
</dict></plist>
EOF
  cat > "$case_root/repo/dist/Needlbar.app/Contents/PlugIns/NeedlbarWidgetExtension.appex/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>NeedlbarAppGroupIdentifier</key><string>TESTTEAMID.com.taejunoh.needlbar</string>
</dict></plist>
EOF
  printf '%s\n' synthetic-widget > "$case_root/repo/dist/Needlbar.app/Contents/PlugIns/NeedlbarWidgetExtension.appex/Contents/MacOS/NeedlbarWidgetExtension"
  chmod 755 "$case_root/repo/dist/Needlbar.app/Contents/PlugIns/NeedlbarWidgetExtension.appex/Contents/MacOS/NeedlbarWidgetExtension"
  printf '%s\n' 'original-ad-hoc-zip' > "$case_root/repo/dist/Needlbar-macos-arm64.zip"
  : > "$case_root/commands.log"
}

run_case_exec() {
  local omitted_name="${1:-}"
  cd "$ROOT"
  export PATH="$fake_bin:$PATH"
  if [[ "${OMIT_FAKE_SHASUM:-}" == 1 ]]; then
    export PATH="$fake_bin_without_shasum"
  fi
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
  local zip_parent
  zip_parent="$(dirname "$case_root/repo/dist/Needlbar-macos-arm64.zip")"
  [[ "$(<"$case_root/repo/dist/Needlbar-macos-arm64.zip")" == original-ad-hoc-zip ]] ||
    fail 'final ZIP was replaced before validation completed'
  [[ ! -e "$case_root/repo/dist/Needlbar-macos-arm64.zip.sha256" ]] ||
    fail 'failure case created checksum sidecar'
  ! find "$zip_parent" -maxdepth 1 -name '.needlbar-checksum.*.sha256' -print -quit | grep -q . ||
    fail 'failure case left checksum candidate'
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
    shasum:sha256
    install:zip
    install:checksum
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

release_validation_status_contract_is_valid() {
  local status_file="$1"
  ruby - "$status_file" <<'RUBY'
status_path = ARGV.fetch(0)
document = File.read(status_path)
match = document.match(/^## Release Validation Continuation — 2026-08-27\n(.*?)(?=^## |\z)/m)
abort 'documentation contract: missing release validation continuation section' unless match

section = match[1].gsub(/\s+/, ' ').strip
required_facts = [
  'The reusable fake-tested `scripts/notarize-app.sh` and split `.github/workflows/release.yml` validate/publish workflow are implemented.',
  'Manual dispatch is tagless and produces only an Actions artifact',
  '`validate` is read-only, while `publish` is write-enabled only for future `v*` push tags',
  'This implementation did not configure or read a protected GitHub Environment secret.',
  'No real notarization, stapling, Gatekeeper acceptance, merge to `main`, tag, public GitHub Release, or distribution is claimed here.',
  'The next gate is merge to `main`, authorized protected Environment setup outside chat, then tagless manual validation.'
]

required_facts.each do |fact|
  abort "documentation contract: continuation is missing #{fact.inspect}" unless section.include?(fact)
end
RUBY
}

release_preparation_status_contract_is_valid() {
  local status_file="$1"
  ruby - "$status_file" <<'RUBY'
status_path = ARGV.fetch(0)
document = File.read(status_path)
match = document.match(/^## v0.2.2 Public Release Preparation — 2026-09-01\n(.*?)(?=^## |\z)/m)
abort 'documentation contract: missing v0.2.2 public release preparation section' unless match

section = match[1].gsub(/\s+/, ' ').strip
required_facts = [
  'This records preparation only: no v0.2.2 tag, GitHub Release, public download, or public notarization claim has been made.',
  'adds the reviewed future-download copy'
]
required_facts.each do |fact|
  abort "documentation contract: preparation is missing #{fact.inspect}" unless section.include?(fact)
end
RUBY
}

published_state_contract_is_valid() {
  local readme_file="$1"
  local status_file="$2"

  if grep -F 'Needlbar is currently unreleased.' "$readme_file" >/dev/null; then
    echo 'documentation contract: README contains stale unreleased availability claim' >&2
    return 1
  fi
  if grep -F 'No public GitHub Release or notarized download is available yet.' "$readme_file" >/dev/null; then
    echo 'documentation contract: README contains stale no-public-download claim' >&2
    return 1
  fi

  grep -F '[Download Needlbar v0.2.2 for Apple Silicon](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip)' "$readme_file" >/dev/null ||
    { echo 'documentation contract: README missing exact v0.2.2 download link' >&2; return 1; }
  grep -F 'ad-hoc signed and is not a substitute' "$readme_file" >/dev/null ||
    { echo 'documentation contract: README missing ad-hoc package caveat' >&2; return 1; }
  grep -F 'Native signed macOS 14 arm64 Widget Gallery/App Group and notification-permission acceptance still require external evidence; the local macOS 26 build is not that acceptance.' "$readme_file" >/dev/null ||
    { echo 'documentation contract: README missing native macOS 14 acceptance caveat' >&2; return 1; }
  grep -F 'Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration.' "$readme_file" >/dev/null ||
    { echo 'documentation contract: README missing Cursor privacy boundary' >&2; return 1; }

  if grep -Fx '## v0.2.2 Public Release Record — 2026-09-01' "$status_file" >/dev/null; then
    if grep -F 'The future public artifact will be Developer ID-signed and notarized.' "$readme_file" >/dev/null; then
      echo 'documentation contract: post-public README contains future signing wording' >&2
      return 1
    fi
    grep -F 'The public artifact is Developer ID-signed and notarized.' "$readme_file" >/dev/null ||
      { echo 'documentation contract: README missing public signing wording' >&2; return 1; }
    if grep -F 'Needlbar v0.2.2 is prepared for public release for macOS 14 or later on Apple Silicon.' "$readme_file" >/dev/null; then
      echo 'documentation contract: post-public README contains preparation availability claim' >&2
      return 1
    fi
    grep -F 'Needlbar v0.2.2 is publicly available for macOS 14 or later on Apple Silicon.' "$readme_file" >/dev/null ||
      { echo 'documentation contract: README missing published availability statement' >&2; return 1; }
    if grep -Fx '## v0.2.2 local repository analytics (prepared for public release)' "$readme_file" >/dev/null; then
      echo 'documentation contract: post-public README contains prepared analytics heading' >&2
      return 1
    fi
    if grep -F 'The feature is prepared for public release and remains local-only; no analytics history is retained after the in-memory state is discarded.' "$readme_file" >/dev/null; then
      echo 'documentation contract: post-public README contains prepared analytics copy' >&2
      return 1
    fi
    grep -Fx '## v0.2.2 local repository analytics' "$readme_file" >/dev/null ||
      { echo 'documentation contract: README missing public analytics heading' >&2; return 1; }
    grep -F 'The feature is released and remains local-only; no analytics history is retained after the in-memory state is discarded.' "$readme_file" >/dev/null ||
      { echo 'documentation contract: README missing public analytics copy' >&2; return 1; }
  else
    if grep -F 'The public artifact is Developer ID-signed and notarized' "$readme_file" >/dev/null; then
      echo 'documentation contract: pre-public README contains present public signing wording' >&2
      return 1
    fi
    grep -F 'The future public artifact will be Developer ID-signed and notarized.' "$readme_file" >/dev/null ||
      { echo 'documentation contract: README missing future signing wording' >&2; return 1; }
    if grep -F 'Needlbar v0.2.2 is publicly available for macOS 14 or later on Apple Silicon.' "$readme_file" >/dev/null; then
      echo 'documentation contract: pre-public README contains public availability claim' >&2
      return 1
    fi
    grep -F 'Needlbar v0.2.2 is prepared for public release for macOS 14 or later on Apple Silicon.' "$readme_file" >/dev/null ||
      { echo 'documentation contract: README missing prepared availability statement' >&2; return 1; }
    if grep -Fx '## v0.2.2 local repository analytics' "$readme_file" >/dev/null; then
      echo 'documentation contract: pre-public README contains public analytics heading' >&2
      return 1
    fi
    if grep -F 'The feature is released and remains local-only; no analytics history is retained after the in-memory state is discarded.' "$readme_file" >/dev/null; then
      echo 'documentation contract: pre-public README contains released analytics copy' >&2
      return 1
    fi
    grep -Fx '## v0.2.2 local repository analytics (prepared for public release)' "$readme_file" >/dev/null ||
      { echo 'documentation contract: README missing prepared analytics heading' >&2; return 1; }
    grep -F 'The feature is prepared for public release and remains local-only; no analytics history is retained after the in-memory state is discarded.' "$readme_file" >/dev/null ||
      { echo 'documentation contract: README missing prepared analytics copy' >&2; return 1; }
  fi

  release_preparation_status_contract_is_valid "$status_file"
}

assert_plist_value() {
  local plist_path="$1" key="$2" expected="$3" actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist_path")"
  [[ "$actual" == "$expected" ]] ||
    fail "$plist_path $key must be $expected, got $actual"
}

test_documentation_contract() {
  local readme_file="$ROOT/README.md"
  local status_file="$ROOT/docs/STATUS.md"
  local published_readme="$temp_root/readme-pre-public-fixture.md"
  local published_status="$temp_root/status-pre-public-fixture.md"
  local post_public_readme="$temp_root/readme-post-public-fixture.md"
  local post_public_status="$temp_root/status-post-public-fixture.md"
  local phase_decoy_pre_public="$temp_root/readme-pre-public-wrongly-public.md"
  local phase_decoy_post_prepared="$temp_root/readme-post-public-still-prepared.md"
  local phase_decoy_pre_public_signing="$temp_root/readme-pre-public-present-signing.md"
  local phase_decoy_post_future_signing="$temp_root/readme-post-public-future-signing.md"
  local phase_decoy_pre_public_analytics="$temp_root/readme-pre-public-released-analytics.md"
  local phase_decoy_post_prepared_analytics="$temp_root/readme-post-public-prepared-analytics.md"
  local status_heading_mention="$temp_root/status-heading-mention.md"
  local decoy_readme_url="$temp_root/readme-wrong-release-url.md"
  local decoy_readme_cursor="$temp_root/readme-missing-cursor-sentence.md"
  local decoy_readme_native="$temp_root/readme-missing-native-caveat.md"
  local decoy_readme_unreleased="$temp_root/readme-stale-unreleased-claim.md"
  local decoy_readme_no_download="$temp_root/readme-stale-no-download-claim.md"
  local decoy_status="$temp_root/status-release-preparation-decoy.md"
  local decoy_output decoy_rc

  grep -F 'tagless' "$readme_file" >/dev/null ||
    fail 'README must describe bounded tagless validation'
  grep -F 'Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration.' "$readme_file" >/dev/null ||
    fail 'README must retain Cursor privacy boundary'
  grep -F 'Cursor usage has no Needlbar-owned hydration layer' "$status_file" >/dev/null ||
    fail 'STATUS must retain Cursor local-cache boundary'

  release_validation_status_contract_is_valid "$status_file" ||
    fail 'STATUS release-validation continuation contract is invalid'
  grep -F 'no tag or release action is authorized' "$status_file" >/dev/null ||
    fail 'STATUS must state that no tag or release action is authorized'

  ruby - "$published_readme" <<'RUBY'
destination = ARGV.fetch(0)
File.write(destination, <<~'MARKDOWN')
  Needlbar v0.2.2 is prepared for public release for macOS 14 or later on Apple Silicon.
  [Download Needlbar v0.2.2 for Apple Silicon](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip)
  The future public artifact will be Developer ID-signed and notarized.
  The local package is ad-hoc signed and is not a substitute for the public artifact.
  Native signed macOS 14 arm64 Widget Gallery/App Group and notification-permission acceptance still require external evidence; the local macOS 26 build is not that acceptance.
  Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration.

  ## v0.2.2 local repository analytics (prepared for public release)

  The feature is prepared for public release and remains local-only; no analytics history is retained after the in-memory state is discarded.
MARKDOWN
RUBY
  ruby - "$published_readme" "$post_public_readme" <<'RUBY'
source, destination = ARGV
document = File.read(source)
prepared = 'Needlbar v0.2.2 is prepared for public release for macOS 14 or later on Apple Silicon.'
public = 'Needlbar v0.2.2 is publicly available for macOS 14 or later on Apple Silicon.'
future_signing = 'The future public artifact will be Developer ID-signed and notarized.'
public_signing = 'The public artifact is Developer ID-signed and notarized.'
prepared_heading = '## v0.2.2 local repository analytics (prepared for public release)'
public_heading = '## v0.2.2 local repository analytics'
prepared_copy = 'The feature is prepared for public release and remains local-only; no analytics history is retained after the in-memory state is discarded.'
public_copy = 'The feature is released and remains local-only; no analytics history is retained after the in-memory state is discarded.'
abort 'fixture setup: expected prepared availability statement was not found' unless document.sub!(prepared, public)
abort 'fixture setup: expected future signing wording was not found' unless document.sub!(future_signing, public_signing)
abort 'fixture setup: expected prepared analytics heading was not found' unless document.sub!(prepared_heading, public_heading)
abort 'fixture setup: expected prepared analytics copy was not found' unless document.sub!(prepared_copy, public_copy)
File.write(destination, document)
RUBY
  ruby - "$published_status" <<'RUBY'
destination = ARGV.fetch(0)
File.write(destination, <<~'MARKDOWN')
  ## Release Validation Continuation — 2026-08-27

  The reusable fake-tested `scripts/notarize-app.sh` and split `.github/workflows/release.yml` validate/publish workflow are implemented.
  Manual dispatch is tagless and produces only an Actions artifact
  `validate` is read-only, while `publish` is write-enabled only for future `v*` push tags
  This implementation did not configure or read a protected GitHub Environment secret.
  No real notarization, stapling, Gatekeeper acceptance, merge to `main`, tag, public GitHub Release, or distribution is claimed here.
  The next gate is merge to `main`, authorized protected Environment setup outside chat, then tagless manual validation.

  ## v0.2.2 Public Release Preparation — 2026-09-01

  Release preparation updates the host and widget to version 0.2.2 (build 2),
  adds the reviewed future-download copy, and prepares validated ZIP and checksum
  release artifacts. This records preparation only: no v0.2.2 tag, GitHub Release,
  public download, or public notarization claim has been made. The signed tagless RC
  run 33524771615 at `15c229f` and docs CI run 33526409582 remain pre-release
  evidence only; a later exact green `main` commit is required for public release.
MARKDOWN
RUBY
  ruby - "$published_status" "$post_public_status" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document << <<~'MARKDOWN'

  ## v0.2.2 Public Release Record — 2026-09-01

  The public release record is selected only by this exact heading.
MARKDOWN
File.write(destination, document)
RUBY

  published_state_contract_is_valid "$published_readme" "$published_status" ||
    fail 'published-state fixture is unexpectedly invalid'
  published_state_contract_is_valid "$post_public_readme" "$post_public_status" ||
    fail 'post-public-state fixture is unexpectedly invalid'

  ruby - "$post_public_readme" "$phase_decoy_pre_public" <<'RUBY'
source, destination = ARGV
document = File.read(source)
public = 'Needlbar v0.2.2 is publicly available for macOS 14 or later on Apple Silicon.'
prepared = 'Needlbar v0.2.2 is prepared for public release for macOS 14 or later on Apple Silicon.'
abort 'fixture setup: expected public availability statement was not found' unless document.sub!(public, prepared)
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$phase_decoy_pre_public" "$post_public_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'post-public prepared-claim decoy was accepted'
  [[ "$decoy_output" == *'post-public README contains preparation availability claim'* ]] ||
    fail 'post-public prepared-claim decoy failed for an unexpected reason'

  ruby - "$published_readme" "$phase_decoy_post_prepared" <<'RUBY'
source, destination = ARGV
document = File.read(source)
prepared = 'Needlbar v0.2.2 is prepared for public release for macOS 14 or later on Apple Silicon.'
public = 'Needlbar v0.2.2 is publicly available for macOS 14 or later on Apple Silicon.'
abort 'fixture setup: expected prepared availability statement was not found' unless document.sub!(prepared, public)
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$phase_decoy_post_prepared" "$published_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'pre-public public-claim decoy was accepted'
  [[ "$decoy_output" == *'pre-public README contains public availability claim'* ]] ||
    fail 'pre-public public-claim decoy failed for an unexpected reason'

  ruby - "$published_readme" "$phase_decoy_pre_public_signing" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document << "\nThe public artifact is Developer ID-signed and notarized.\n"
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$phase_decoy_pre_public_signing" "$published_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'pre-public signing decoy was accepted'
  [[ "$decoy_output" == *'pre-public README contains present public signing wording'* ]] ||
    fail 'pre-public signing decoy failed for an unexpected reason'

  ruby - "$post_public_readme" "$phase_decoy_post_future_signing" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document << "\nThe future public artifact will be Developer ID-signed and notarized.\n"
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$phase_decoy_post_future_signing" "$post_public_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'post-public signing decoy was accepted'
  [[ "$decoy_output" == *'post-public README contains future signing wording'* ]] ||
    fail 'post-public signing decoy failed for an unexpected reason'

  ruby - "$published_readme" "$phase_decoy_pre_public_analytics" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document << <<~'MARKDOWN'

  ## v0.2.2 local repository analytics

  The feature is released and remains local-only; no analytics history is retained after the in-memory state is discarded.
MARKDOWN
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$phase_decoy_pre_public_analytics" "$published_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'pre-public analytics decoy was accepted'
  [[ "$decoy_output" == *'pre-public README contains public analytics heading'* ]] ||
    fail 'pre-public analytics decoy failed for an unexpected reason'

  ruby - "$post_public_readme" "$phase_decoy_post_prepared_analytics" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document << <<~'MARKDOWN'

  ## v0.2.2 local repository analytics (prepared for public release)

  The feature is prepared for public release and remains local-only; no analytics history is retained after the in-memory state is discarded.
MARKDOWN
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$phase_decoy_post_prepared_analytics" "$post_public_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'post-public analytics decoy was accepted'
  [[ "$decoy_output" == *'post-public README contains prepared analytics heading'* ]] ||
    fail 'post-public analytics decoy failed for an unexpected reason'

  ruby - "$published_status" "$status_heading_mention" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document << "\nThe prose mention `## v0.2.2 Public Release Record — 2026-09-01` is not an exact heading.\n"
File.write(destination, document)
RUBY
  published_state_contract_is_valid "$published_readme" "$status_heading_mention" ||
    fail 'non-heading Public Release Record mention changed the pre-public phase'

  ruby - "$published_readme" "$decoy_readme_unreleased" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document << "\nNeedlbar is currently unreleased.\n"
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$decoy_readme_unreleased" "$published_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'README stale-unreleased decoy was accepted'
  [[ "$decoy_output" == *'README contains stale unreleased availability claim'* ]] ||
    fail 'README stale-unreleased decoy failed for an unexpected reason'

  ruby - "$published_readme" "$decoy_readme_no_download" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document << "\nNo public GitHub Release or notarized download is available yet.\n"
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$decoy_readme_no_download" "$published_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'README stale-no-download decoy was accepted'
  [[ "$decoy_output" == *'README contains stale no-public-download claim'* ]] ||
    fail 'README stale-no-download decoy failed for an unexpected reason'

  ruby - "$published_readme" "$decoy_readme_url" <<'RUBY'
source, destination = ARGV
document = File.read(source)
old_link = '[Download Needlbar v0.2.2 for Apple Silicon](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip)'
new_link = '[Download Needlbar v0.2.2 for Apple Silicon](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/wrong.zip)'
abort 'fixture setup: expected download link was not found' unless document.sub!(old_link, new_link)
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$decoy_readme_url" "$published_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'README URL decoy was accepted'
  [[ "$decoy_output" == *'README missing exact v0.2.2 download link'* ]] ||
    fail 'README URL decoy failed for an unexpected reason'

  ruby - "$published_readme" "$decoy_readme_cursor" <<'RUBY'
source, destination = ARGV
document = File.read(source)
sentence = 'Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration.'
abort 'fixture setup: expected Cursor sentence was not found' unless document.sub!(sentence, '')
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$decoy_readme_cursor" "$published_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'README Cursor decoy was accepted'
  [[ "$decoy_output" == *'README missing Cursor privacy boundary'* ]] ||
    fail 'README Cursor decoy failed for an unexpected reason'

  ruby - "$published_readme" "$decoy_readme_native" <<'RUBY'
source, destination = ARGV
document = File.read(source)
sentence = 'Native signed macOS 14 arm64 Widget Gallery/App Group and notification-permission acceptance still require external evidence; the local macOS 26 build is not that acceptance.'
abort 'fixture setup: expected native acceptance caveat was not found' unless document.sub!(sentence, '')
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(published_state_contract_is_valid "$decoy_readme_native" "$published_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'README native caveat decoy was accepted'
  [[ "$decoy_output" == *'README missing native macOS 14 acceptance caveat'* ]] ||
    fail 'README native caveat decoy failed for an unexpected reason'

  ruby - "$published_status" "$decoy_status" <<'RUBY'
source, destination = ARGV
document = File.read(source)
unless document.sub!(/^## v0.2.2 Public Release Preparation — 2026-09-01\n.*?(?=^## |\z)/m, '')
  abort 'fixture setup: expected public release preparation section was not found'
end
File.write(destination, document)
RUBY
  release_validation_status_contract_is_valid "$decoy_status" ||
    fail 'STATUS preparation decoy altered the historical release-validation section'
  set +e
  decoy_output="$(published_state_contract_is_valid "$published_readme" "$decoy_status" 2>&1)"
  decoy_rc=$?
  set -e
  [[ "$decoy_rc" -ne 0 ]] || fail 'STATUS preparation decoy was accepted'
  [[ "$decoy_output" == *'missing v0.2.2 public release preparation section'* ]] ||
    fail 'STATUS preparation decoy failed for an unexpected reason'

  published_state_contract_is_valid "$readme_file" "$status_file"

  assert_plist_value "$ROOT/Resources/Info.plist" CFBundleShortVersionString 0.2.2
  assert_plist_value "$ROOT/Resources/Info.plist" CFBundleVersion 2
  assert_plist_value "$ROOT/WidgetExtension/NeedlbarWidgetExtension-Info.plist" CFBundleShortVersionString 0.2.2
  assert_plist_value "$ROOT/WidgetExtension/NeedlbarWidgetExtension-Info.plist" CFBundleVersion 2
}

test_documentation_contract

release_workflow_contract_is_valid() {
  local release_workflow="$1"
  local ci_workflow="$2"
  ruby - "$release_workflow" "$ci_workflow" <<'RUBY'
require 'yaml'

release_path, ci_path = ARGV

def assert_contract(condition, message)
  abort "release workflow contract: #{message}" unless condition
end

def mapping(value, label)
  assert_contract(value.is_a?(Hash), "#{label} must be a mapping")
  value
end

def sequence(value, label)
  assert_contract(value.is_a?(Array), "#{label} must be a sequence")
  value
end

def scalar_strings(value)
  case value
  when Hash then value.values.flat_map { |child| scalar_strings(child) }
  when Array then value.flat_map { |child| scalar_strings(child) }
  when String then [value]
  else []
  end
end

def exact_artifact_paths(value, label)
  expected = [
    'dist/Needlbar-macos-arm64.zip',
    'dist/Needlbar-macos-arm64.zip.sha256'
  ]
  paths = case value
          when String
            lines = value.lines.map(&:chomp)
            lines.pop if lines.last == ''
            lines
          when Array
            value
          else
            nil
          end
  assert_contract(paths == expected, "#{label} must list ZIP and checksum exactly")
  paths
end

def uses_values(value)
  case value
  when Hash
    value.flat_map do |key, child|
      (key == 'uses' ? [child] : []) + uses_values(child)
    end
  when Array then value.flat_map { |child| uses_values(child) }
  else []
  end
end

release = mapping(YAML.safe_load(File.read(release_path), aliases: false), 'release workflow')
ci = mapping(YAML.safe_load(File.read(ci_path), aliases: false), 'CI workflow')
events = release['on'] || release[true]
events = mapping(events, 'release on')
assert_contract(events.key?('workflow_dispatch'), 'workflow_dispatch is missing')
assert_contract(!mapping(events['workflow_dispatch'] || {}, 'workflow_dispatch').key?('inputs'), 'workflow_dispatch must not define inputs')
push = mapping(events['push'], 'push trigger')
assert_contract(push['tags'] == ['v*'], 'push trigger must be exactly v* tags')

concurrency = mapping(release['concurrency'], 'concurrency')
assert_contract(concurrency['group'] == 'release-${{ github.workflow }}-${{ github.ref }}', 'concurrency group is wrong')
assert_contract(concurrency['cancel-in-progress'] == false, 'concurrency must preserve in-progress validation')
assert_contract(mapping(release['permissions'], 'workflow permissions')['contents'] == 'read', 'workflow contents permission must be read')

jobs = mapping(release['jobs'], 'jobs')
assert_contract(jobs.keys.sort == %w[publish validate], 'release must contain exactly validate and publish jobs')
validate = mapping(jobs['validate'], 'validate job')
publish = mapping(jobs['publish'], 'publish job')
assert_contract(validate['environment'] == 'release', 'validate must use the release environment')
assert_contract(jobs.all? { |name, job| name == 'validate' ? job['environment'] == 'release' : !job.key?('environment') }, 'release environment belongs only to validate')
assert_contract(mapping(validate['permissions'], 'validate permissions')['contents'] == 'read', 'validate contents permission must be read')
assert_contract(publish['needs'] == 'validate', 'publish must need validate')
assert_contract(publish['if'] == "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')", 'publish condition is wrong')
assert_contract(mapping(publish['permissions'], 'publish permissions')['contents'] == 'write', 'publish contents permission must be write')

jobs.each do |name, job|
  permissions = job['permissions']
  next unless permissions

  contents = mapping(permissions, "#{name} permissions")['contents']
  assert_contract(contents != 'write' || name == 'publish', 'contents write is outside publish')
end

validate_steps = sequence(validate['steps'], 'validate steps').map { |step| mapping(step, 'validate step') }
publish_steps = sequence(publish['steps'], 'publish steps').map { |step| mapping(step, 'publish step') }
required_runs = ['make test', 'make package', 'make smoke', './scripts/notarize-app.sh']
run_indices = required_runs.map do |command|
  indices = validate_steps.each_index.select { |index| validate_steps[index]['run'] == command }
  assert_contract(indices.length == 1, "validate must run #{command} exactly once")
  indices.first
end
assert_contract(run_indices == run_indices.sort, 'validate commands must run test, package, smoke, then notarize in order')
notarize_index = run_indices.last
notarize_step = validate_steps[notarize_index]

expected_secret_names = %w[
  DEVELOPER_ID_APPLICATION
  DEVELOPER_ID_APPLICATION_CERTIFICATE
  DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD
  APPLE_ID
  APPLE_TEAM_ID
  APPLE_APP_SPECIFIC_PASSWORD
]
expected_secrets = expected_secret_names.to_h { |name| [name, "${{ secrets.#{name} }}"] }
assert_contract(mapping(notarize_step['env'], 'notarize env') == expected_secrets, 'notarize step must receive exactly the six expected secrets')
secret_strings = scalar_strings(release).select { |value| value.include?('secrets.') }
assert_contract(secret_strings.sort == expected_secrets.values.sort, 'secret references must exist exactly once and only on the notarize step')

all_steps = jobs.flat_map do |job_name, job|
  sequence(job['steps'], "#{job_name} steps").each_with_index.map do |step, index|
    [job_name, index, mapping(step, "#{job_name} step")]
  end
end
uploads = all_steps.select { |_, _, step| step['uses'].to_s.start_with?('actions/upload-artifact@') }
assert_contract(uploads.length == 1 && uploads.first[0] == 'validate', 'only validate may upload the artifact')
upload_index = uploads.first[1]
upload = uploads.first[2]
upload_with = mapping(upload['with'], 'upload artifact settings')
assert_contract(upload_index > notarize_index, 'upload must follow notarization')
assert_contract(upload_with['name'] == 'Needlbar-macos-arm64-notarized', 'upload artifact name is wrong')
exact_artifact_paths(upload_with['path'], 'upload artifact path')
assert_contract(upload_with['if-no-files-found'] == 'error', 'upload must fail for a missing artifact')

downloads = all_steps.select { |_, _, step| step['uses'].to_s.start_with?('actions/download-artifact@') }
assert_contract(downloads.length == 1 && downloads.first[0] == 'publish', 'only publish may download the validated artifact')
download_with = mapping(downloads.first[2]['with'], 'download artifact settings')
assert_contract(download_with['name'] == 'Needlbar-macos-arm64-notarized', 'download artifact name is wrong')
assert_contract(download_with['path'] == 'dist', 'download artifact path is wrong')

publish_steps.each do |step|
  command = step['run'].to_s
  assert_contract(command !~ /(?:make (?:package|smoke)|notarize-app\.sh|codesign|notarytool|xcrun|security)/, 'publish must not package, sign, or notarize')
end
publish_uses = publish_steps.filter_map { |step| step['uses'] }
assert_contract(publish_uses.length == 2 && publish_uses.any? { |value| value.start_with?('actions/download-artifact@') } && publish_uses.any? { |value| value.start_with?('softprops/action-gh-release@') }, 'publish may only download and release the validated artifact')
release_actions = publish_steps.select { |step| step['uses'].to_s.start_with?('softprops/action-gh-release@') }
assert_contract(release_actions.length == 1, 'publish must contain exactly one GitHub Release action')
release_with = mapping(release_actions.first['with'], 'release action settings')
exact_artifact_paths(release_with['files'], 'release action files')
assert_contract(release_with['body_path'] == '.github/release-notes/v0.2.2.md', 'release action body_path is wrong')
assert_contract(release_with['generate_release_notes'] == false, 'release action generate_release_notes must be false')

all_runs = all_steps.map { |_, _, step| step['run'].to_s }
assert_contract(all_runs.none? { |command| command.match?(/(?:^|\s)(?:git\s+(?:tag|push)|gh\s+(?:release|api))/) }, 'workflow must not create tags or releases directly')
assert_contract(scalar_strings(release).none? { |value| value.include?('Documents') }, 'workflow must not use Documents paths')

uses_values(release).concat(uses_values(ci)).each do |uses|
  assert_contract(uses.is_a?(String) && uses.match?(/\A[^@\s]+@[0-9a-f]{40}\z/), "action is not commit pinned: #{uses}")
end
RUBY
}

test_release_workflow_contract() {
  # This regression is intentionally malformed: the required predicate and
  # environment survive only as comments while write permission moves to a
  # post-publish job. A correct contract checker must reject it.
  local release_workflow="$ROOT/.github/workflows/release.yml"
  local ci_workflow="$ROOT/.github/workflows/ci.yml"
  local valid_workflow="$temp_root/release-valid-baseline.yml"
  local decoy_workflow="$temp_root/release-scope-decoy.yml"
  local decoy_missing_upload_checksum="$temp_root/release-missing-upload-checksum.yml"
  local decoy_zip_only_release_files="$temp_root/release-zip-only-files.yml"
  local decoy_missing_body_path="$temp_root/release-missing-body-path.yml"
  local decoy_generated_notes="$temp_root/release-generated-notes.yml"
  local decoy_output decoy_status

  set +e
  decoy_output="$(release_workflow_contract_is_valid "$release_workflow" "$ci_workflow" 2>&1)"
  decoy_status=$?
  set -e
  if [[ "$decoy_status" -ne 0 ]]; then
    [[ "$decoy_output" == *'upload artifact path must list ZIP and checksum exactly'* ]] ||
      fail "current release workflow RED failed for an unexpected reason: $decoy_output"
  fi

  ruby - "$release_workflow" "$valid_workflow" <<'RUBY'
source, destination = ARGV
document = File.read(source)
upload_paths = "          path: |\n            dist/Needlbar-macos-arm64.zip\n            dist/Needlbar-macos-arm64.zip.sha256\n"
unless document.sub!(/          path: (?:dist\/Needlbar-macos-arm64\.zip\n|\|\n            dist\/Needlbar-macos-arm64\.zip\n            dist\/Needlbar-macos-arm64\.zip\.sha256\n)/, upload_paths)
  abort 'fixture setup: could not normalize artifact upload path'
end
release_fields = "          files: |\n            dist/Needlbar-macos-arm64.zip\n            dist/Needlbar-macos-arm64.zip.sha256\n          body_path: .github/release-notes/v0.2.2.md\n          generate_release_notes: false\n"
unless document.sub!(/          files: dist\/Needlbar-macos-arm64\.zip\n|          files: \|\n            dist\/Needlbar-macos-arm64\.zip\n            dist\/Needlbar-macos-arm64\.zip\.sha256\n          body_path: [^\n]+\n          generate_release_notes: (?:true|false)\n/, release_fields)
  abort 'fixture setup: could not normalize release action settings'
end
File.write(destination, document)
RUBY
  release_workflow_contract_is_valid "$valid_workflow" "$ci_workflow" ||
    fail 'normalized valid release workflow fixture was rejected'

  ruby - "$release_workflow" "$decoy_workflow" <<'RUBY'
source, destination = ARGV
document = File.read(source)
document.sub!(/    environment: release\n/, '')
document.sub!(
  "    if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')\n",
  "    if: always()\n",
)
document.sub!(/      contents: write\n/, "      contents: read\n")
document << <<~YAML

  postpublish:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    # environment: release
    # github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')
YAML
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(release_workflow_contract_is_valid "$decoy_workflow" "$ci_workflow" 2>&1)"
  decoy_status=$?
  set -e
  if [[ "$decoy_status" -eq 0 ]]; then
    fail 'release workflow contract accepts a scoped-field decoy'
  fi
  [[ "$decoy_output" == *'validate must use the release environment'* ]] ||
    fail 'scoped-field decoy failed for an unexpected reason'

  ruby - "$valid_workflow" "$decoy_missing_upload_checksum" <<'RUBY'
source, destination = ARGV
document = File.read(source)
old_paths = "          path: |\n            dist/Needlbar-macos-arm64.zip\n            dist/Needlbar-macos-arm64.zip.sha256\n"
new_paths = "          path: dist/Needlbar-macos-arm64.zip\n"
abort 'fixture setup: valid upload path was not found' unless document.sub!(old_paths, new_paths)
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(release_workflow_contract_is_valid "$decoy_missing_upload_checksum" "$ci_workflow" 2>&1)"
  decoy_status=$?
  set -e
  [[ "$decoy_status" -ne 0 ]] || fail 'missing-upload-checksum decoy was accepted'
  [[ "$decoy_output" == *'upload artifact path must list ZIP and checksum exactly'* ]] ||
    fail 'missing-upload-checksum decoy failed for an unexpected reason'

  ruby - "$valid_workflow" "$decoy_zip_only_release_files" <<'RUBY'
source, destination = ARGV
document = File.read(source)
old_files = "          files: |\n            dist/Needlbar-macos-arm64.zip\n            dist/Needlbar-macos-arm64.zip.sha256\n"
new_files = "          files: dist/Needlbar-macos-arm64.zip\n"
abort 'fixture setup: valid release files were not found' unless document.sub!(old_files, new_files)
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(release_workflow_contract_is_valid "$decoy_zip_only_release_files" "$ci_workflow" 2>&1)"
  decoy_status=$?
  set -e
  [[ "$decoy_status" -ne 0 ]] || fail 'ZIP-only release-files decoy was accepted'
  [[ "$decoy_output" == *'release action files must list ZIP and checksum exactly'* ]] ||
    fail 'ZIP-only release-files decoy failed for an unexpected reason'

  ruby - "$valid_workflow" "$decoy_missing_body_path" <<'RUBY'
source, destination = ARGV
document = File.read(source)
abort 'fixture setup: valid body_path was not found' unless document.sub!("          body_path: .github/release-notes/v0.2.2.md\n", '')
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(release_workflow_contract_is_valid "$decoy_missing_body_path" "$ci_workflow" 2>&1)"
  decoy_status=$?
  set -e
  [[ "$decoy_status" -ne 0 ]] || fail 'missing-body-path decoy was accepted'
  [[ "$decoy_output" == *'release action body_path is wrong'* ]] ||
    fail 'missing-body-path decoy failed for an unexpected reason'

  ruby - "$valid_workflow" "$decoy_generated_notes" <<'RUBY'
source, destination = ARGV
document = File.read(source)
abort 'fixture setup: valid generated-notes setting was not found' unless document.sub!("          generate_release_notes: false\n", "          generate_release_notes: true\n")
File.write(destination, document)
RUBY
  set +e
  decoy_output="$(release_workflow_contract_is_valid "$decoy_generated_notes" "$ci_workflow" 2>&1)"
  decoy_status=$?
  set -e
  [[ "$decoy_status" -ne 0 ]] || fail 'generated-notes decoy was accepted'
  [[ "$decoy_output" == *'release action generate_release_notes must be false'* ]] ||
    fail 'generated-notes decoy failed for an unexpected reason'
}

test_release_workflow_contract

new_case
export OMIT_FAKE_SHASUM=1
if PATH="$fake_bin_without_shasum" command -v shasum >/dev/null 2>&1; then
  fail 'missing shasum fixture unexpectedly resolved a fallback command'
fi
if invoke_case; then
  fail 'missing shasum prerequisite case unexpectedly succeeded'
fi
unset OMIT_FAKE_SHASUM
[[ "$status" -ne 0 ]] || fail 'missing shasum prerequisite case must fail'
grep -F 'required command not found: shasum' "$case_root/output.txt" >/dev/null ||
  fail 'missing shasum prerequisite was not reported during preflight'
assert_stage_absent "$case_root" security:create-keychain
assert_original_zip
! find "$case_root/private-temp" -mindepth 1 -print -quit | grep -q . ||
  fail 'missing shasum preflight left private temp child'
! find "$case_root/repo/dist" -maxdepth 1 -name '.needlbar-final.*.zip' -print -quit | grep -q . ||
  fail 'missing shasum preflight left candidate ZIP'

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
  assert_original_zip
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

new_case
export FAKE_MALFORMED_KEYCHAIN_LIST=1
if invoke_case; then
  fail 'malformed keychain list case unexpectedly succeeded'
fi
unset FAKE_MALFORMED_KEYCHAIN_LIST
[[ "$status" -ne 0 ]] || fail 'malformed keychain list case must fail'
grep -F 'could not parse caller keychain search list' "$case_root/output.txt" >/dev/null ||
  fail 'malformed keychain list was not rejected safely'
assert_stage_absent "$case_root" security:create-keychain
assert_stage_absent "$case_root" security:set-list
assert_stage_absent "$case_root" security:restore-list
assert_stage_absent "$case_root" codesign:sign
assert_stage_absent "$case_root" xcrun:notarytool-submit
assert_original_zip
! find "$case_root/private-temp" -mindepth 1 -print -quit | grep -q . ||
  fail 'malformed keychain list preflight left private temp child'
! find "$(dirname "$case_root/repo/dist/Needlbar-macos-arm64.zip")" -maxdepth 1 \
  -name '.needlbar-final.*.zip' -print -quit | grep -q . ||
  fail 'malformed keychain list preflight left candidate ZIP'
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
  assert_original_zip
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
checksum_sidecar="$case_root/repo/dist/Needlbar-macos-arm64.zip.sha256"
[[ -f "$checksum_sidecar" ]] || fail 'success case did not create checksum sidecar'
[[ "$(wc -l < "$checksum_sidecar")" -eq 1 ]] || fail 'checksum sidecar must contain one line'
grep -Eq '^[0-9a-f]{64}  Needlbar-macos-arm64\.zip$' "$checksum_sidecar" ||
  fail 'checksum sidecar must name only the final ZIP'
assert_stage_subsequence "$case_root"
PATH="$fake_bin:$PATH" shasum -a 256 -c "$checksum_sidecar" > "$case_root/checksum-output.txt" ||
  fail 'checksum sidecar failed shasum verification'
assert_private_cleanup "$case_root"
assert_no_canary "$case_root"

release_group='3BMF4LM6TM.com.taejunoh.needlbar'
grep -F "$release_group" "$case_root/repo/dist/Needlbar.app/Contents/Info.plist" >/dev/null || fail 'host group was not resolved from APPLE_TEAM_ID'
grep -F "$release_group" "$case_root/repo/dist/Needlbar.app/Contents/PlugIns/NeedlbarWidgetExtension.appex/Contents/Info.plist" >/dev/null || fail 'extension group was not resolved from APPLE_TEAM_ID'
grep -F "$release_group" "$case_root/state/host-entitlements" >/dev/null || fail 'host signing entitlement group mismatch'
grep -F "$release_group" "$case_root/state/widget-entitlements" >/dev/null || fail 'extension signing entitlement group mismatch'
extension_sign_line="$(grep -n 'NeedlbarWidgetExtension.appex' "$case_root/commands.log" | head -n 1 | cut -d: -f1)"
host_sign_line="$(grep -n 'codesign:sign:.*Needlbar\.app$' "$case_root/commands.log" | head -n 1 | cut -d: -f1)"
[[ "$extension_sign_line" =~ ^[0-9]+$ && "$host_sign_line" =~ ^[0-9]+$ ]] || fail 'Developer ID sign records missing'
(( extension_sign_line < host_sign_line )) || fail 'Developer ID host signing preceded extension signing'

echo 'notarize-app shell contracts passed'
