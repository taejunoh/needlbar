# Needlbar Tagless Release Validation and Notarization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable, testable Developer ID signing and notarization validation path that produces a verified arm64 ZIP without creating a tag or public GitHub Release.

**Architecture:** Existing `scripts/package-app.sh` and `scripts/smoke-app.sh` remain the ad-hoc build boundary. New `scripts/notarize-app.sh` owns the security-sensitive signing boundary: temporary keychain/P12 provisioning, identity checks, notarization, stapling, Gatekeeper checks, extracted-ZIP revalidation, and atomic final ZIP replacement. One protected `validate` workflow job calls it for manual dispatch and version tags; a separate tag-only `publish` job receives the validated artifact.

**Tech Stack:** Bash 3.2-compatible shell, macOS `security`, `codesign`, `xcrun notarytool`, `xcrun stapler`, `spctl`, `zip`, `ditto`, GNU Make, GitHub Actions, protected GitHub Environments, and fake-command shell contract tests.

**Spec:** `docs/superpowers/specs/2026-08-27-release-validation-and-notarization-design.md`

## Global Constraints

- This work is release-validation plumbing only: do not create/push a tag, public GitHub Release, release asset, or distribution.
- Do not configure GitHub secrets/settings, request secrets in chat, record secret values, inspect credential contents, or place any secret in source, logs, artifacts, screenshots, comments, or test fixtures.
- The protected GitHub Environment is exactly `release`. Its exact secret names are `DEVELOPER_ID_APPLICATION`, `DEVELOPER_ID_APPLICATION_CERTIFICATE`, `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`.
- An unset or blank input fails before keychain creation, signing, notarization, artifact upload, or publication. Safe errors list variable names only.
- The currently inspected identity metadata is `Developer ID Application: Taejun Oh (3BMF4LM6TM)`; never commit its certificate, private key, or password.
- Preserve macOS 14+, arm64-first packaging, Xcode 16.2 selection, package/smoke behavior, pinned `tokscale-core`, and all Cursor local-cache-only/privacy behavior.
- The script uses `set -euo pipefail`, Bash 3.2-compatible syntax, `umask 077`, quoted exact paths, and an `EXIT` cleanup trap installed before sensitive files exist.
- Stable validation requires the exact configured Developer ID identity, `--options runtime`, `--timestamp`, configured Team ID, successful notarization, staple validation, Gatekeeper assessment, and extracted-final-ZIP revalidation. It never accepts ad-hoc signing as a stable result.
- Submission/final archives use `COPYFILE_DISABLE=1 zip -qryX`; final `dist/Needlbar-macos-arm64.zip` replacement occurs only after every extracted candidate check passes.
- Cleanup restores the caller's keychain search list and removes only exact invocation-owned temporary paths. Preserve the original failure status even if cleanup also fails.
- Validation has only `contents: read`; only a guarded tag-push publish job has `contents: write`. No workflow-level write permission.
- Pin every `uses:` in `.github/workflows/ci.yml` and `.github/workflows/release.yml` to a verified full 40-character SHA. At implementation time verify the current action commit against its official upstream repository/tag; no mutable `@v*` reference remains.
- Credentialed acceptance occurs only after PR merge to `main`, in the protected Environment, by an authorized maintainer. Successful validation never authorizes a tag/release.

---

## File Map

| File | Change | Responsibility |
| --- | --- | --- |
| `scripts/notarize-app.sh` | Create | Production preflight, temporary keychain/P12 lifecycle, exact signing checks, notarization/stapling, final archive checks, atomic replacement, cleanup. |
| `scripts/tests/notarize-app-tests.sh` | Create | Fake-command contract tests for success/failure, cleanup/redaction, archive sequencing, and workflow structure. |
| `Makefile` | Modify | Add `notarize-test` and include it in credential-free `make test`. |
| `.github/workflows/release.yml` | Modify | Manual tagless validation, protected `release` environment, concurrency, artifact handoff, tag-only publication, least privilege. |
| `.github/workflows/ci.yml` | Modify | Pin existing Actions to verified full SHAs while preserving CI behavior. |
| `README.md` | Modify | Bound maintainer-facing tagless validation statement; retain no-public-release notice. |
| `docs/STATUS.md` | Modify | Record code/test results and protected external gate without claiming real credentials, notarization, tag, or release. |

## Interfaces

`scripts/notarize-app.sh` takes no positional arguments. It consumes the six protected values and only these documented path overrides:

