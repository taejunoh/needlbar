# README visual refresh design

**Date:** 2026-09-04

**Status:** Approved for implementation planning.

**Scope:** Update the repository root `README.md` with a current, light-mode
native visual set for the development system dashboard and Settings surfaces.
This design does not change application behavior, release artifacts, provider
contracts, or the public v0.2.2 download.

## 1. Purpose

The README screenshots should show the product as it exists today and make the
system-monitor work easy to understand before a reader installs it. The
screenshots must be native app-window captures at the actual dashboard width,
with enough content to represent the approved v0.3 development experience.
The README must continue to distinguish that development dashboard from the
public v0.2.2 release.

The visual refresh is documentation work only. It must not be used to change
layout, settings defaults, provider behavior, authentication, quota retrieval,
or release metadata.

## 2. Approved visual direction

Use light appearance and the exact packaged development app's native rendering
for every replacement image. Do not create synthetic HTML, fixture screenshots,
full-desktop captures, or screenshots of the public/release app.

The image set consists of three screenshots:

1. **Dashboard:** the main system-dashboard popover with all six system
   sections enabled and visible in this order: CPU, RAM, Disk, Network,
   Battery, and AI usage. Claude, Codex, and Cursor must all be visible in the
   AI section. Local and public IP display must both be off for the capture.
2. **Settings upper:** the current Settings window at the upper scroll
   position, showing module visibility controls and the local/public IP
   controls.
3. **Settings lower:** the same Settings window at the lower scroll position,
   showing provider visibility, order, selected display values, and provider
   actions as currently implemented.

The dashboard screenshot must be captured at the real 312-point popover width.
The Settings screenshots may use their native window width; do not crop or
stretch them to make them appear to be dashboard captures. The dashboard and
Settings lower screenshot must retain the official Claude, OpenAI
Blossom/Codex, and Cursor assets and the approved centered icon/title
alignment; the Settings upper screenshot is only required to show its module
and IP controls. Values may be native sample values, but they must not expose
private user data.

## 3. README content changes

Implementation may edit only `README.md` and add or replace the three images
listed below:

```text
docs/images/system-dashboard.png
docs/images/settings-modules.png
docs/images/settings-providers.png
```

Keep the existing user-first README structure and the exact public-release
boundary already established by the public README refresh specification:

- Keep the public v0.2.2 Apple-Silicon/macOS 14-or-later download and checksum
  links, verification command, Developer ID signing/notarization statement,
  and `/Applications` installation steps.
- Keep the explicit statement that `make package` creates a local ad-hoc
  evaluation bundle and is not a substitute for the public artifact.
- Keep the existing native macOS 14 acceptance caveat; do not imply that the
  local development capture proves Widget Gallery, App Group, notification,
  or macOS 14 acceptance.
- Keep current v0.2.2 usage/quota, export, widget/notification, and analytics
  descriptions accurate and user-facing.
- Keep provider support, privacy, development, limitations, and links intact
  unless a screenshot caption requires a small clarification.

The system-monitor section should be labeled clearly as a **v0.3 development
build** (or equivalent wording) and placed after the released v0.2.2 feature
groups. Its caption must state that the images are from a development build,
that values are native examples, and that provider visibility is configurable.
The README must not present these images as part of the public v0.2.2 ZIP.

Describe, without inventing capabilities, that the development dashboard can
combine CPU, RAM, disk, network, battery, and AI usage; that visibility and
provider display settings are configurable; and that IP values are omitted
from these screenshots. Add one concise sentence stating that the dashboard
uses the official Claude, OpenAI Blossom/Codex, and Cursor icons with centered
provider-title alignment. Do not add a new provider, new authentication flow,
telemetry, hosted service, or remote analytics claim.

Use descriptive alt text for all three images. Set the dashboard Markdown
display width to the actual 312-point width (the native image's pixel density
may produce a larger pixel file); do not imply that the README display width is
the screenshot's physical pixel width. Settings images should use a consistent
readable display width appropriate to their native window.

## 4. Safe native capture procedure

Capture from an isolated local development app and a temporary, reversible
configuration snapshot. The procedure is:

1. Confirm the worktree, app bundle, and executable identity. Build/package the
   current development app only; do not open the public/release app.
2. Before changing anything, export or record an exact snapshot of all
   relevant persisted settings: module visibility and order, provider
   visibility/order, provider metric selections, local-IP and public-IP
   toggles, appearance/window state, and any other setting the capture flow
   may touch. Store the snapshot outside the repository and do not include it
   in the README, images, logs, or commit.
3. Launch the isolated development app and enable the six dashboard modules
   and Claude/Codex/Cursor visibility only for the capture. Disable local and
   public IP display. Do not click provider sign-in, refresh, spending, export,
   notification, Keychain, or any other provider/account action.
4. Select light appearance if needed and open the dashboard. Wait only for
   local system rendering to settle. Capture the exact app window/popover by
   exact process/window identity, at native scale, with no desktop behind it
   included. Confirm the dashboard is 312 points wide and every required row is
   present before retaining the image.
5. Open Settings without changing any unrelated setting. Capture the upper
   and lower native window positions, ensuring that the module/IP controls and
   provider controls respectively are visible. Keep account identifiers,
   paths, IP values, credentials, and raw provider payloads out of frame.
