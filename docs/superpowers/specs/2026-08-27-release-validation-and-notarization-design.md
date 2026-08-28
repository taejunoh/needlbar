# Needlbar Tagless Release Validation and Notarization Design

**Status:** Approved on 2026-08-27 for implementation planning
**Scope:** Release validation and notarization plumbing only; this scope does not authorize a tag, public GitHub Release, or distribution.
**Supersedes:** The release-path portion of `docs/superpowers/plans/2026-08-13-needlbar-v0.1.md` where it conflicts with the tagless validation gate below.
**Related contracts:**

- `docs/superpowers/specs/2026-08-26-cursor-local-usage-dashboard-quota-design.md` — current Cursor privacy and local-only behavior.
- `docs/superpowers/plans/2026-08-13-needlbar-v0.1.md` — Task 15, “Package an Installable arm64 macOS v0.1 Artifact”.

## 1. Context and Problem

Needlbar already builds an arm64 macOS app bundle, an ad-hoc signed package, and a packaged-app smoke test. The existing release workflow is tag-triggered and combines signing, notarization, and public GitHub Release publication in one path. That makes it difficult to validate the real distribution boundary before a release is intentionally created, and it risks publishing an ad-hoc artifact if stable-release credentials are incomplete.

The approved next step is a protected, repeatable validation path that can run without a tag and without publishing anything. It must use the same package output and the same signing/notarization checks that a future stable release will use, while keeping credentials out of source, logs, artifacts, and chat. A future tag/release path remains available but is separately authorized and is not part of this acceptance.

At the time of this design, local inspection found the valid signing identity metadata:

`Developer ID Application: Taejun Oh (3BMF4LM6TM)`

No GitHub secrets are currently configured. No secret values belong in this document, in repository files, or in conversation.

## 2. Goals

1. Provide a single reusable `scripts/notarize-app.sh` entry point for local validation and CI.
2. Allow a manually dispatched, tagless GitHub Actions run to build, sign, notarize, staple, and verify an arm64 artifact without creating a GitHub Release.
3. Preserve a future `v*` tag path whose validation runs before a separate publish job.
4. Require all six signing/notarization inputs and fail clearly before any publication when one is missing or invalid.
5. Verify the exact Developer ID identity, Apple Team ID, hardened runtime, notarization result, staple, Gatekeeper assessment, and final ZIP contents.
6. Exercise failure handling and cleanup using fake command seams without using real credentials in tests.
7. Keep the existing Needlbar package, smoke, privacy, and Cursor local-only contracts unchanged.

## 3. Non-Goals and Explicit Boundaries

- No tag creation, tag push, public GitHub Release, or GitHub Release asset publication in this implementation or acceptance run.
- No configuration of GitHub secrets by an agent and no request for secret values through chat.
- No change to the Cursor local-cache-only amendment. Needlbar must not restore Cursor session tokens, browser-profile access, private Cursor API requests, or remote usage hydration.
- No change to Claude/Codex provider behavior.
- No replacement for `scripts/package-app.sh` or `scripts/smoke-app.sh`; the validation script consumes their packaged app and verifies the signed result.
- No ad-hoc stable artifact publication. A future stable tag must fail closed if the protected release credentials are absent or invalid.
- No release-notarization claim based only on a mocked test; the real notarization acceptance requires a user-authorized, protected environment with valid credentials.

## 4. Approaches Considered and Decision

### 4.1 Keep all signing logic inline in workflow YAML

This is the smallest textual change, but it duplicates security-sensitive shell logic across local and CI contexts and makes cleanup, ordering, and failure behavior difficult to test.

### 4.2 Add a second validation workflow

A separate workflow could be dispatch-only, but it would duplicate build/package steps and create drift from the eventual release path. It also makes it easier for a future fix to land in one path but not the other.

### 4.3 Chosen: extract signing/notarization into `scripts/notarize-app.sh`

The chosen approach extracts the complete signing, notarization, stapling, and post-archive verification sequence into `scripts/notarize-app.sh`. The release workflow invokes that script from a validation job for both `workflow_dispatch` and `v*` tag events. A separate publish job is gated exclusively on a version-tag push and receives the validated artifact. This gives local and CI runs the same ordered boundary, a small fake-command test surface, and an explicit permission split.

## 5. Architecture

### 5.1 `scripts/notarize-app.sh`

The script takes the existing `dist/Needlbar.app` and the expected output path `dist/Needlbar-macos-arm64.zip`, or accepts explicit paths through documented environment variables if the implementation needs a test fixture. The input ZIP may be the ad-hoc package output, but it is never treated as the notarized result: the script creates a private submission archive and later creates a new final archive from the stapled app. It runs with `set -euo pipefail`, uses a private temporary directory, and installs an `EXIT` cleanup trap before creating sensitive files.

The ordered production flow is:

1. Validate that the app, final-ZIP parent directory, and required tools exist; the package ZIP, if present, is only the ad-hoc input that will be replaced after validation.
2. Require all six inputs listed in Section 6, without printing their values.
3. Create a random-password temporary keychain and a temporary P12 file under the runner temp directory.
4. Decode the certificate secret into the P12 file with mode `0600` under `umask 077`.
5. Import only that P12 into the temporary keychain, unlock it, configure the codesign partition list, and make the temporary keychain available for signing.
6. Confirm that the requested Developer ID identity exists in the temporary keychain and matches the exact configured identity. Confirm that the configured Team ID is the expected account/team value used by the certificate and notarization request.
7. Re-sign the app with the exact identity, `--options runtime`, and a timestamp. No ad-hoc identity is accepted in this path.
8. Run `codesign --verify --deep --strict` and inspect the signing identity and hardened-runtime requirement.
9. Create a private temporary notarization-submission ZIP from the signed app using deterministic, host-metadata-free archive options. This submission ZIP is never the published output.
10. Submit the private submission ZIP with `xcrun notarytool submit`, using Apple ID, Team ID, and app-specific password credentials, and wait for the notarization result.
11. Staple the notarization ticket to the signed app and run `xcrun stapler validate`.
12. Re-run codesign verification and `spctl --assess --type execute --verbose` against the stapled app.
13. Create a candidate final ZIP in a private temporary output path from the stapled app, again using deterministic, host-metadata-free archive options. Extract that candidate final ZIP into a fresh private temporary directory and repeat codesign verification, stapler validation, and Gatekeeper assessment against the extracted app. This confirms that the distributed archive, not only the pre-archive directory, is valid.
14. Atomically replace `dist/Needlbar-macos-arm64.zip` with the validated candidate final ZIP only after every extracted-app check passes, preserving the expected artifact name. The private submission ZIP and candidate staging paths are then removed by the cleanup trap.

The script must never echo secret-bearing command lines. It must not print the P12 bytes, keychain password, app-specific password, Apple ID password equivalent, raw notary output containing credential context, or any serialized credential. Failure output uses safe step names and exit status. The script may print non-secret identity metadata and tool diagnostics after redaction, but must not include environment dumps.

The script must restore the caller's keychain search list and delete the temporary keychain, P12, submission ZIP, candidate final ZIP, extracted app, and private temporary directory on both success and failure. Cleanup is best effort after preserving the original failure status; cleanup failure must still be visible and must not turn a failed validation into success. No broad home-directory or repository deletion is permitted.

### 5.2 GitHub Actions workflow

`.github/workflows/release.yml` supports both:

- `workflow_dispatch` for tagless validation, and
- `push` tags matching `v*` for a future stable release.

The workflow uses concurrency keyed by workflow/ref so duplicate validations for the same ref do not race over artifacts or environments.

#### Validation job

The validation job:

1. Runs on the approved `macos-14` baseline and selects the Swift 6-capable Xcode toolchain already used by CI.
2. Checks out the repository with recursive submodules.
3. Runs `make test`, `make package`, and `make smoke`.
4. Uses the protected GitHub `release` Environment to obtain signing/notarization inputs.
5. Invokes `scripts/notarize-app.sh`.
6. Uploads the resulting arm64 ZIP as a workflow artifact only after all checks pass.

The validation job declares `contents: read`. It does not have permission to create releases, tags, or other repository writes. On `workflow_dispatch`, this job is the complete workflow outcome: the artifact is downloadable from the Actions run, but no public Release is created.

#### Publish job

The publish job is a distinct job with `contents: write` and is guarded by the conjunction:

`github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')`

It downloads only the validation artifact for the same run and invokes the GitHub Release action. It is never eligible during `workflow_dispatch`, even if a manual input is added later. Adding a tag or publishing a public Release remains a separately authorized future operation and is excluded from this validation run.

The workflow must not grant `contents: write` at the workflow top level. The validation job and publish job permissions remain visibly separate in YAML review.

## 6. Protected Environment and Secret Contract

The protected GitHub Environment is named `release`. Its reviewers and branch/tag policy are configured in GitHub by an authorized maintainer, outside this code change. The six existing secret names are:

1. `DEVELOPER_ID_APPLICATION` — exact signing identity string, expected to be `Developer ID Application: Taejun Oh (3BMF4LM6TM)` for the currently inspected local certificate.
2. `DEVELOPER_ID_APPLICATION_CERTIFICATE` — base64-encoded P12 containing the exact Developer ID Application certificate and private key.
3. `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` — password for that P12.
4. `APPLE_ID` — Apple account identifier used by `notarytool`.
5. `APPLE_TEAM_ID` — Apple Developer Team ID used by `notarytool`.
6. `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password used by `notarytool`.

The implementation must treat an unset or blank value as missing and stop before signing or publication with a safe list of missing secret names. It must not print values, lengths that could identify values, or shell environments. The secret names may appear in a clear error because they are not secret values.

Provisioning is exact and ephemeral: decode only the configured certificate into an exact temporary P12 path, import only that P12 into an exact temporary keychain, and remove both in the cleanup trap. Use `umask 077`, random keychain/P12 paths below the runner's temporary directory, and a random keychain password. Never persist these values in repository files, caches, artifacts, screenshots, comments, or logs. Local validation may use the local certificate through the same temporary-keychain flow; no certificate or password is copied into chat.

## 7. Test-First Contract

Before implementing production shell logic, add contract tests around a fake-command directory placed first on `PATH`. The fake `security`, `codesign`, `xcrun`, `spctl`, `plutil`, `ditto`/archive, and filesystem helpers record only safe command names and non-secret arguments. They must not require or inspect a real keychain, Apple account, certificate, or clipboard.

Required red/green cases:

- Missing each required secret fails before keychain creation and names only the missing variable.
- A non-matching Developer ID identity fails closed.
- A Team ID mismatch fails closed.
- Missing hardened-runtime signing flags fails verification.
- Notarization submission failure propagates a non-zero status and prevents ZIP publication.
- Stapling or `stapler validate` failure propagates and prevents success.
- Gatekeeper or final extracted-ZIP verification failure propagates and prevents success.
- The exact sequence includes signing, private submission-ZIP creation, notarization, stapling, final-ZIP creation from the stapled app, and extracted-archive revalidation before atomic output replacement.
- Success and every failure path remove the temporary keychain and P12 and restore the original keychain list.
- Secret canaries never occur in captured stdout, stderr, command traces, generated artifacts, or cleanup diagnostics.
- `workflow_dispatch` never enables the publish job.
- Only a `push` event for a `v*` tag can enable the publish job; branch pushes and manual runs cannot.
- The validation job has `contents: read`; only the tag-only publish job has `contents: write`.
- The exact identity, Team ID, runtime option, `xcrun notarytool`, `xcrun stapler validate`, and `spctl` checks are all asserted.

The fake seam should be injected through command lookup and temporary paths rather than by weakening production checks. Tests must use disposable fixture directories under the repository's permitted Developer/LFG workspace or the system temporary directory and must clean exact paths afterward.

## 8. Error, Artifact, and Concurrency Handling

- Missing tools or missing secrets fail before any artifact is uploaded.
- Any signing, notarization, staple, Gatekeeper, archive, or extracted-ZIP check failure returns non-zero and leaves no publishable success signal.
- The workflow uploads the ZIP only after the full validation script succeeds. Failed runs may retain standard CI logs, but must not upload P12 files, keychains, credential files, or partially signed bundles.
- The package path remains arm64 and macOS 14-compatible. The validation job does not silently fall back to an ad-hoc stable artifact.
- The script uses exact paths and safe quoting; cleanup never expands an unresolved glob or broad directory.
- Concurrency cancels or serializes duplicate runs according to the repository's existing CI convention, but a canceled run cannot publish.
- Publish receives an artifact produced by the same successful run and does not rebuild or re-sign an unverified file.
- A manual validation produces no tag and no public Release. A future tag run may publish only after validation succeeds and only under the explicit tag-only condition.

## 9. Acceptance Criteria

1. A PR merge to `main` makes the workflow available for `workflow_dispatch`; before that merge, tagless manual validation is not claimed as available from the default-branch Actions UI.
2. With the six protected `release` Environment secrets configured by an authorized maintainer, a manual tagless run completes `make test`, `make package`, `make smoke`, signing, notarization, stapling, Gatekeeper verification, and final ZIP extraction/revalidation.
3. The resulting artifact is arm64, signed by the exact configured Developer ID identity, uses hardened runtime, has a valid staple, and passes `spctl` after extraction.
4. No secret value appears in workflow output, script output, artifacts, repository files, or chat.
5. Missing or invalid credentials fail closed without artifact publication and without a public Release.
6. Workflow permissions show `contents: read` for validation and `contents: write` only for the guarded tag-only publish job.
7. Contract tests cover missing secrets, identity/team/runtime checks, notarization/staple/Gatekeeper failures, cleanup, redaction, and event gating using fake commands.
8. Existing project verification remains green: `make test`, `make package`, and `make smoke`.
9. Cursor remains local-cache-only and no private Cursor authentication or endpoint behavior is reintroduced.
10. This acceptance creates no tag and no public GitHub Release. Any future tag/release execution requires separate explicit authorization.

## 10. Future, Separately Authorized Release

After tagless validation is green and a maintainer has reviewed the artifact, a later request may separately authorize a `v*` tag and public GitHub Release. That request must be treated as a new external-state operation. It must not be inferred from successful validation, and this design does not authorize creating the tag, publishing the Release, or changing release access policy.