```bash
APP_PATH="${NEEDLBAR_NOTARIZE_APP_PATH:-$ROOT/dist/Needlbar.app}"
ZIP_PATH="${NEEDLBAR_NOTARIZE_ZIP_PATH:-$ROOT/dist/Needlbar-macos-arm64.zip}"
TEMP_PARENT="${NEEDLBAR_NOTARIZE_TEMP_PARENT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
```

It exits 0 only after extracting a candidate final archive and rechecking its app signature, staple, and Gatekeeper assessment. On success it replaces only `ZIP_PATH`; on failure it leaves any existing `ZIP_PATH` untouched.

`scripts/tests/notarize-app-tests.sh` takes no positional arguments. It changes to `ROOT`, makes one `mktemp -d "${TMPDIR:-/tmp}/needlbar-notarize-test.XXXXXX"` fixture root, builds a single shared `"$temp_root/fake-bin"`, copies the script under test into each disposable case repository, prepends that shared fake-bin to `PATH`, and removes precisely the fixture root in its `EXIT` trap.

### Task 1: Define fake-command notarization contracts

**Files:**
- Create: `scripts/tests/notarize-app-tests.sh`
- Test: `scripts/tests/notarize-app-tests.sh`

**Interfaces:**
- Consumes: future executable `scripts/notarize-app.sh` and six protected variable names.
- Produces: a no-credential narrow test command.

- [ ] **Step 1: Create the test harness and exact cleanup boundary**

```bash
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
```

Keep every fixture path beneath `"$temp_root"`; do not use Documents, a home directory, a repository fixture, or an unresolved glob.

- [ ] **Step 2: Create safe fake commands**

Create executable fake `security`, `codesign`, `xcrun`, `spctl`, `zip`, `ditto`, `base64`, and `uuidgen` once in `"$fake_bin"`, then use that same directory for every case. Every fake uses:

```bash
record_stage() {
  printf '%s\n' "$1" >> "$FAKE_COMMAND_LOG"
}
```

Record only `security:create-keychain`, `security:import`, `security:set-list`, `security:restore-list`, `security:delete-keychain`, `codesign:sign`, `codesign:verify`, `codesign:display`, `xcrun:notarytool-submit`, `xcrun:stapler-staple`, `xcrun:stapler-validate`, `spctl:assess`, `zip:submission`, `zip:final`, and `ditto:extract`. Never log argv, stdin, environment variables, P12 bytes, passwords, or Apple IDs.

Support deterministic test controls: `FAKE_NOTARY_FAIL=1`, `FAKE_NOTARY_STDERR_CANARY`, `FAKE_NOTARY_SIGNAL=INT|TERM`, `FAKE_STAPLE_FAIL=1`, `FAKE_STAPLER_VALIDATE_FAIL=1`, `FAKE_SPCTL_FAIL=1`, `FAKE_EXTRACTED_SPCTL_FAIL=1`, `FAKE_CODESIGN_TEAM_ID`, `FAKE_CODESIGN_RUNTIME`, `FAKE_SECURITY_IDENTITIES`, and `FAKE_EMPTY_KEYCHAIN_LIST=1`.

Fake `security find-identity -v -p codesigning` emits a concrete quoted record, and fake `codesign --display --verbose=4` returns only:

```text
  1) ABCDEF0123456789 "Developer ID Application: Test Signer (3BMF4LM6TM)"
Authority=Developer ID Application: Test Signer (3BMF4LM6TM)
TeamIdentifier=3BMF4LM6TM
Runtime Version=14.0.0
```

`FAKE_SECURITY_IDENTITIES` supplies the quoted identity text after the hash;
the fake always preserves the numeric/hash/quoted record shape. Team/runtime
controls replace only their respective display lines with
`TeamIdentifier=WRONGTEAMID` or `Runtime Version=`.

Fake `zip` parses the output path and accepts only the exact production staging
names: `*/notarization-submission.zip` records `zip:submission`; a basename
matching `.needlbar-final.*.zip` records `zip:final` and writes that exact path
to `"$FAKE_STATE_DIR/candidate-path"`. It writes the source app path into its
output marker. Fake `ditto -x -k` copies that source to
`"$destination/Needlbar.app"`. Fake `spctl` itself increments
`"$FAKE_STATE_DIR/spctl-count"` each time it runs and fails only on its second
call when `FAKE_EXTRACTED_SPCTL_FAIL=1`.