6. Stop the isolated capture app if appropriate, restore the complete settings
   snapshot exactly, and verify that the restored values match the pre-capture
   snapshot. Do not leave the temporary visibility or appearance changes in
   the user's persisted configuration.
7. Inspect image dimensions, alpha/crop bounds, light appearance, app-only
   scope, required rows, official icons, and privacy redactions before adding
   the images to the repository.

If a state cannot be reached without a provider action, credential access,
network request, or unsafe data exposure, stop the capture and report the
constraint. Do not substitute a public/release app, synthetic data, or a
full-desktop screenshot to hide the failure.

## 5. Privacy and data-handling safeguards

The capture must be local-only and least-privilege. Specifically:

- Do not sign in, log out, refresh, open provider dashboards, trigger quota or
  usage actions, access Keychain, inspect credentials, paste tokens, or invoke
  provider-owned browser flows.
- Do not enable public-IP lookup or make any network request for the capture.
  Both IP toggles remain off; no local or public address may appear in an
  image, alt text, README text, command output copied into the repository, or
  committed metadata.
- Do not open or capture the public/release app, a release artifact, the
  desktop, another app, browser content, terminal content, or a full-screen
  workspace. Native app-window bounds must be established before capture.
- Treat any provider values, paths, account names, timestamps, or diagnostics
  visible during inspection as sensitive. Redact or discard an image rather
  than editing sensitive pixels into an apparently valid product screenshot.
- Keep temporary settings snapshots, build logs, window identifiers, process
  details, and rejected images outside the repository. Do not commit them.
- Use only the existing local development bundle and already-approved official
  provider assets. Do not download replacement assets during this task.

The README remains subject to the existing privacy policy: no credentials,
account identifiers, raw provider responses, prompts, assistant responses,
source code, raw paths, or telemetry claims may be introduced by the visual
refresh.

## 6. Validation and acceptance

Before committing the implementation, verify:

### Image validation

- Exactly three intended README images exist at the paths named above.
- The dashboard image is a native light-mode app-only capture at 312 points
  wide and shows CPU, RAM, Disk, Network, Battery, AI usage, Claude, Codex,
  and Cursor.
- The dashboard image contains no local/public IP values.
- Settings upper and lower images are native light-mode captures of the same
  current Settings UI and show their intended control groups.
- The dashboard and Settings lower images show official Claude/OpenAI
  Blossom/Cursor icons with the centered provider-title alignment; the Settings
  upper image is not required to contain provider rows or provider icons.
- Image dimensions, cropping, alpha, alt text, and Markdown display widths
  are consistent and readable.

### README and scope validation

- The v0.2.2 public/release section still links to the published artifact and
  checksum and does not call the v0.3 development images public-release UI.
- The v0.3 development boundary and native macOS 14 acceptance caveat remain
  explicit.
- No claims were added for login, Keychain, public-IP lookup, provider
  refresh, Cursor quota, telemetry, hosted services, analytics history, or
  native macOS 14 acceptance.
- `README.md` links and Markdown image paths resolve, and no credentials,
  addresses, or temporary paths occur in the changed text.
- Only the README and its three intended image files changed in the
  implementation commit; no `docs/STATUS.md`, application source, release
  workflow, public artifact, or approved spec is changed by implementation.
- Run the repository's documentation/release contract as applicable, then
  run `git diff --check` and inspect `git status --short` for scope.

The native captures are supplementary documentation evidence. They do not
replace automated tests, package/smoke checks, or the separate macOS 14 native
acceptance gate.

## 7. Failure, rollback, and ambiguity handling

If capture or validation fails, retain the pre-capture settings snapshot and
restore it before doing anything else. If exact restoration cannot be proven,
stop and report the mismatch; do not continue to README editing.

If an image contains private data, delete or quarantine that image outside the
repository, restore settings, and recapture only after the privacy issue is
understood. Do not blur or mask an accidental credential, token, IP address,
or account identifier and then treat the result as approved evidence.

If the 312-point geometry, required provider visibility, light appearance, or
official asset cannot be observed in the exact development app, stop and
surface the discrepancy instead of changing application code or inventing a
fixture. If the current README already contains a conflicting release or
feature claim, preserve the approved v0.2.2/v0.3 boundary and report the
conflict for maintainer decision rather than silently broadening scope.

Rollback consists of restoring the settings snapshot and reverting only the
README/image implementation changes from this task. No public release, app
installation, credentials, or unrelated worktree state may be rolled back or
deleted.

## 8. Non-goals

This design does not authorize:

- application layout or behavior changes;
- changing dashboard width, adaptive height, anchoring, scrolling, dismissal,
  provider alignment, or Settings controls;
- changing settings defaults or provider visibility outside the temporary,
  restored capture state;
- logging in, reading Keychain, handling credentials, making provider actions,
  or enabling public-IP/network access;
- opening or publishing the public/release app;
- creating synthetic or full-desktop screenshots;
- changing `docs/STATUS.md`, release workflows, package metadata, or approved
  specifications; or
- adding README claims beyond the currently implemented v0.2.2 public release
  and v0.3 development dashboard.