Fake `base64` is exactly `cat`, so it writes the test P12 canary to the private
P12 path without interpreting it. Fake `uuidgen` is exactly
`printf '%s\n' '00000000-0000-0000-0000-000000000000'`; it emits no credential
data and makes keychain-path cleanup deterministic.

Implement each named fake executable with its own exact case structure below;
no fake command may fall through to a real command:

```bash
# fake security
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
```

```bash
# fake codesign
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
```

```bash
# fake xcrun
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

# fake spctl
```

```bash
count=0; [[ ! -f "$FAKE_STATE_DIR/spctl-count" ]] || count="$(<"$FAKE_STATE_DIR/spctl-count")"
count=$((count + 1)); printf '%s\n' "$count" > "$FAKE_STATE_DIR/spctl-count"
record_stage spctl:assess
if [[ "${FAKE_SPCTL_FAIL:-}" == 1 ]] || { [[ "${FAKE_EXTRACTED_SPCTL_FAIL:-}" == 1 ]] && [[ "$count" -eq 2 ]]; }; then
  exit 74
fi
```

```bash
# fake zip: zip -qryX OUTPUT Needlbar.app
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

# fake ditto: ditto -x -k ARCHIVE DESTINATION
[[ "$1" == '-x' && "$2" == '-k' ]] || exit 64
archive_path="$3"
destination="$4"
record_stage ditto:extract
source_app="$(<"$archive_path")"
mkdir -p "$destination"
cp -R "$source_app" "$destination/Needlbar.app"
```

- [ ] **Step 3: Add concrete case/copy/invocation helpers with non-secret canaries**

Implement these exact helpers. `new_case` makes the application fixture and
copies/chmods the future production script, so the invoke path always exists.
`invoke_case` is the only script caller and always executes from `ROOT` with
the shared fake-bin.

```bash
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
```

Every negative-case call (missing secret, fake failure, and signal) must invoke
the helper in conditional context so `set -e` does not exit before its expected
non-zero status is asserted:

```bash
if invoke_case "$omitted_name"; then
  fail 'negative case unexpectedly succeeded'
fi
```

For a fake failure, export its named control before that conditional
`invoke_case` and unset it immediately afterward; because `invoke_case` runs
in a child subshell, the production script sees only that case's exported
control. Success-path tests must not print captured output.

- [ ] **Step 4: Write all six missing-secret cases**

Loop over exactly `DEVELOPER_ID_APPLICATION`, `DEVELOPER_ID_APPLICATION_CERTIFICATE`, `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`, clearing only the chosen variable in `invoke_case`. Require non-zero status, only the variable name in safe output, no `security:create-keychain`, unchanged final ZIP sentinel, zero canary matches, no private-temp child, and no same-directory candidate file.

```bash
if invoke_case "$missing_name"; then
  fail "missing $missing_name unexpectedly succeeded"
fi
[[ "$status" -ne 0 ]] || fail "missing $missing_name must fail"
grep -F "$missing_name" "$output_file" >/dev/null || fail "missing name not reported"
! grep -Fx 'security:create-keychain' "$command_log" >/dev/null || fail 'keychain created before preflight'
[[ "$(<"$final_zip")" == 'original-ad-hoc-zip' ]] || fail 'preflight replaced final ZIP'
! find "$(dirname "$final_zip")" -maxdepth 1 -name '.needlbar-final.*.zip' -print -quit | grep -q . ||
  fail 'missing-secret preflight left candidate ZIP'
```

- [ ] **Step 5: Run RED**

Run: `bash scripts/tests/notarize-app-tests.sh`

Expected: non-zero with `missing executable script: .../scripts/notarize-app.sh`; no real keychain, certificate, Apple account, clipboard, or network access.

- [ ] **Step 6: Commit the RED contract**

```bash
git add scripts/tests/notarize-app-tests.sh
git commit -m "test: define notarization shell contract"
```

### Task 2: Implement secure notarization and final archive validation

**Files:**
- Create: `scripts/notarize-app.sh`
- Modify: `scripts/tests/notarize-app-tests.sh`
- Test: `scripts/tests/notarize-app-tests.sh`

**Interfaces:**
- Consumes: the six protected values and path overrides above.
- Produces: executable `scripts/notarize-app.sh`, which replaces the expected ZIP only after all checks pass.

- [ ] **Step 1: Add identity, Team ID, and runtime RED cases**

Add cases using `FAKE_SECURITY_IDENTITIES='Developer ID Application: Different Signer (3BMF4LM6TM)'`, `FAKE_CODESIGN_TEAM_ID='WRONGTEAMID'`, and `FAKE_CODESIGN_RUNTIME=''`. Each requires non-zero status, safe phase copy (`identity`, `team`, or `hardened runtime`), no notary submission, unchanged sentinel, restored list/deleted keychain, deleted private files, absent candidate path, and zero canaries. Add `FAKE_EMPTY_KEYCHAIN_LIST=1` as a separate pre-mutation case: it requires `security:create-keychain`, `security:set-list`, and `security:restore-list` all absent, because the original list was never replaced; it still requires private/candidate cleanup and unchanged ZIP.

Use this exact assertion over test-owned paths:

```bash
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
```

- [ ] **Step 2: Add notary/staple/Gatekeeper/extracted ZIP RED cases**

- `FAKE_NOTARY_FAIL=1`: submission ZIP exists; no staple/final ZIP/output replacement.
- `FAKE_STAPLE_FAIL=1`: notarization occurred; no final ZIP/output replacement.
- `FAKE_STAPLER_VALIDATE_FAIL=1`: staple occurred; no `spctl`/final ZIP.
- `FAKE_SPCTL_FAIL=1`: staple validation occurred; no final ZIP.
- `FAKE_EXTRACTED_SPCTL_FAIL=1`: candidate final ZIP and extraction occurred, but expected final sentinel remains unchanged.

Every failure case asserts the expected final ZIP still contains
`original-ad-hoc-zip`, runs `assert_private_cleanup`, and checks all
output/log/surviving fixture files contain no canary. The success case asserts
the saved candidate path no longer exists after the atomic move and the final
ZIP marker changed only after all extracted-app checks passed.

- [ ] **Step 3: Add synchronous signal-cleanup contract cases**

`FAKE_NOTARY_SIGNAL=INT|TERM` makes fake `xcrun notarytool submit` record the
submission stage, send that signal to its direct parent (`"$PPID"`), and then
exit 0 immediately. Invoke the production script synchronously through
`invoke_case`: because the fake child exits, Bash can process the pending
signal trap and then its `EXIT` cleanup deterministically. Do not add a
background shell, readiness file, release file, polling loop, or timeout.

```bash
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
```

Both cases also require the saved candidate path to be absent (through
`assert_private_cleanup`) and the output/log/surviving fixture files to remain
canary-free (through `assert_no_canary`).

- [ ] **Step 4: Add successful sequence/redaction assertions**

Require this subsequence in the safe log:

```text
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
```

Require output ZIP to differ from `original-ad-hoc-zip`. Search `output.txt`, command log, final marker, and all surviving test-owned files for every canary; each search returns no match.

- [ ] **Step 5: Implement preflight and private lifecycle**

Create `scripts/notarize-app.sh`:

```bash
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
```

Before `mktemp`, require app, ZIP parent, temp parent, and commands `base64 security codesign xcrun spctl zip ditto mktemp uuidgen`. Build the required variable list, collect blank/missing names, and fail exactly:

```text
notarize-app: missing required signing/notarization inputs: NAME [...]
```

Only then create paths exactly as follows; this makes every cleanup target
invocation-owned and makes `mv` remain inside the final ZIP directory:

```bash
work_dir="$(mktemp -d "$TEMP_PARENT/needlbar-notarize.XXXXXX")"
p12_path="$work_dir/developer-id.p12"
keychain_path="$work_dir/signing.keychain-db"
submission_zip="$work_dir/notarization-submission.zip"
notary_output="$work_dir/notarytool-output.txt"
extract_root="$work_dir/extracted"
candidate_zip="$(mktemp "$(dirname "$ZIP_PATH")/.needlbar-final.XXXXXX.zip")"
rm -f -- "$candidate_zip"
```

The candidate path is recreated by `zip` and then either removed by cleanup or
atomically moved with same-directory `mv -f` after all checks pass.

- [ ] **Step 6: Install cleanup before P12 decoding**

```bash
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
```

Read the caller list before mutating it with the existing Bash 3.2-safe loop.
An empty/unparseable list is a safe pre-mutation failure, not an attempt to run
`security list-keychains -s` with zero identities:

```bash
while IFS= read -r keychain; do
  original_keychains+=("$keychain")
done < <(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')
[[ ${#original_keychains[@]} -gt 0 ]] || fail "could not capture caller keychain search list"
```

- [ ] **Step 7: Implement P12 import and exact sign checks**

```bash
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
```

Capture, never print, `security find-identity -v -p codesigning "$keychain_path"`; parse only its quoted identity field and require exactly one record exactly equal to `$DEVELOPER_ID_APPLICATION`:

```bash
identity_names="$(security find-identity -v -p codesigning "$keychain_path" \
  | sed -nE 's/^[[:space:]]*[0-9]+\) [[:xdigit:]]+ "(.*)"$/\1/p')"
identity_count="$(printf '%s\n' "$identity_names" | grep -Fxc "$DEVELOPER_ID_APPLICATION" || true)"
[[ "$identity_count" == 1 ]] || fail "configured Developer ID identity was not found exactly"
```

Sign exactly once:

```bash
codesign --force --deep --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
```

Capture `codesign --display --verbose=4 "$APP_PATH" 2>&1` and require exact
lines with `grep -Fx "Authority=$DEVELOPER_ID_APPLICATION"` and
`grep -Fx "TeamIdentifier=$APPLE_TEAM_ID"`, plus
`grep -E '^Runtime Version=.+$'`. Do not accept a substring identity or Team
ID match.

- [ ] **Step 8: Implement private submission and post-staple app checks**

```bash
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
```

The notary output file exists only below `work_dir` and cleanup removes it on
success/failure. Do not enable shell tracing, dump the environment, or retrieve
a notary log automatically. Make fake failed notary write
`FAKE_NOTARY_STDERR_CANARY` to stderr; the failed-notary test must prove the
canary appears neither in the script output nor in surviving fixture files.

- [ ] **Step 9: Implement extracted final ZIP checks and atomic replacement**

```bash
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
```

The script never calls package/smoke and never publishes.

- [ ] **Step 10: Run GREEN**

Run: `bash scripts/tests/notarize-app-tests.sh`

Expected: exit 0 with `notarize-app shell contracts passed`; no real credential/tool access.

- [ ] **Step 11: Commit**

```bash
git add scripts/notarize-app.sh scripts/tests/notarize-app-tests.sh
git commit -m "build: add notarization validation script"
```

### Task 3: Run fake notarization contracts through Make

**Files:**
- Modify: `Makefile`
- Test: `scripts/tests/notarize-app-tests.sh`

**Interfaces:**
- Consumes: Task 2's executable test suite.
- Produces: `make notarize-test`; standard `make test` runs it without credentials.

- [ ] **Step 1: Capture RED for narrow target**

Run: `make notarize-test`

Expected: non-zero with `No rule to make target 'notarize-test'`.

- [ ] **Step 2: Add targets**

```make
.PHONY: rust swift swift-test package-test notarize-test test run package smoke

notarize-test:
	./scripts/tests/notarize-app-tests.sh

test:
	cargo test --workspace --features bridge-test-runtime
	sh ./scripts/tests/vendor-tokscale-test.sh
	$(MAKE) swift-test
	$(MAKE) package-test
	$(MAKE) notarize-test
```

Do not add credentialed signing/notarization to `make test`.

- [ ] **Step 3: Verify narrow GREEN**

Run: `make notarize-test`

Expected: exit 0, no real keychain/protected Environment/tag/release/network notary access.

- [ ] **Step 4: Verify full GREEN**

Run: `make test`

Expected: exit 0 including Rust/Swift/package tests and fake notarization contracts.

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "test: run notarization contracts in make test"
```

### Task 4: Split tagless validation from tag-only publication

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/tests/notarize-app-tests.sh`
- Test: `scripts/tests/notarize-app-tests.sh`

**Interfaces:**
- Consumes: `scripts/notarize-app.sh`, `make test`, `make package`, `make smoke`, and protected `release` Environment variables.
- Produces: artifact `Needlbar-macos-arm64-notarized`, job `validate`, and job `publish`.

- [ ] **Step 1: Add workflow RED assertions**

Add `test_release_workflow_contract` to the shell suite. It asserts `workflow_dispatch:`, `tags: ["v*"]`, `concurrency:`, `cancel-in-progress: false`, `validate:`, `environment: release`, `contents: read`, `publish:`, and this exact predicate:

```bash
github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')
```

Set `release_workflow="$ROOT/.github/workflows/release.yml"` and
`ci_workflow="$ROOT/.github/workflows/ci.yml"` at the start of this function;
every `grep`, `awk`, and `rg` in this contract uses those absolute paths. Use
`awk` to prove no top-level write permission exists and `contents: write` occurs
only after the `publish:` header. Verify `validate` runs `make test`, `make
package`, `make smoke`, and `./scripts/notarize-app.sh`; verify `publish`
downloads `Needlbar-macos-arm64-notarized` and contains no package/sign/notarize
command.

Assert all Actions references are full commit SHAs:

```bash
while IFS= read -r uses_line; do
  [[ "$uses_line" =~ @[0-9a-f]{40}$ ]] || fail "action is not commit pinned: $uses_line"
done < <(rg '^[[:space:]]*uses:' "$ci_workflow" "$release_workflow")
```

- [ ] **Step 2: Run workflow RED**

Run: `bash scripts/tests/notarize-app-tests.sh`

Expected: non-zero because current workflow lacks manual dispatch, has workflow-wide write permission, lacks split jobs/artifact route, and uses mutable action tags.

- [ ] **Step 3: Resolve and verify action commit pins**

The current resolution at plan-writing time is listed below. The implementation
must rerun these commands immediately before editing, compare the selected
commit to the official upstream tag/release page, and replace the literal only
if current upstream provenance confirms it:

```bash
git ls-remote https://github.com/actions/checkout.git refs/tags/v4 'refs/tags/v4^{}'
git ls-remote https://github.com/actions/upload-artifact.git refs/tags/v4 'refs/tags/v4^{}'
git ls-remote https://github.com/actions/download-artifact.git refs/tags/v4 'refs/tags/v4^{}'
git ls-remote https://github.com/softprops/action-gh-release.git refs/tags/v2 'refs/tags/v2^{}'
```

The resolved literal commit pins are:

```text
actions/checkout@11d5960a326750d5838078e36cf38b85af677262
actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093
softprops/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65
```

Record the immediately reverified values in review evidence. Do not retain a symbolic tag, short SHA, unverified fork, or value from an issue/comment.

- [ ] **Step 4: Implement release workflow**

Committed YAML must use the reverified full SHAs from Step 3. With the values
resolved above, its complete required job structure is:

```yaml
on:
  workflow_dispatch:
  push:
    tags: ["v*"]

concurrency:
  group: release-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: read

jobs:
  validate:
    runs-on: macos-14
    timeout-minutes: 45
    environment: release
    permissions:
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262
        with:
          submodules: recursive
      - name: Install Rust if needed
        shell: bash
        run: |
          set -euo pipefail
          if ! command -v cargo >/dev/null 2>&1; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
            echo "$HOME/.cargo/bin" >> "$GITHUB_PATH"
          fi
      - name: Select Swift 6 toolchain
        shell: bash
        run: |
          set -euo pipefail
          sudo xcode-select --switch /Applications/Xcode_16.2.app
          xcodebuild -version
          swift --version
      - name: Verify complete project
        run: make test
      - name: Package arm64 app
        run: make package
      - name: Smoke-test packaged app
        run: make smoke
      - name: Sign, notarize, staple, and validate
        env:
          DEVELOPER_ID_APPLICATION: ${{ secrets.DEVELOPER_ID_APPLICATION }}
          DEVELOPER_ID_APPLICATION_CERTIFICATE: ${{ secrets.DEVELOPER_ID_APPLICATION_CERTIFICATE }}
          DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD }}
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
        run: ./scripts/notarize-app.sh
      - name: Upload notarized arm64 validation artifact
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
        with:
          name: Needlbar-macos-arm64-notarized
          path: dist/Needlbar-macos-arm64.zip
          if-no-files-found: error

  publish:
    needs: validate
    if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Download validated release artifact
        uses: actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093
        with:
          name: Needlbar-macos-arm64-notarized
          path: dist
      - name: Publish notarized GitHub Release
        uses: softprops/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65
        with:
          files: dist/Needlbar-macos-arm64.zip
```

Map all six `${{ secrets.* }}` values only into the validation script's environment. Do not add a manual publish input or any route by which `workflow_dispatch` can satisfy `publish`. If re-verification yields newer official commits, replace all matching lines with those reverified literal values and record why.

- [ ] **Step 5: Pin CI actions without semantic change**

Replace `actions/checkout@v4` with `actions/checkout@11d5960a326750d5838078e36cf38b85af677262` and `actions/upload-artifact@v4` with `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` in `.github/workflows/ci.yml`; use reverified replacements if Step 3 finds newer official pins. Keep CI triggers, `contents: read`, submodules, all test/lint/package/smoke steps, and artifact name/path unchanged.

- [ ] **Step 6: Run workflow GREEN**

Run: `bash scripts/tests/notarize-app-tests.sh`

Expected: exit 0. It proves manual dispatch cannot publish, only push tag refs can, the permission split is present, all Actions pins are full SHAs, and script fake tests remain green.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/release.yml .github/workflows/ci.yml scripts/tests/notarize-app-tests.sh
git commit -m "ci: add tagless notarization validation"
```

### Task 5: Document the remaining protected external gate

**Files:**
- Modify: `README.md`
- Modify: `docs/STATUS.md`
- Modify: `scripts/tests/notarize-app-tests.sh`
- Test: `scripts/tests/notarize-app-tests.sh`

**Interfaces:**
- Consumes: Task 4 workflow/job names and approved no-tag/no-release boundary.
- Produces: accurate maintainer continuation state.

- [ ] **Step 1: Add documentation RED checks**

```bash
readme_file="$ROOT/README.md"
status_file="$ROOT/docs/STATUS.md"
grep -F 'No public GitHub Release or notarized download is available yet.' "$readme_file" >/dev/null
grep -F 'tagless' "$readme_file" >/dev/null
grep -F 'no tag or release action is authorized' "$status_file" >/dev/null
grep -F 'Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration.' "$readme_file" >/dev/null
grep -F 'Cursor usage has no Needlbar-owned hydration layer' "$status_file" >/dev/null
```

These checks require no protected value or GitHub API call.

- [ ] **Step 2: Run documentation RED**

Run: `bash scripts/tests/notarize-app-tests.sh`

Expected: non-zero because README lacks protected tagless validation copy and STATUS lacks this implementation gate.

- [ ] **Step 3: Update README**

Immediately after current Availability paragraph add exactly:

```markdown
Maintainer-only release validation is performed through a protected, tagless GitHub Actions workflow. It can sign, notarize, staple, and validate a workflow artifact without creating a public release; it does not make a release available for download. Creating a version tag or public GitHub Release requires separate explicit authorization.
```

Do not include secret names/values, certificate-export instructions, or a public-release availability claim.

- [ ] **Step 4: Update STATUS with facts only**

Add a dated continuation entry stating: reusable fake-tested script/split workflow are implemented; manual dispatch is tagless and produces only an Actions artifact; `validate` is read-only and `publish` is write-enabled only for future push tags `v*`; this implementation did not configure/read a protected secret; no real notarization/stapling/Gatekeeper acceptance, merge, tag, public Release, or distribution is claimed; next gate is merge to `main`, authorized protected Environment setup outside chat, then tagless manual validation.

Preserve historical Cursor-session evidence only as superseded history. Active status must say Cursor is local-cache-only and never request/record a Cursor session token.

- [ ] **Step 5: Run documentation GREEN**

Run: `bash scripts/tests/notarize-app-tests.sh`

Expected: exit 0; bounded no-public-release copy and Cursor privacy checks pass.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/STATUS.md scripts/tests/notarize-app-tests.sh
git commit -m "docs: describe tagless release validation"
```

### Task 6: Verify code and hand off protected acceptance

**Files:**
- Verify: `scripts/notarize-app.sh`
- Verify: `scripts/tests/notarize-app-tests.sh`
- Verify: `Makefile`
- Verify: `.github/workflows/release.yml`
- Verify: `.github/workflows/ci.yml`
- Verify: `README.md`
- Verify: `docs/STATUS.md`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: a clean reviewable PR; never produces a tag, public release, real notarization result, or GitHub Environment change.

- [ ] **Step 1: Run focused fake contracts**

Run: `make notarize-test`

Expected: exit 0 with no real keychain, certificate, Apple account, GitHub Environment, tag, release, or network notarization use.

- [ ] **Step 2: Run project verification**

Run: `make test`

Expected: exit 0 including fake notarization, Rust workspace, explicit pinned vendor path, Swift, and package relink checks.

- [ ] **Step 3: Run package/smoke verification**

Run:

```bash
make package
make smoke
```

Expected: both exit 0. The result remains ad-hoc signed and neither command requests Developer ID/notary input.

- [ ] **Step 4: Run hygiene checks**

Run:

```bash
bash scripts/tests/notarize-app-tests.sh
git diff --check
git status --short
```

Expected: all checks pass, no non-SHA action references remain, no plan notation remains in committed YAML, and no unexpected working-tree changes remain after commits.

- [ ] **Step 5: Request review before protected external work**

Review path containment, cleanup on all exits, Bash 3.2 compatibility, secret redaction, exact identity/team/runtime checks, candidate ZIP atomicity, extracted ZIP validation, manual nonpublication, publish predicate, permission split, action provenance pins, and unchanged Cursor local-only behavior. Fix each finding in a focused commit and rerun affected and full gates.

- [ ] **Step 6: Commit actual review fixes only**

```bash
git add scripts/notarize-app.sh scripts/tests/notarize-app-tests.sh Makefile \
  .github/workflows/release.yml .github/workflows/ci.yml README.md docs/STATUS.md
git commit -m "build: validate notarized release artifacts"
```

Preserve focused Task 1–5 commits; do not make an empty commit.

- [ ] **Step 7: Hand off, but do not execute, protected tagless acceptance**

After PR merge to `main`, an authorized maintainer outside chat must:

1. Configure protected GitHub Environment `release` with maintainer-chosen reviewers and branch/tag policy.
2. Set the six exact Environment secret names using GitHub's secure UI or another maintainer-controlled secure channel.
3. Run **Release** via `workflow_dispatch` on `main`; do not create a tag.
4. Require `validate` to pass `make test`, `make package`, `make smoke`, `scripts/notarize-app.sh`, and notarized-artifact upload.
5. Download `Needlbar-macos-arm64-notarized` to a supported macOS 14+ arm64 Mac, extract it, and verify Developer ID identity, hardened runtime, staple validation, Gatekeeper assessment, and launch behavior.
6. Record only safe results: run URL, commit, pass/fail, artifact checksum, and no-public-release fact. Never record secrets, certificate data, account identifiers, passwords, or credential-derived output.

This handoff ends before a tag/public release. A future `v*` tag and GitHub Release require a new explicit user authorization.

## Plan Self-Review

### Spec coverage

- Reusable script; private submission archive; temporary keychain/P12 lifecycle; identity/team/runtime, notarization, staple, Gatekeeper, extracted ZIP, and atomic replacement: Task 2.
- Fake RED/GREEN cases for all secrets, exact quoted identity/team/runtime, notary stderr redaction, notary/staple/Gatekeeper/extraction failure, synchronous child-signalled INT/TERM cleanup, ordering, candidate staging cleanup, and output preservation: Tasks 1–2.
- `workflow_dispatch`, tag validation before separate publish, concurrency, protected Environment, artifact handoff, permission split, action pins, CI pinning: Task 4.
- Makefile/full test/package/smoke verification: Tasks 3 and 6.
- README/STATUS, PR-to-main prerequisite, protected manual gate, no-tag/no-release boundary, and Cursor local-only preservation: Tasks 5–6.

Every approved requirement is assigned.

### Placeholder, interface, and Bash review

The plan gives concrete fake executable dispatch, shared fake-bin, case-copy, invocation, synchronous child-signalled signal, candidate-path, canary, and private-output helpers; it leaves no deferred test behavior or blocking loop. Task 4 records the current complete commit pins and requires official-upstream re-verification immediately before implementation, so final YAML cannot rely on a mutable action tag. All tasks consistently use `scripts/notarize-app.sh`, `scripts/tests/notarize-app-tests.sh`, `make notarize-test`, `NEEDLBAR_NOTARIZE_APP_PATH`, `NEEDLBAR_NOTARIZE_ZIP_PATH`, `NEEDLBAR_NOTARIZE_TEMP_PARENT`, Environment `release`, jobs `validate`/`publish`, artifact `Needlbar-macos-arm64-notarized`, and output `dist/Needlbar-macos-arm64.zip`.

All shell snippets are Bash 3.2-compatible: indexed arrays, process substitution, `[[ ]]`, `local`, `sed -E`, `grep -Fxc`, and arithmetic expansion are supported; the plan uses no associative arrays, `mapfile`, negative array indices, `wait -n`, or Bash 4-only parameter forms. Workflow/document assertions execute from `ROOT` and use absolute `$ROOT/...` paths.
