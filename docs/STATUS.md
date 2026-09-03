# Needlbar Development Status

**Updated:** 2026-09-03
**Branch:** `codex/claude-fable-quota` from pushed `main` at `44a9ce3` (v0.2.2 public release remains at source `299c1a9eec04573d16469d5b6a7b6aab8fb559e8`).
**Current phase:** The user completed provider-owned sign-in; a fresh bounded HTTP 200 response closed Task 0's Fable `percent`-meaning gate. The approved Fable implementation can now proceed. Release publication remains unauthorized, and native macOS 14 acceptance remains deferred.
**Next action:** Execute Task 1 (headline/export compatibility protections) in `docs/superpowers/plans/2026-09-03-claude-fable-quota.md`, then Tasks 2–4 with test-first development and reviews. Keep the actual normal full-test result distinct from serial diagnostics; do not publish a release or claim native macOS 14 acceptance.

## Claude Fable implementation baseline — 2026-09-03

Before application edits, plain `make test` exited 0: Rust workspace and vendor
tests, Swift 336 tests in 12 suites, widget-extension, package, and notarization
contracts passed. Log:
`/Users/taejunoh/Developer/LFG/needlbar-fable-baseline.lmjRU9`.
This is fresh normal full-gate evidence on unchanged application code, not
serial-only evidence; it supersedes the earlier local baseline failures for
this run without deleting their history. Task 1 test-first implementation is
in progress. CI, release publication, and native macOS 14 acceptance are not
implied by this local result.

## Claude Fable source semantics verified — 2026-09-03

After the user reported sign-in complete, one fresh `BackgroundNoUI` request
resolved credentials and returned HTTP 200 in 3.902 seconds. Sanitized evidence
at `2026-09-03T14:16:43.832932Z`:

- Session `limits[].percent = 59` exactly matched `five_hour.utilization = 59`;
  both resets were `2026-09-03T16:59:59.792118Z`.
- Weekly-all `limits[].percent = 12` exactly matched `seven_day.utilization = 12`;
  both resets were `2026-09-10T09:59:59.792142Z`.
- Exactly one Fable entry matched `weekly_scoped`, `group=weekly`, model display
  name `Fable`, and explicit null surface. Its `percent = 14`, with reset
  `2026-09-10T09:59:59.792368Z`; `is_active = false` remained opaque metadata.

The same-response non-50 percent and exact reset matches satisfy the approved
semantic comparison gate: normalize source percent as used/utilization and
derive remaining in presentation. Fable was therefore 86% remaining at that
capture, not a guaranteed current value. No raw body, credential, account ID,
or real fixture was retained; no extra login, prompt, refresh, or retry occurred.
The external diagnostic helper was returned recoverably to its existing Trash
location. This is source-data evidence, not yet a native Needlbar Fable UI check.

## Claude Fable explicit-access diagnostic — 2026-09-03

The user approved one exact-item Keychain read that could display macOS's
permission prompt. The diagnostic reused the production resolver in
`UserInitiatedAllowUI` mode, with a 90-second outer deadline to allow time for
the user's system permission choice. It returned in 4.868 seconds:

```text
phase=parent_watchdog;status=user_initiated_started
phase=credential_resolution;status=started;mode=user_initiated_allow_ui
phase=credential_resolution;status=expired
phase=parent_watchdog;status=child_exited;elapsed_ms=4868
```

This is a typed expired-credential result, not a generic unavailable result or
proof that the user's account itself is signed out. No HTTP request, Fable
value, reset value, or source-semantics comparison occurred. No permission
dialog was reported, and no dialog choice was automated. The single-request
authorization has been consumed; no retry, provider login/refresh, credential
mutation, or app implementation was performed.

The main agent reran synthetic percent/reset-identity and exact-child watchdog
checks successfully. The helper was moved recoverably back to
`/Users/taejunoh/.Trash/needlbar-fable-limits-probe-Y8R2N`.
Task 0 remains blocked until provider-native authentication is refreshed and
actual response semantics are corroborated. The next user action is **Sign in
with Claude** in Needlbar Settings, not another diagnostic permission approval.

## Claude Fable bounded diagnostic checkpoint — 2026-09-03

One newly authorized non-interactive diagnostic ran with flushed phase markers
and a 20-second parent watchdog around the exact child, covering both resolver
and transport. It returned:

```text
phase=credential_resolution;status=started
phase=credential_resolution;status=unavailable
phase=parent_watchdog;status=child_exited;elapsed_ms=6849
```

No HTTP request occurred. This locates the current blocker at credential
resolution, but does not identify the underlying resolver error or explain
the earlier greater-than-30-second stall. Do not claim the account is signed
out or that macOS permission denial is proven. There was no live retry,
permission prompt, credential change, or app implementation.

The diagnostic also corrected two observation defects: compare actual parsed
reset timestamps instead of timestamp shapes, and drain final child output
after joining the reader. Synthetic checks for percent extraction, unequal
reset timestamps, forced child termination, and immediate-exit output all
passed. The main agent reran those synthetic checks successfully; they are
not live semantics evidence. The exact helper was returned recoverably to
`/Users/taejunoh/.Trash/needlbar-fable-limits-probe-Y8R2N`; no live probe remains.

Public first-party documentation confirms a shared weekly pool but does not
document the source field mapping. Native Claude UI inspection did not obtain
the Fable usage panel or numeric/reset evidence, and further UI interaction
was stopped. Task 0 remains open. Explicit user permission for a one-off
diagnostic read of the exact `Claude Code-credentials` Keychain item with a
macOS authorization prompt has been requested, not granted. No raw credential
or HTTP body may be printed or retained if that permission is later granted.

The user subsequently approved that one-off Keychain prompt on 2026-09-03.
This approval is limited to the diagnostic's exact-item user-initiated read;
it does not authorize automating the system permission choice, storing a
credential, changing Keychain access policy, retrying a denied request, or
changing Needlbar's background-authentication behavior.

## Claude Fable implementation-plan checkpoint — 2026-09-03

The user approved the written design. The plan now specifies the source
semantics gate, exact Swift compatibility projections, optional Rust parsing,
dashboard detail/freshness, consumer regressions, and integrated/native checks.
No application or fixture files changed during planning.

The corrected diagnostic passed a synthetic extraction test only. Its single
live follow-up emitted no output and remained alive beyond 30 seconds despite
the 15-second HTTP timeout. Exact process 48962 was terminated and confirmed
gone; the helper was returned to Trash and was not retried. There is no new
live numeric evidence and no established cause for the delay. Future diagnosis
needs an outer bound covering credential resolution as well as transport.
Task 0 remains blocked; the plan must not be mistaken for a verified mapping
from source `percent` to used/utilization. Existing full-test caveats below
remain unchanged; no product test result is claimed for this documentation step.

## Claude Fable quota design checkpoint — 2026-09-02

The user approved a separate Fable weekly remaining/reset row beneath the
existing Claude quota presentation; the menu-bar title and headline remain
unchanged. The review-ready design is
`docs/superpowers/specs/2026-09-02-claude-fable-quota-design.md`.

Two bounded non-interactive Rust requests returned HTTP 200 through the current
production resolver/background path and confirmed the exact `weekly_scoped`
Fable identity (`group=weekly`, model display name `Fable`, null model ID and
surface), plus `is_active`, numeric `percent`, and RFC3339 `resets_at`. The
agent output did not emit the actual Fable numeric value, and `percent` is not
yet proven to mean used/utilization. No live current remaining percentage is
claimed. Implementation is blocked until first-party semantics evidence closes
that gate; no app code changed in this step.

## v0.3 Local integration checkpoint — 2026-09-02

The approved dashboard refinement and Settings documentation were fast-forward
merged into `main` at `d719402` from `95d08c9`. This is an integration
checkpoint; no assertion of remote publication is made here. The README
now includes the inspected native dashboard and Settings screenshots; the
Settings captures show upper/lower scroll positions of one window, no IP or
account secrets, and unchanged current settings.

Verification evidence:

- Plain `make test` at `00fd6a3` exited 2 with six unchanged analytics
  process-fixture failures. `exited_parent_pipe_cleanup_returns_timeout_and_runner_is_reusable`
  first reported `ENOENT`; the remaining five reported guard poisoning. Log:
  `/Users/taejunoh/Developer/LFG/needlbar-make-test.XXXXXX.log`.
- A complete `RUST_TEST_THREADS=1 make test` in the same production tree
  exited 0, covering Rust, vendored tests, Swift (336 tests in 12 suites),
  widget, package, and notarization contracts. Log:
  `/Users/taejunoh/Developer/LFG/needlbar-merge-serial.tAvpVA`.
- A second `source /Users/taejunoh/.cargo/env && RUST_TEST_THREADS=1 make test`
  on merged HEAD `d719402` also exited 0 with the same Swift, Rust/vendor, and
  contract coverage. Log:
  `/Users/taejunoh/Developer/LFG/needlbar-merged-test.Hnd3Fy`.
- The serial success does not make the default parallel `make test` or CI gate
  green. Release publication remains unauthorized, and native macOS 14
  acceptance remains unperformed.

## AI remaining-quota default — 2026-09-02

The user approved making remaining subscription quota the default AI value in
the menu bar and dashboard. The scoped plan is
`docs/superpowers/plans/2026-09-02-ai-remaining-default.md`. The code is applied:
fresh/default and invalid persisted metric paths
use `.remaining`, while explicit saved Usage/Cost choices remain valid. Existing
quota selection, missing-value behavior, and provider actions are reused.

The current Mac's three provider metric keys were explicitly changed from
`usage` to `remaining` after gracefully stopping the exact development bundle;
visibility, order, IP preferences, and other settings were not changed. Native
picker automation exposed a non-settable AXValue, so this approved local update
used only the corresponding `com.taejunoh.needlbar` UserDefaults keys.

Regression evidence: RED reproduced the old `.usage` fallback; all 66 focused
configuration/model/menu/dashboard/controller/settings tests then passed.
Independent spec and quality reviews passed with no scoped issues. The current
`make test` attempt still fails two unchanged Codex shell-process tests
(`app_server_stderr_limit_fails_before_the_process_deadline` and
`app_server_transport_uses_the_documented_order_and_reaps_the_child`) with the
previously documented timeout behavior. No timeout, Rust code, or test assertion
was weakened. Logs: `ai-default-red.log`, `ai-default-green.log`, and
`ai-default-make-test.log` in the verification directory below. `make package`
and `make smoke` passed. The exact rebuilt development bundle was relaunched;
native Settings confirmed all three provider pickers read Remaining, with the
existing Claude-only visibility and IP settings unchanged. The live dashboard
confirmed the remaining-quota caption and displayed `—` while Claude quota was
Unavailable, even though token usage was Fresh (no token fallback). A live
numeric quota percentage is not claimed for that capture; fixture tests verify
the available-quota percentage path. Screenshot: `ai-remaining-native.png` in
the verification directory. The user explicitly authorized committing and
publishing this development checkpoint; it is merged into `main` at `d719402`.
This does not make the default full gate green or authorize release publication.

After the user completed Claude browser sign-in, a fresh native capture of the
same development app confirmed **22% remaining**, with both Usage and Quota
Fresh and no sign-in action. This completes the live numeric remaining-quota
check without changing authentication code. Evidence:
`ai-remaining-authenticated.png` in the verification directory. The existing
branch-wide process-test gate remains unchanged.

## v0.3 Dashboard Readability Follow-up — 2026-09-02

The user compared the running development build with Stats and approved the
recommended improvement direction. The design amendment is
`docs/superpowers/specs/2026-09-02-dashboard-readability-design.md`; the
implementation plan is `docs/superpowers/plans/2026-09-02-dashboard-readability.md`.

Confirmed source-level causes before implementation:

- Compact menu mode did not actually fit titles to a measured width.
- The open dashboard retained its initial snapshot instead of observing updates.
- Local IP always dumped all interface addresses without an opt-in setting.
- RAM included file-backed/purgeable cache; swap and disk I/O were hardcoded nil.
- Battery health mapped the qualitative Good state to an invented 100%.

Implemented on `codex/v03-dashboard-polish` in
`.worktrees/integration-main.d16P79` and fast-forward merged into `main` at
`d719402` (remote publication is not asserted here):

- Menu titles are measured using the menu font, capped at 240 points and three
  summaries, with a genuine icon-only fallback. CPU/RAM/AI are the defaults;
  existing saved preferences are preserved.
- One observable model updates the open dashboard without recreating its panel.
  CPU core bars occupy one row; gauges and bounded disk/network trends replace
  raw tables. The dashboard is 360 points wide, at most 680 points tall, with
  fixed header/footer and scrolling for additional content. Native inspection
  caught and corrected both excessive height and intrinsic gauge-size overlap.
- RAM excludes reclaimable cache, swap uses `vm.swapusage`, disk I/O follows
  the root volume's native storage counters, and battery health uses actual
  full-charge/design capacities. Memory pressure uses the sysctl's public
  flags (1 normal, 2 warning, 4 critical), not XNU's internal enum.
- Local IP is separately opt-in; public IP remains independently off by
  default. Transfer history is limited to 60 memory-only numeric samples, with
  gaps for missing/stale data and no IP addresses or persistence.
- README, architecture, and privacy documents describe these development-only
  changes. The public v0.2.2 artifact is unchanged.

Verification evidence:

- Independent spec/quality reviews were completed; identified regressions
  (counter-reset handling, numeric conversion, width fallback, accessibility)
  were addressed.
- The complete Swift suite passed 326 tests before the final native-driven
  layout and pressure additions. A later 329-test run passed the new tests but
  failed four unchanged `ProviderLoginProcessRunnerTests` with `readyTimedOut`.
- The final density/layout regression run
  `make swift-test SWIFT_TEST_FILTER=SystemDashboardPopoverTests` passed all 10
  tests. The subsequent gauge-only drawing adjustment was rebuilt and checked
  in the native screenshot; no claim of a final full-suite pass is made.
- `make package` and `make smoke` passed after the final gauge adjustment.
- Current-host native inspection confirmed a 360 x 680 panel with all six
  sections visible for the saved one-provider configuration, no overlapping
  gauges, no IP dump, RAM 36.6 GiB, swap 710.8 MiB, battery health 93%, and real
  disk/network rates. Two captures of the same open panel showed changing
  CPU/rates without window recreation. Settings opened correctly; local-IP
  on/off round-trip was checked and restored off, with public IP left off.
- Earlier plain `make test` passed on an intermediate revision. Final-candidate
  retries intermittently failed unchanged Rust analytics or Codex shell
  fixtures; `RUST_TEST_THREADS=1 make test` passed Rust/vendor tests but then
  encountered the Swift readiness timeouts above. These tests use short real
  process deadlines and are scheduling-sensitive; no production timeout or
  Rust source was changed to hide the failures.

Local verification logs and the final screenshot are outside the checkout in
`/Users/taejunoh/Developer/LFG/needlbar-dashboard-validation-aW4dTC/`
(`dashboard-final-native.png`). The exact locally running bundle is
`.worktrees/integration-main.d16P79/dist/Needlbar.app`. Expanded-IP disclosure,
an explicit final outside-click action, and native macOS 14 acceptance are not
claimed as completed by this inspection. Nothing here claims release readiness.

## v0.3 System Monitor — Approved Design and Implementation — 2026-09-02

The approved brainstorming direction is to make Needlbar a configurable Stats
replacement: CPU, RAM, disk, network, battery, and AI usage are combined in one
menu-bar item and popover. Menu-bar module visibility/order and AI display values
are configurable; the renderer automatically switches between expanded text and
compact icon/value layouts for available space and notched displays. System
metrics refresh every second, while provider refresh ownership remains
unchanged. Transfer speed is shown by default; local/public IP display is
optional, with public-IP lookup disabled unless explicitly enabled.

The approved design is in
`docs/superpowers/specs/2026-09-02-needlbar-v0.3-system-monitor-design.md`.
The ordered implementation plan is in
`docs/superpowers/plans/2026-09-02-needlbar-v0.3-system-monitor.md`.

### Task 1 — Models and persisted configuration

Task 1 is complete at commit `6d4a8a9`. It adds bounded system metric models,
canonical module ordering, AI display preferences, and UserDefaults-backed
monitor configuration with legacy provider visibility migration. Focused model
and configuration tests passed.

### Task 2 — Native collectors and supervised service

Task 2 is complete at commit `4b85745`. Swift now collects CPU, memory, disk,
network, and battery values through macOS APIs, publishes a one-second system
snapshot stream, isolates collector failures with stale/unavailable states, and
supports opt-in public-IP lookup at the pinned endpoint with a five-minute
cache and two-second timeout. Focused service tests, `swift build`, formatting,
and `git diff --check` passed.

The next continuation point is Task 3, `CombinedSnapshotStore`. Native macOS 14
Widget Gallery/App Group, WidgetKit, and notification-permission acceptance
remain deferred and unperformed.

### Task 3 — Combined snapshot store

Task 3 is complete at commit `dd6fae6`. The actor-backed
`CombinedSnapshotStore` merges provider and system streams independently,
preserves per-module system availability and provider failures, keeps a stable
provider order, and delivers the current combined value to new subscribers
with newest-only buffering. Focused merge tests passed.

The next continuation point is Task 4, the single adaptive menu-bar dashboard
item and deterministic compact/expanded renderer.

### Task 4 — Adaptive single-item menu bar dashboard

Task 4 is complete in the current worktree. The menu bar now owns one retained
status item, renders configured modules in expanded or compact layouts from an
injected width budget, and subscribes to the combined snapshot stream without
starting provider refreshes. Existing panel anchoring, outside-click/Escape
dismissal, settings, analytics, Claude/Codex browser login, and Cursor Spending
actions remain routed through their existing seams. Renderer and controller
tests passed.

### Task 5 — Complete six-section system dashboard popover

Task 5 is complete in the current worktree. The combined dashboard popover now
renders CPU, RAM, disk, network, battery, and AI sections from one immutable
snapshot. It always includes all six sections even when menu-bar visibility is
restricted, keeps network transfer rates visible by default, redacts public IP
unless explicitly enabled, formats provider values from their per-provider
preferences, and routes provider connection actions through the existing login
and Cursor Spending seams. Existing anchor, outside-click, and generation-safe
dismissal behavior is preserved. Focused dashboard, controller, and placement
tests passed.

The next continuation point is Task 6, module and AI display controls in
Settings. Native macOS 14 acceptance remains deferred and unperformed.

### Task 6 — Settings controls for system modules and AI display

Task 6 is complete in the current worktree. Settings now provides menu-bar
visibility toggles and drag-to-reorder controls for CPU, RAM, disk, network,
battery, and AI usage. Public-IP display is opt-in with the fixed endpoint and
privacy explanation. Claude, Codex, and Cursor each have independent
visibility, ordering, and display-metric preferences; changes persist through
`ModuleConfiguration` and update the existing configuration-change
notification without restarting the app. The complete dashboard continues to
show all six modules regardless of menu-bar visibility.

Verification recorded for the completed task:

- `make swift-test SWIFT_TEST_FILTER=SystemMonitorSettingsViewTests`: 4 tests passed.
- `make swift-test SWIFT_TEST_FILTER=ModuleConfigurationTests`: 5 tests passed.
- `make swift-test SWIFT_TEST_FILTER=MenuBarDashboardRendererTests`: 5 tests passed.
- `make swift-test SWIFT_TEST_FILTER=SystemDashboardPopoverTests`: 3 tests passed.
- Settings and dashboard targets compiled successfully; existing linker and
  unused-await warnings remain unchanged.

The next continuation point is Task 7, production lifecycle wiring,
documentation, and full verification. Native macOS 14 acceptance remains
deferred and unperformed.

### Task 7 — Production lifecycle, documentation, and verification

Task 7 is complete in the current worktree. Production now constructs one
`CombinedSnapshotStore` and one `SystemMetricsService` backed by the native
collector. AppDelegate forwards provider and system streams through separate
cancellation-aware tasks, starts system monitoring immediately after menu
observation, and keeps the acceptance build on its fixture-only construction
path. Termination cancels forwarding tasks and stops system monitoring after
notifications but before menu observation teardown. The architecture guide,
privacy policy, and README document the six modules, adaptive title, one-second
refresh, opt-in public-IP request/cache boundary, and deferred native macOS 14
acceptance.

Verification recorded for the completed task:

- `make swift-test`: 310 tests in 12 suites passed.
- `make acceptance-test`: 9 acceptance fixture tests passed with the acceptance
  compiler define.
- `git diff --check`: exit 0.

The next continuation point is final v0.3 review and release-readiness
verification. Native macOS 14 Widget Gallery/App Group and
notification-permission acceptance remains deferred and unperformed.

## v0.2.2 Public Release Preparation — 2026-09-01

Release preparation updates the host and widget to version 0.2.2 (build 2),
adds the reviewed future-download copy, and prepares validated ZIP and checksum
release artifacts. This records preparation only: no v0.2.2 tag, GitHub Release,
public download, or public notarization claim has been made. The signed tagless RC
run 33524771615 at `15c229f` and docs CI run 33526409582 remain pre-release
evidence only; a later exact green `main` commit is required for public release.

## v0.2.2 Public Release Record — 2026-09-01

Public release source commit: `299c1a9eec04573d16469d5b6a7b6aab8fb559e8`.
The tag-triggered public Release workflow [33554577457](https://github.com/taejunoh/needlbar/actions/runs/33554577457)
completed successfully and published [v0.2.2](https://github.com/taejunoh/needlbar/releases/tag/v0.2.2).
Fresh downloads from that GitHub Release contained exactly the ZIP and its
SHA-256 sidecar. The sidecar verified `Needlbar-macos-arm64.zip` with digest
`cf2b8b0eb1c3afeee34f9ee29efbedc8eec1c1d5d7844376864da370cf7cf086`.

Downloaded-asset verification passed: both executables were arm64; host and
widget bundle values were `0.2.2`/`2`; deep strict code-signature validation,
Developer ID authority presence, hardened-runtime presence, stapler validation,
Gatekeeper assessment, and smoke testing of the extracted downloaded app all
passed. Only safe command outcomes are recorded here; certificate, account,
team, token, keychain, and app-specific-password values are not recorded.

This public release is distinct from the signed tagless RC [33524771615](https://github.com/taejunoh/needlbar/actions/runs/33524771615).
The unresolved v0.2.1 native macOS 14 Widget Gallery/App Group and
notification-permission acceptance caveat remains unchanged; this record does
not claim native macOS 14 acceptance.

## Source of Truth

The active Needlbar work is governed by:

- `docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md` — approved architecture and product scope.
- `docs/superpowers/plans/2026-08-13-needlbar-v0.1.md` — ordered implementation plan.
- `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md` — approved authentication UX amendment.
- `docs/superpowers/plans/2026-08-25-provider-managed-browser-login.md` — ordered follow-up implementation plan.
- `docs/superpowers/specs/2026-08-29-needlbar-v0.2.0-local-json-export-design.md` — approved v0.2.0 local JSON export contract; implementation and acceptance are recorded below.
- `docs/superpowers/plans/2026-08-29-needlbar-v0.2.0-local-json-export.md` — approved v0.2.0 local JSON export implementation plan; all tasks are implemented and documented below.
- `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md` — user-approved v0.2.1 widgets/notifications written design; W1–W4, Notification Tasks N1–N4, and automated Integration Task 1 verification are complete on the code path, with native acceptance still pending.
- `docs/superpowers/plans/2026-08-31-needlbar-v0.2.1-widgets-notifications.md` — reviewed v0.2.1 implementation index: four widget tasks, four notification tasks, then combined acceptance.
- `docs/superpowers/specs/2026-09-01-needlbar-v0.2.2-local-repository-cost-analytics-design.md` — approved v0.2.2 local repository cost analytics design; its implementation plan is recorded below.
- `docs/superpowers/plans/2026-09-01-needlbar-v0.2.2-local-repository-cost-analytics.md` — approved v0.2.2 implementation plan; Tasks 1–6 and final verification are complete and recorded below.
- `docs/superpowers/specs/2026-09-02-needlbar-v0.3-system-monitor-design.md` — approved v0.3 system-monitor product, privacy, and layer-ownership contract.
- `docs/superpowers/plans/2026-09-02-needlbar-v0.3-system-monitor.md` — ordered v0.3 implementation plan; Tasks 1–7 are complete in this worktree.
- `docs/superpowers/plans/2026-08-31-needlbar-v0.2.1-widget.md` — W1–W4, including Swift-only day provenance, sanitized projection, and medium Overview presentation.
- `docs/superpowers/plans/2026-08-31-needlbar-v0.2.1-widget-packaging.md` — W3/W4 packaging and real-Team extension-first signing appendix; not an additional task.
- `docs/superpowers/plans/2026-08-31-needlbar-v0.2.1-notifications.md` — N1–N4, including fresh quota observation, durable policy, explicit permission, and lifecycle tests.
- `AGENTS.md` — continuation rules for Codex/agentic workers.

## v0.2.1 Native Acceptance Driver Task 3 — Lifecycle isolation — 2026-09-02

Task 3 is complete at commit `e000679`. The acceptance-only launch parser now
requires exactly `--acceptance-fixture <absolute-path>` beneath the configured
input root. Acceptance startup constructs only the shared snapshot, projection,
notification, inert Settings, and fixture-driver services; production retains
its existing provider, Rust, login, export, and analytics construction path.
The ordered acceptance lifecycle starts menu observation, notifications,
widget projection, and fixture driving, and stops them in reverse order through
the real service seams. No fixture parser or acceptance argument is exposed in
the normal build.

Verification recorded for the task:

- `make swift-test`: 278 tests in 12 suites passed.
- `make acceptance-test`: 9 acceptance fixture tests passed, including the
  lifecycle ordering and launch-boundary contracts.
- `git diff --check`: exit 0.

The next continuation point is Task 4, public/acceptance artifact boundary
scripts and isolation contracts. The real macOS 14 Widget Gallery/App Group,
WidgetKit, and notification-permission acceptance caveat remains open. No
push, tag, release, signing, or native acceptance run was performed.

## v0.2.1 Native Acceptance Driver Task 4 — Artifact boundary — 2026-09-02

Task 4 is complete at commit `c102a43`. Public packaging now rejects the
acceptance compiler define and scans the production bundle for fixture files or
the acceptance argument. The separate acceptance package path builds the host
with `NEEDLBAR_ACCEPTANCE_DRIVER`, embeds the unchanged extension, signs the
extension before the host with hardened runtime, verifies the host-only parser,
and emits no ZIP, checksum, notarization, or release artifact.

Verification recorded for the task:

- `make acceptance-build-test`: acceptance build isolation contract passed.
- `make package-test`, `make widget-extension-test`, and `make notarize-test`:
  all passed.
- `make test`: all Rust, vendor, Swift (278 tests in 12 suites), widget,
  packaging, and notarization contracts passed.
- `git diff --check`: exit 0.

The next continuation point is Task 5, the bounded native macOS 14 acceptance
harness. The real macOS 14 Widget Gallery/App Group, WidgetKit, and
notification-permission acceptance caveat remains open. No push, tag, release,
signing, or native acceptance run was performed.

## v0.2.1 Native Acceptance Driver Task 5 — Native harness — 2026-09-02

Task 5 is complete in the local worktree. `scripts/native-acceptance-run.sh`
accepts only the five bounded absolute-path options, keeps all resolved paths
under `/Users/taejunoh/Developer/LFG`, enforces the macOS 14 arm64 and disabled
network preflight, materializes only allowlisted sanitized case templates, and
caps parser/runtime evidence. Parser failures are recorded with stable codes;
the acceptance PID and generated runtime fixture are the only cleanup targets.
The checked-in parser, widget, and notification templates contain no provider
credentials, account identifiers, paths, prompts, responses, or raw payloads.

Verification recorded for the task:

- `make native-acceptance-harness-test`: native harness contract passed.
- `make acceptance-build-test`: acceptance build isolation contract passed.
- `make test`: all Rust, vendor, Swift (278 tests in 12 suites), widget,
  packaging, and notarization contracts passed.
- `git diff --check`: exit 0.

The next continuation point is Task 6, the maintainer-only macOS 14 execution
matrix. The real Widget Gallery/App Group, WidgetKit, and notification-
permission acceptance remains unperformed and is not claimed here. No push,
tag, release, signing, or native acceptance run was performed.

## v0.2.2 Design Checkpoint — 2026-09-01

The v0.2.2 local repository cost analytics design and implementation plan are finalized under the user's pre-approval of the recommended three-hour option. The bounded scope is a 30-day on-demand analysis using automatically observed local Git workspaces, local Git metadata, and best-effort local PR-number metadata. It has no network or provider-authentication activity, no database, and no raw path crossing the sanitization boundary. Execution is pre-approved as subagent-driven (recommended); push, tag, and release actions remain unauthorized.

Baseline verification from fresh HEAD `d1b13d1` passed with `make test` exit 0: Rust workspace tests passed (72), pinned vendor tests reported 1372 passed / 1 ignored, Swift reported 245 tests in 11 suites passed, and the widget-extension, package relink, and notarization shell contracts passed. Existing warnings remain (Swift unused-await/result diagnostics and macOS deployment-target linker warnings). No push, tag, or release was performed or authorized.

### v0.2.1 status preserved

The v0.2.1 native macOS 14 arm64 and remaining acceptance gates are still incomplete; this v0.2.2 checkpoint does not change that outcome.

## v0.2.2 Task 1 — Cached WorkspaceSession Report — 2026-09-01

Task 1 is complete. The pinned vendor now provides the additive cached-only
streaming/cross-file-dedup `WorkspaceSession` report, including explicit missing
timestamp/workspace coverage and provider-specific token/date/model-cost/dedup
parity. The implementation records bounded caps `512/8192/32` and exact
Unattributed overflow behavior without changing existing report consumers.

Vendor commits:

- `95e200c`, `dae421b`, `f9484d0`, `f763ea8` — additive WorkspaceSession report,
  tests, and vendor ledger updates.

Parent gitlink commits:

- `e7ba0a8`, `020f357`, `09b1368`, `cd9a60d` — corresponding superproject pin
  updates.

Verification recorded for the completed task:

- Focused WorkspaceSession suite: 10/10 passed.
- `cargo clippy -D warnings`: passed.
- Final isolated vendor suite: core 1376 passed / 1 ignored, plus 20 integration
  tests passed.
- Spec and quality reviews: approved.
- Worktree status: clean.

The next continuation point is Task 2 `needlbar-project-analytics` TDD. The
v0.2.1 native acceptance caveats remain unchanged. No push, tag, or release was
performed or authorized.

## v0.2.2 Task 2 — Local Repository Analytics Core — 2026-09-01

Task 2 is complete through final parent head `26f95d4` (implementation range
`3760e76` through `26f95d4`). The new `needlbar-project-analytics` crate accepts
only automatically observed workspaces and applies canonical symlink, `..`, and
worktree handling. Repository inspection uses closed, absolute `/usr/bin/git`
commands with strict NUL-delimited parsing and no remote/authentication path.

The bounded execution contract is enforced for 64 repositories, the 501-to-500
parsed-record sentinel, 200 returned rows, 1 MiB stdout, 8 KiB stderr, 2-second
per-process timeout, and 10-second total deadline. Process-group termination,
reaping, lifecycle reuse, and poisoned-runner behavior are covered. Correlation
uses the inclusive four-hour window, full-OID tie breaking, pending-window state,
and the local unambiguous PR marker rule. Canonical cost formatting, partial
coverage, Task 1 overflow propagation, and privacy/debug redaction are covered.

Verification recorded for the completed task:

- 35 tests passed.
- Formatting and `clippy -D warnings` passed.
- Prohibited-command/privacy scan and `git diff --check` passed.
- Spec and quality reviews: approved.
- Worktree status: clean.

The next continuation point is Task 3 sanitized analytics ABI. The v0.2.1
native acceptance caveats remain unchanged. No push, tag, or release was
performed or authorized.

## v0.2.2 Task 3 — Sanitized Analytics Bridge — 2026-09-01

Task 3 is complete. Commits `083a1fb`, `82deeae`, `f71e4ea`, and `90b23b7`
introduce the `needlbar_analytics_snapshot_json` bridge symbol and the dedicated
`needlbar.analytics.v1` envelope with exact 30-day/millisecond semantics, a
256 KiB bound, and a safe fallback. Cache, provider, and Git paths remain
isolated; pre-sanitization raw canary rows are redacted, with zero quota/auth
or Cursor mutation. Synthetic bridge fixtures are cleaned up after use.

Verification recorded for the completed task:

- Analytics contract: 8 tests passed.
- Redaction contract: 9 tests passed.
- FFI contract: 3 tests passed.
- Existing usage contract: 1 test passed.
- Existing quota contract: 6 tests passed.
- Formatting, clippy, `make rust`, and release-symbol (`nm`) checks passed.
- Spec and quality reviews: approved.
- Worktree status: clean.

The next continuation point is Task 4 Swift Core. The v0.2.1 native
acceptance caveats remain unchanged. No push, tag, or release was performed or
authorized.

## v0.2.2 Task 4 — Swift Core Analytics State — 2026-09-01

Task 4 is complete. Commits `7c926a9`, `2f42976`, and `17d512e` add the strict
analytics DTO/decoder with the actual allowlisted enums and enforce the 256 KiB
input bound, exact timestamp round trips, canonical number strings, ordering,
duplicate rejection, and control-character rejection. `RustBridge` owns each
analytics pointer exactly once; the repository is detached from production
sources, and the actor provides one in-flight operation with cancellation
isolation plus fresh, stale, and unavailable states.

Verification recorded for the completed task:

- `make swift-test` Analytics suites: 259 tests in 11 suites passed.
- Spec and quality reviews: approved.
- Worktree status: clean.

The next continuation point is Task 5 Analytics window. The v0.2.1 native
acceptance caveats remain unchanged. No push, tag, or release was performed or
authorized.

## v0.2.2 Task 5 — Analytics Window — 2026-09-01

Task 5 is complete. Commits `e931a54`, `cbd42f9`, `1f056b7`, and `d621c3d`
add one retained `760x520` resizable Analytics window, dismiss-before-open
Overview wiring, exactly-once initial/manual refresh behavior, truthful
unavailable/partial/coverage/Unattributed/about copy, lazy bounded `64x200`
layout, bounded formatting/reason IDs, and disclosure accessibility.

Verification recorded for the completed task:

- 275 Swift tests passed, including 15 Analytics tests.
- Build and `git diff --check` passed.
- Spec and quality reviews: approved.
- Worktree status: clean.

The next continuation point is Task 6 synthetic acceptance/docs/full matrix. The
v0.2.1 native acceptance caveats remain unchanged. No push, tag, or release was
performed or authorized.

## v0.2.2 Task 6 — Synthetic acceptance, documentation, and final matrix — 2026-09-01

Task 6 implementation and automated acceptance are complete on this worktree.
The fixture-only acceptance uses no provider, user, repository, remote, Git
checkout, network, credential, or authentication data. It loads
`Fixtures/analytics/workspace-session-fixture.json` and the escaped-NUL
`git-log-fixture.nul`, builds a `WorkspaceSessionReport`, feeds a queued fake
`GitRunner`, and exact-compares the deterministic sanitized golden payload.
The test proves valid/missing/non-repository workspaces, repository totals and
provider/model order, Task-1 overflow/timing/model partial counters, the
inclusive four-hour boundary, full-OID earliest tie break, pending and
no-eligible windows, `(#42)` only, multiple invalid PR markers, fake-only
read-only Git request kinds, and absence of every listed privacy canary from
JSON, Debug output, and errors.

The user-facing boundary is documented in `README.md`, `docs/architecture.md`,
and `docs/privacy.md`: Analytics is an unreleased manual **Analytics…** window
over 30 days of automatically observed local workspaces, with repository/model
totals, observed active AI-session time terminology, local four-hour commit
correlation, best-effort local PR metadata, and explicit partial/coverage
states. No remote forge/authentication/network/backend/database/export/widget/
notification behavior was added.

### Fresh verification evidence

- TDD RED: the new acceptance test failed with `No such file or directory` for
  the absent synthetic fixture (exit 101), then GREEN: the exact golden test
  passed (1/1).
- `cargo fmt --check`: exit 0.
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`:
  exit 0.
- `cargo test --workspace --features bridge-test-runtime`: exit 0; Needlbar
  Rust workspace tests 121 passed. The workspace excludes `vendor/tokscale-core`;
  its tests are counted only under the dedicated vendor shell command below.
- `bash scripts/tests/vendor-tokscale-test.sh`: exit 0; vendor core 1,376
  passed/1 ignored plus 20 integration tests passed.
- `make test` after sourcing `/Users/taejunoh/.cargo/env`: exit 0; Swift 275
  tests in 12 suites passed and widget/package/notarization shell contracts
  passed. An initial unsourced `make test` was an environment-only exit 2
  (`cargo: No such file or directory`) and was not treated as product failure.
- `make package`: exit 0; local arm64 ad-hoc package assembled and relinked.
- `make smoke`: exit 0; bundle metadata, architecture, signature, launch, and
  cleanup smoke checks passed.
- `git diff --check`: exit 0.

Known warnings remain pre-existing: Swift unused-await/result diagnostics,
macOS deployment-target linker warnings from the local macOS 26/Xcode 26
toolchain, and benign lifecycle-test `kill: No such process` diagnostics. This
matrix does not claim native signed macOS 14 arm64, Widget Gallery/App Group,
or live visual acceptance.

Task 6 files are committed as `docs: record local repository analytics
acceptance` at the handoff commit recorded by `git rev-parse HEAD`; no push,
tag, release, notarization, credentialed provider action, or remote Git action
was performed or authorized.

The independent final whole-branch review and native current-host check are
recorded in the final completion handoff below. The outstanding v0.2.1
macOS 14/installed-widget and related native acceptance caveats remain open
and are not satisfied by this synthetic local matrix.

## v0.2.2 Final Completion Handoff — 2026-09-01

An independent whole-branch review is **APPROVED**. Final review findings were
resolved in the exact-instant-window fixes (`926a249` parent / `ecfb694` vendor),
Git-read coverage fix (`c1be106`), payload and cost bounds (`2ab598c`), production
ABI casing fix (`65d83c0`), and golden update (`0572bd1`). The pinned vendor
revision is `ecfb694`.

Fresh final verification at HEAD `0572bd1` passed: `cargo fmt --check` exit 0;
workspace all-targets/all-features `clippy -D warnings` exit 0; `make test` exit 0
with all Needlbar Rust suites passing (including acceptance/privacy), vendor
1,396 passed / 1 ignored (1,376 core plus 20 integrations), Swift 277 tests in
12 suites, and the widget/package/notarization shell contracts passing;
`make package` exit 0; `make smoke` exit 0; and `git diff --check` exit 0. The
parent worktree and vendor submodule are clean.

On the current macOS 26 host, the exact fresh `dist` app visually showed the
Overview **Analytics…** button, a separate `760x520` window, initial and manual
Refresh transitions from Loading to Ready, and safe partial
`gitUnavailable`/Unattributed states rather than a fatal error after the ABI
fix. A generic `needlbar://overview` initially opened the stale
`runtime/latest` registration because duplicate bundle/URL handlers were
present; acceptance was retargeted to the exact fresh package, and the stale
screenshot is invalid evidence.

The v0.2.2 implementation is complete. Native signed macOS 14 arm64,
Widget Gallery, and live App Group acceptance were not established on this
macOS 26 host. No push, tag, release, notarization, or credentialed provider
action was performed or authorized. The next continuation is optional local
integration/release only with explicit user authorization, not additional
feature implementation.

## v0.2.2 Local Integration Completion — 2026-09-01

`main` was fast-forwarded locally from `d1b13d1` to `28af5dd`, incorporating
the former `codex/v022-project-cost-analytics` branch. The former v0.2.2
worktree and branch were cleaned after the merged-result `make test` passed:
all Needlbar Rust suites passed, vendor reported 1,396 passed / 1 ignored,
Swift reported 277 tests in 12 suites, and the widget/package/notarization
shell contracts passed.

The initial `git submodule update --init --recursive` from the fresh main
worktree failed because pinned vendor revision `ecfb694` was local-only and was
not advertised by `https://github.com/Nanako0129/tokscale-core.git`. The main
worktree obtained that exact commit through a local fetch from the former
feature worktree, after which the merged-result tests passed.

With explicit user authorization, `taejunoh/tokscale-core` was created as a
fork and the exact pinned commit was published on branch
`needlbar-v0.2.2-workspace-session-report`. The superproject submodule URL now
uses that authorized fork so a fresh checkout can retrieve `ecfb694`. A clean
`--no-local` clone then initialized the public submodule at that exact SHA and
passed `make test`: all Needlbar Rust suites passed, vendor reported 1,396
passed / 1 ignored, Swift reported 277 tests in 12 suites, and the
widget/package/notarization shell contracts passed. The known macOS 26.5 object
version versus macOS 14.0 link-target warnings remained non-blocking.

The vendor-publication blocker is resolved. The next continuation is the
separately authorized superproject push and CI confirmation, followed by a
signed RC only with explicit authorization. No tag, release, notarization, or
credentialed provider action was performed.

## v0.2.2 Push and CI Verification — 2026-09-01

The initial CI run [33515294154](https://github.com/taejunoh/needlbar/actions/runs/33515294154)
failed because `analytics_contract` imported bridge runtime symbols without the
required feature. Commit `c8972d5` gates those imports behind that feature.

A local high-parallel test exposed a process-fixture timing flake. Commit
`193dd8a` serializes only the test process fixtures; production behavior is
unchanged.

Rerun [33517179792](https://github.com/taejunoh/needlbar/actions/runs/33517179792)
passed the Rust tests, lints, and vendor suite, but the Xcode 16.2 full
`make test` failed on an actor-isolated `Optional.map` call. Commit `ad02662`
uses a direct actor-isolated call. Final code run
[33519496485](https://github.com/taejunoh/needlbar/actions/runs/33519496485)
succeeded through all CI stages.

A fresh local full `make test` at `ad02662` passed: all Needlbar Rust suites,
vendor 1,396 passed / 1 ignored, Swift 277 tests in 12 suites, and the
widget/package/notarization contracts. The vendor-publication blocker is
resolved. No tag or public release was performed at this stage. The next
continuation is the signed tagless RC validation recorded below.

## v0.2.2 Signed Tagless RC Validation — 2026-09-01

Remote and local `main` are at HEAD
`15c229f19a8c74417e11092873b947e8ca368e7d`. Release workflow dispatch run
[33524771615](https://github.com/taejunoh/needlbar/actions/runs/33524771615)
succeeded. Its validation stages passed: **Verify complete project**,
**Package arm64 app**, **Smoke-test packaged app**,
**Sign/notarize/staple/validate**, and **Upload**; **Publish** was skipped.

The `Needlbar-macos-arm64-notarized` artifact was 5,930,415 bytes through the
Actions API and expires at `2026-11-30T15:17:00Z`. The downloaded inner archive
is retained at
`/Users/taejunoh/Developer/LFG/needlbar-release-artifacts/33524771615/Needlbar-macos-arm64.zip`;
it is 5,949,772 bytes with SHA-256
`dc2b624922935338b6d9ce7eb6bb57c4736bbd590c3287519cb6844ee732ff15`.

Independent host checks on macOS 26.6.2 arm64 passed: deep strict
`codesign` verification, Developer ID identity presence, hardened-runtime
presence, stapler validation, Gatekeeper assessment, and extracted-bundle
smoke launch. Identity, team, and account details are intentionally not
recorded.

Repository tag count is 0 and public release count is 0. This validates a
tagless notarized RC artifact only; it does not claim exact macOS 14 native
acceptance, Widget Gallery acceptance, or App Group acceptance. No tag or
public release was created. The next action is a separately authorized
tag/public release if desired, while preserving the outstanding v0.2.1 exact
macOS 14 Widget Gallery/App Group acceptance caveat.

## v0.2.1 Widgets and Notifications — Design Continuation

The user-approved v0.2.1 scope and reviewed implementation plans are limited to:

- One medium Overview-first macOS widget, centered on quota/reset information with tokens and cost as secondary values. Cursor contributes usage only; its quota remains unavailable. Clicking the widget opens Needlbar.
- Alerts default to off and require explicit permission when enabled. While the main app is running, fresh Claude/Codex readings crossing downward thresholds of 20%/10% may alert once per cycle stage. The first fresh reading establishes a baseline; one jump to at most 10% emits only the 10% alert. Restart deduplication is durable, and reset-date drift alone does not re-arm alerts.
- The main app remains the only provider-fetching process and publishes a sanitized local widget projection. The projection preserves last-good/stale state, timestamps, and the last value at app quit; it does not expose credentials or raw provider data.

**Planning-only checkpoint, before W1 implementation:**

Written design approval and implementation-plan review are complete. The current machine is macOS 26.6.2 with Xcode 26.6; actual signed macOS 14 arm64 Widget Gallery/App Group acceptance must be recorded separately before v0.2.1 completion. The known historical green CI result for baseline main commit `1ba620b` is [run 33284608349](https://github.com/taejunoh/needlbar/actions/runs/33284608349), recorded from the previous turn. Docs-only verification: `git diff --check`, Markdown fence validation, and Bash code-block syntax checks passed. `make test` and native compilation/signing were not run because product/build/test sources were unchanged; no new CI run was made. This planning checkpoint predates the W1–W4, N1–N4, and Integration Task 1 verification records below.

Notification Task 1 complete: ProviderSnapshotStore now provides a coalesced quota-alert wake-up and authoritative per-provider quota revisions.

Notification Task 2 complete: allowlisted per-window threshold policy and private durable reservation ledger are covered by synthetic tests; next: Notification Task 3 permission/lifecycle service.

Notification Task 3 complete: serialized opt-in authorization, admission revalidation, durable reservation, and immediate no-retry submission are implemented; next: Notification Task 4 Settings and lifecycle wiring.

Notification Task 4 complete: Settings and main-app lifecycle own the explicit quota-alert preference; notifications implementation awaits combined v0.2.1 acceptance.

## v0.2.1 Widgets and Notifications — Integration Task 1 Automated Verification — 2026-08-31

W1–W4 and Notification Tasks N1–N4 are implemented on source HEAD `9de686e`
(`fix: preserve widget freshness and deduplicate alerts`). The controller's prescribed
final pipeline ran on the frozen five-file tree in session `4025` and exited 0; the exact
command/output record is retained in the ignored
`.superpowers/sdd/2026-08-31-needlbar-v0.2.1-widgets-notifications/final-fix-controller-gates.log`.
No gate was rerun during this documentation bookkeeping pass.

Recorded automated command outcomes:

- `source /Users/taejunoh/.cargo/env && make test` — exit 0; Rust and package suites passed,
  pinned `tokscale-core` reported 1372 passed/0 failed/1 ignored, and Swift reported 213
  tests in 9 suites passed. The widget-extension, package relink, and notarization shell
  contracts also passed.
- `cargo fmt --check` — exit 0.
- `cargo clippy --workspace --all-targets --all-features -- -D warnings` — exit 0.
- `make package` — exit 0; local arm64/macOS 14 package produced.
- `make smoke` — exit 0; `Needlbar app-bundle smoke passed`.
- `./scripts/tests/package-app-tests.sh` — exit 0; `package-app relink regression passed`.
- `./scripts/tests/notarize-app-tests.sh` — exit 0; `notarize-app shell contracts passed`.

Read-only checks on the produced `dist/Needlbar.app` found arm64 host and extension
executables, `14.0` minimum-system metadata, one `com.apple.widgetkit-extension`, and matching
synthetic `TESTTEAMID.com.taejunoh.needlbar` host/extension App Group metadata. The local
ad-hoc signature verifies with `codesign --verify --deep --strict`; the extension declares
App Sandbox and no network/Keychain entitlement. `swift package dump-package` reports external
`dependencies: []` and a dependency-free `NeedlbarWidgetSupport` target. The checked-in widget
source scan, extension entitlement scan, and extension `otool -L`/`nm -u` boundary checks found
no `NeedlbarCore`, `CNeedlbar`, Rust, provider, credential, Keychain, URLSession, or network
dependency. These are structural/ad-hoc checks only and do not establish a real Team ID,
provisioned entitlements, Widget Gallery discovery, or App Group runtime behavior.

Actual signed macOS 14 arm64 Widget Gallery/App Group/deep-link/quit/reset/midnight acceptance
is unavailable on the current macOS 26.6.2/Xcode 26.6 host. Current-host notification
authorization/enable-disable testing is possible. Live-data launch is now approved and underway,
but Settings/permission UI access remains pending as recorded in the runtime continuation below.
These checks remain the next action;
v0.2.1 is implemented but not accepted. Final whole-branch review and scoped final-fix re-review accepted the code,
specification, and quality for `9de686e`; Integration Task 1 overall remains incomplete until
the external native gates are satisfied. No new CI run was made, and no tag or release action is
authorized.

## v0.2.1 Widgets and Notifications — Current macOS 26 Native Preflight — 2026-08-31

This is the historical pre-launch checkpoint; the runtime continuation below supersedes its
launch-consent and registration pending states.

The controller completed local signing and a native preflight on the current macOS 26.6.2
arm64 host without changing product source. No Needlbar process was running. An existing local Developer ID identity was valid;
the original `dist/Needlbar.app` remains unchanged and was copied to the isolated candidate
`.superpowers/native-validation/macos26.YDT1Bc/Needlbar.app` without rebuilding. The candidate
was based on checkout HEAD `df51dbd` (docs-only after source `9de686e`).

- Candidate `Info.plist` and copied entitlements were resolved to
  `3BMF4LM6TM.com.taejunoh.needlbar`. The extension was signed before the host with
  `--force --options runtime --timestamp=none --sign 4C6503D0A78A9F51C86CC7C9683115E74A4902A7`;
  `codesign --verify --deep --strict --verbose=2` exited 0.
- Both binaries are arm64, carry the real Developer ID TeamIdentifier and hardened-runtime
  flag. Host entitlements are unsandboxed with only the App Group; the widget is sandboxed with
  the same group and has no network or Keychain entitlement.
- This is local signing only: no trusted timestamp, notarization/stapling, Gatekeeper
  acceptance, upload, Apple portal mutation, credential export/import, tag, release, or push was
  performed.
- `pluginkit -a` for the exact candidate extension exited 0, but
  `pluginkit -m -Av -i com.taejunoh.needlbar.widget` listed only the old `dist` extension; no
  candidate-discovery claim is made.
- Native launch was not performed. Read-only review found no preview/fixture-only app path, and
  production launch always starts normal provider refresh. The controller is awaiting approval
  for real-data launch under the synthetic-only acceptance constraint, or a separately scoped
  synthetic harness. Widget Gallery/show, App Group runtime, widget data/deep-link behavior,
  quit/reset/midnight behavior, and notifications remain unverified. Current-host notification
  permission testing can proceed after launch approval; only macOS 14-specific compatibility
  remains impossible to establish on this host.

The detailed local evidence is retained in
`.superpowers/native-validation/macos26.YDT1Bc/preflight.md`. This preflight does not change the
macOS 14 minimum target or authorize any tag/release action.

## v0.2.1 Widgets and Notifications — macOS 26 Runtime Continuation — 2026-08-31

Following explicit approval for a live connected-data normal-app launch, the signed candidate was
started with `open -n` at `16:17:26 EDT` (PID `72814`). Initial candidate
`codesign --verify --deep --strict --verbose=2` exited 0. The real App Group container
`3BMF4LM6TM.com.taejunoh.needlbar` was auto-created; `NeedlbarWidgetProjection.json` appeared with mode `0600`,
size `815` bytes, and mtime `16:17:43`. At `16:22`, `pluginkit` listed the signed candidate
extension only.

A later controller `stat` observed mode `0600`, size `817` bytes, and mtime `16:22:33 EDT`,
confirming a subsequent host publication during the running session. This is not evidence that
WidgetKit rendered or read back the projection.

- A read-only responsiveness sample recorded 2,588 samples over 3 seconds. The main thread was
  in `NSApplication.run`/normal `mach_msg` idle with CPU at 0% range; no hang was observed.
- `open -a` for the candidate with `needlbar://overview` exited 0, but the UI was not observable,
  so no deep-link visual pass is claimed. A separate old Task 5 fresh-app process (PID `72970`,
  started `16:17:56`) appeared during those attempts; its exact-path start was checked and it was
  terminated with `SIGTERM`, while candidate PID `72814` remained alive.
- Registration cleanup was narrow: `lsregister -u` targeted only the worktree
  `dist/Needlbar.app`, then `lsregister -f` targeted the exact candidate. No files were deleted.
  Existing desktop widgets were observed enabled. System Settings did not list Needlbar under
  notifications.
- Orca could not expose Needlbar's status-item popover despite granted UI-automation access;
  System Settings was accessible, while Needlbar background-state reads timed out. No persistent
  Settings surface, alert toggle, OS permission change, or authorization request was visually
  verified at that initial checkpoint. The user subsequently opened Settings. The controller
  observed the signed candidate's persistent `Needlbar Settings` window using native UI
  automation and scrolled to Notifications: `Quota threshold alerts` was off, with
  `Off. Enable to request permission.` visible at that checkpoint.

After action-time approval, the controller enabled the quota-alert switch. The first request
returned an error (`didGrant: 0 hasError: 1` in the bounded native log), and the app showed
`Notifications unavailable in macOS settings.` The exact error was not retained by the client.
The user then confirmed personally granting OS permission; System Settings showed Needlbar's
allow-notifications switch on. Re-enabling the already-approved app option re-read authorization
and visibly changed `Quota threshold alerts` to on with
`Alerts are enabled for fresh Claude and Codex quota readings.` No OS permission switch was
changed by the controller, no permission database was reset, and no product source was changed.
This verifies current-host opt-in activation after permission was granted, not notification
delivery, revocation, restart de-duplication, or macOS 14 behavior.

At approximately `16:51 EDT`, the user opened Widget Gallery and the controller inspected its
native UI without requiring a chat reply while the modal editor was open. Searching `Needlbar`
produced only `All Widgets` with an empty previews collection, confirmed in a second UI read.
The signed candidate still appeared as the sole entry in `pluginkit -m -ADv`, so plugin
registration alone has not established WidgetKit discovery. The empty-result screenshot is
retained locally at `.superpowers/native-validation/macos26.YDT1Bc/gallery-needlbar-empty.jpeg`.
The editor was closed afterward so the user could return to chat; no widget was added and no
existing desktop widget was changed. Gallery discovery failed this native check.

Bounded native logs subsequently narrowed the failure to extension startup: at `16:49:50`,
macOS launched the exact candidate, initialized its sandbox, and entered `WidgetBundle.main`,
but the process then exited voluntarily before replying to the descriptor request. `chronod`
reported an invalidated connection (`NSCocoaErrorDomain 4099`). An earlier `16:21` containing-bundle
registration warning is therefore not sufficient to explain the current failure. Binary
comparison found that Needlbar enters its synthesized Swift `main` and lacks the Foundation
`_NSExtensionMain` entry used by three working WidgetKit extensions. A narrowly scoped linker
entrypoint regression test first failed with the missing linker argument, then passed after adding
`-Xlinker -e -Xlinker _NSExtensionMain` to the extension build. The actual rebuilt binary imports
Foundation's `_NSExtensionMain`; its `LC_MAIN` entry (`211172`) points to that symbol's trampoline.
The scoped read-only review accepted the two-script change without findings. No widget source,
plist template, data schema, provider, or permission behavior changed.

The controller preserved the original signed and ad-hoc bundles, copied the signed candidate to
`.superpowers/native-validation/entrypoint.nW5gTb/Needlbar.app`, embedded the rebuilt extension,
resolved its group to the existing real Team ID, and signed the extension before the host with
the same local runtime/no-timestamp signing recipe. Strict nested verification exited 0.
After checking the old candidate's exact process path, only PID `72814` was terminated; its
registration was narrowly replaced with the new candidate. The new host started at `17:01:14`
as PID `80226`, with one registered extension. No files or system caches were deleted.
At `17:01:14–15`, `chronod` received the `NeedlbarOverview` medium-widget descriptor and the
extension successfully completed its placeholder request.

At `17:02:54`, the controller opened Gallery through the existing widget context menu and searched
`Needlbar`. Both the native accessibility tree and screenshot showed the Needlbar category and
one medium `Overview` preview with rendered provider rows. The screenshot is retained locally at
`.superpowers/native-validation/entrypoint.nW5gTb/gallery-needlbar-visible.jpeg`. The controller
clicked Done and verified the editor was closed. No widget was added or removed. This passes
current-host Gallery discovery and preview rendering, but is not installed-widget acceptance.

Fresh verification on the two-script fix: `source /Users/taejunoh/.cargo/env && make test` exited 0
(controller session `3404`); Rust/vendor, 213 Swift tests in 9 suites, widget-extension, package
relink, and notarization shell contracts passed. Output is retained at
`.superpowers/native-validation/entrypoint.nW5gTb/make-test.log`. The host test link still reports
newer-macOS object-file deployment warnings (26.5 objects against the 14.0 target); this successful
current-host run does not establish macOS 14 compatibility. The original `dist` and earlier signed
candidate remain preserved; no commit, push, release upload, or native cache reset was performed.

The user then reproduced a separate native popover problem: clicking an ordinary other-app view
or the desktop did not dismiss the `.transient` popover. The existing code had no close veto or
re-show path, so a narrowly scoped global left/right/other mouse-down fallback was added without
changing the popover edge, activation policy, panel type, or SwiftUI layout. TDD first failed on
the missing monitor seam; a review wave then added RED cases for a hidden popover incorrectly
installing a monitor and a queued old-presentation callback closing a newly presented popover.
The final implementation installs only after a successful show, guards delayed callbacks with a
monotonic presentation generation, and cancels on replacement, close, and both application
termination paths. The final scoped review accepted the implementation with no Critical or
Important findings; the public test seam remains a nonblocking Minor in this executable target.

Focused `MenuBarControllerTests` passed 19 tests in one suite, full Swift verification passed 221
tests in 9 suites, and a fresh `source /Users/taejunoh/.cargo/env && make test` exited 0 with all
Rust/vendor, Swift, widget-extension, package, and notarization contracts passing. `make package`
also exited 0. The candidate `.superpowers/native-validation/dismiss.Pyfdbi/Needlbar.app` was
resolved to the existing real Team ID, signed extension-first with the existing local
runtime/no-timestamp recipe, and passed strict nested verification. After exact-path validation,
only the prior candidate PID `80226` was terminated and its registration was narrowly replaced.
The new candidate started as PID `20555` at `17:31:44 EDT`. The user then confirmed that clicking
outside the displayed popover closes it. Popover positioning remains separately unverified and
unchanged; no tag, push, release upload, portal change, or cache reset occurred.

Installed-widget rendering/readback, App Group lifecycle behavior, deep-link visual behavior,
quit/reset/midnight behavior, remaining notification-permission cases, and threshold-crossing acceptance remain
unverified. No artificial usage, login change, provider record overwrite, notarization/upload,
portal mutation, tag, or push occurred. The current-host notification checks are no longer blocked
by launch consent, Settings access, or initial authorization; macOS 14 arm64
compatibility remains a separate final gate.

## v0.2.1 Final Review Fix Wave — 2026-08-31

The final whole-branch review found two important code defects and this single scoped fix wave
addresses them without changing the shared quota domain, provider/bridge/export contracts, or
widget schema. Projection dates now use a paired fractional RFC3339 codec while preserving
legacy whole-second decoding; notification observation construction omits every row for an
ambiguous duplicated allowlisted window ID rather than selecting one arbitrarily.

Focused RED/GREEN evidence from this worktree:

- RED: `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=WidgetProjectionTests` exited 2 with 28 tests in 2 suites and 3 expected issues: default ISO-8601 encoding lost fractional `lastSuccessfulAt` and `resetsAt`, making the just-below-900-second reading stale.
- GREEN: the same `WidgetProjectionTests` command exited 0 with 28 tests in 2 suites. The fixture uses non-millisecond successful/reset dates, preserves both through encode/decode, is fresh just below 900 seconds, and stale exactly at 900 seconds. Existing whole-second document fixtures continue to decode.
- RED: `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=QuotaNotificationServiceTests` exited 2 with 14 tests in 1 suite and 3 expected issues: an initial duplicate `claude.session` 80%/20% sample submitted a false alert and contaminated the later unique baseline/crossing assertions.
- GREEN: the same `QuotaNotificationServiceTests` command exited 0 with 14 tests in 1 suite. Both duplicate orders submit nothing; a later unique 80% sample baselines and its later unique 20% sample submits one alert. The existing distinct-window independence fixture remains green.
- `bash scripts/build-widget-extension.sh && bash scripts/tests/widget-extension-tests.sh` — exit 0; the native extension built with the synthetic App Group identity and the fake build/metadata contract passed.
- Controller full pipeline, session `4025`, on the frozen five-file fix tree — actual exit 0: `source /Users/taejunoh/.cargo/env && make test` passed with 213 Swift tests in 9 suites plus Rust/vendor and all widget/package/notarization contracts; `cargo fmt --check`, strict `cargo clippy --workspace --all-targets --all-features -- -D warnings`, `make package`, `make smoke`, `./scripts/tests/package-app-tests.sh`, and `./scripts/tests/notarize-app-tests.sh` also passed. The exact output is retained in the ignored `final-fix-controller-gates.log`.

The controller-owned full integration pipeline has completed. Final whole-branch review and
scoped final-fix re-review accepted the code, specification, and quality with no new findings.
The external signed macOS 14 arm64 Widget Gallery/App Group and native notification-permission
acceptance gates remain separate and unsatisfied. The final review's Minor coverage groups are
nonblocking future test debt for fresh-checkout continuation: decoder/reader failure fixtures;
container failure; package argv/sandbox assertions; usage-only no-wake; throwing-writer/0700;
uncertain-save/initial-freshness; and permission-after-start. No production or test source
changes are requested by these debt items.

## Widget W4 Verification — 2026-08-31

W4 host packaging, extension embedding, signing, smoke contracts, and release-path signing assertions are implemented. The host remains unsandboxed with only the TeamID-prefixed App Group; the extension is sandboxed with the same group. The automated package contract embeds exactly one `.appex` and records extension signing before host signing. The Developer ID notarization path retains the six existing secret inputs, temporary-keychain import/cleanup, hardened runtime, timestamp, deep verification, stapling, Gatekeeper, and candidate ZIP replacement semantics while resolving the production group from `APPLE_TEAM_ID` and signing the extension before the host without `--deep` signing.

Verification evidence:

- RED: `bash scripts/tests/package-app-tests.sh` and `bash scripts/tests/notarize-app-tests.sh` exited 1 on the expected missing `Resources/NeedlbarHostWidget.entitlements`; `bash scripts/tests/smoke-app-tests.sh` exited 1 because no packaged `dist/Needlbar.app` existed yet.
- GREEN: `bash scripts/tests/widget-extension-tests.sh` exited 0 with `widget extension build/metadata contract passed`; `bash scripts/tests/package-app-tests.sh` exited 0 with `package-app relink regression passed`; `bash scripts/tests/notarize-app-tests.sh` exited 0 with `notarize-app shell contracts passed`.
- GREEN after `source /Users/taejunoh/.cargo/env && make package`: `bash scripts/tests/smoke-app-tests.sh` exited 0 with `smoke-app cleanup regressions passed`; `make package` exited 0; and `make smoke` exited 0 with `Needlbar app-bundle smoke passed`.
- Full project verification `source /Users/taejunoh/.cargo/env && make test` exited 0: Rust workspace tests passed; pinned `tokscale-core` reported 1372 passed, 0 failed, 1 ignored; Swift reported 187 tests in 5 suites passed; widget-extension, package relink, and notarization shell contracts passed.
- `git diff --check` and Bash syntax checks for all six changed scripts exited 0.

The package and smoke checks are structural/ad-hoc evidence only. This macOS 26.6.2/Xcode 26.6 environment does not establish provisioned entitlements, Widget Gallery discovery, App Group access, or signed macOS 14 arm64 acceptance. Those remain Integration Task 1 and do not block N1 after the automated W4 checks pass. No credentialed notarization, Apple portal action, tag, or release action was performed.

## What Is Already Implemented

Task 1 bootstrap files exist on `main`, including:

- SwiftPM package with `Needlbar`, `NeedlbarApp`, `NeedlbarCore`, and `CNeedlbar` targets.
- Rust workspace with `needlbar-bridge`, `needlbar-source-sync`, and `needlbar-quota` crates.
- Pinned `vendor/tokscale-core` submodule.
- Root `Makefile` and `scripts/build-rust.sh`.
- Tracked `Cargo.lock` for deterministic Rust dependency resolution.
- Minimal Swift and Rust bootstrap sources/tests.
- GitHub Actions CI on `macos-14` running `make test`.

Task 1 continuation commits on `main`:

- `dea34b2` — select Xcode 16.2 for Swift tests on CI.
- `a7ca67a` — track `Cargo.lock`.

Task 2 implementation commits on `main`:

- `29a0b71` — add the versioned Rust/Swift bridge contract.
- `c46c4f8` — format the bridge ABI contract with scoped `rustfmt`.

Task 3 implementation commit on `main`:

- `37846c3` — aggregate Claude and Codex usage with `tokscale-core`.

Task 4 implementation commits on `main`:

- `066e985` — hydrate Cursor usage before aggregation.
- `96e49e7` — harden Cursor cache synchronization and validate exports.
- `e8f0953` — close Cursor cache path races and support v1 CSV compatibility.
- `1cef31c` — separate mechanical source-sync Clippy hygiene.

Task 5 implementation commits on `main`:

- `cf25a5f` — add the shared quota domain and Claude adapter.
- `7526171` — harden Claude quota/auth/HTTP boundaries.

Task 6 implementation commits on `main`:

- `c77ed8d` — add the Codex quota adapter with RPC fallback.
- `86f374f` — harden Codex RPC fallback transport and cleanup.
- `37b8aaf` — validate Codex RPC request and response contracts.

Task 7 implementation commits on `main`:

- `ecf6d32` — add Cursor quota and explicit connection flow.
- `20e02b6` — harden Cursor session import and source sync.

Task 8 implementation commit on `main`:

- `8fd1e21` — expose partial quota results through the bridge.

Task 9 implementation commit on `main`:

- `f078ff7` — add Swift bridge models and stale state.

## Current CI State

Task 1 is verified green.

- Local `make test` passed on Swift 6.3.3 and Rust 1.97.1.
- `Cargo.lock` is tracked for deterministic Rust dependency resolution.
- GitHub Actions run [31837456920](https://github.com/taejunoh/needlbar/actions/runs/31837456920) succeeded in 3m49s.
- CI retains `runs-on: macos-14` and deliberately selects `/Applications/Xcode_16.2.app` before running tests.
- `Package.swift` remains on Swift tools version 6.0 with a macOS 14 deployment target.
- No approved-baseline deviation was made.

## v0.2.0 Local JSON Export — Task 5 Acceptance and Completion

The v0.2.0 implementation plan was completed only after the acceptance evidence for all five numbered tasks was recorded. The pre-integration implementation head `2eafbdb` (`fix: expose pending snapshot cleanup safely`) included sanitized `cleanupPending` and the `requiresAuthentication` regression. Task 5 adds the public documentation and acceptance record without changing implementation code. The v0.1 release authorization gate remains separate and unchanged.

Final focused and full acceptance on pre-integration head `2eafbdb` passed:

- `swift test --filter SnapshotFileWriterTests` — exit 0.
- `swift test --filter SnapshotExporterTests` — exit 0.
- `source /Users/taejunoh/.cargo/env && make test` — exit 0; the Rust workspace, pinned `tokscale-core` suite, Swift tests, package relink regression, and notarization shell contracts passed.

Release-like checks run at pre-integration head `2eafbdb` also passed:

- `swift build -c release` — exit 0.
- `make package` — exit 0; the local arm64/macOS 14 bundle was produced.
- `make smoke` — exit 0; bundle metadata, signature, executable identity, launch, and bounded cleanup passed.

The bounded live Settings/save-panel export and cancellation acceptance is explicitly evidence from the initial implementation head `718748e`; it remains the recorded live UI run and was not rerun on `2eafbdb` or the final feature commit. No Foundation `JSONSerialization` re-encode byte-equality claim is made; the exact sorted-key/golden behavior remains covered by `SnapshotExporter` automation.

Bounded live UI acceptance completed through the accessibility fallback: the exact packaged app from this worktree was running, Settings opened from its status-item popover, and the Data Export button opened the production save panel. The panel default was `Needlbar-Snapshot-20260829T233601572Z`; selecting the harmless LFG destination produced `/Users/taejunoh/Developer/LFG/Needlbar-Snapshot-20260829T233601572Z.json` (with the OS-appended `.json` extension). `stat` reported mode `600` and size `3055`; `file` reported JSON data; the final byte was `0a`. Parsed data reported `schemaVersion: 1`, provider order `claude,codex,cursor`, `cursor.quota.data == null`, and an empty forbidden-key intersection for `title`, `message`, `path`, `accountId`, `prompt`, `response`, `sourceCode`, `cookie`, and `credential`. Object keys followed the `SnapshotExporter`/`JSONEncoder` sorted-key contract; exact full golden behavior remains covered by automation. No Foundation `JSONSerialization` re-encode byte-equality claim is made because its numeric-key ordering differs for `last7Days` and `last30Days`. A second export click opened the panel again; Cancel returned to Settings and the only matching file remained the first saved file, proving cancellation created nothing. No credentials, account identifiers, prompts, responses, cookies, or source content were inspected.

No Rust/C/provider/auth/network changes, extra export entry points, raw error/title fields, tag, or release action were introduced. No tag or public GitHub Release was created; until explicit authorization is given, no tag or release action is authorized.

Final whole-branch review and the scoped fix re-review were clean with `Ready to merge: Yes`; PR #3 integration and green main CI are recorded below.

## v0.2.0 Integration Completion — 2026-08-30

Pull request [#3](https://github.com/taejunoh/needlbar/pull/3) merged at `2026-08-30T00:42:48Z` via merge commit `181e41d07d9c2dfe41edb37d9257e697dd5840d7`. The local `main` worktree was fast-forwarded to that merge commit before this documentation update. The final feature commit `6f39ec6917db92a6566b545aab0eef80cfd4540f` (`fix: canonicalize snapshot JSON key order`) replaced the cross-Xcode-sensitive encoder ordering with an internal UTF-8 lexical canonical writer after PR CI run [33282531973](https://github.com/taejunoh/needlbar/actions/runs/33282531973) failed on the Xcode 16.2 golden-byte test.

Corrected PR CI run [33283518126](https://github.com/taejunoh/needlbar/actions/runs/33283518126) passed. Main CI run [33283963156](https://github.com/taejunoh/needlbar/actions/runs/33283963156) passed all Rust, vendored, lint, `make test`, package, smoke, and artifact steps. The prior release build/package/smoke evidence and the live Settings save/cancel evidence remain recorded above with their exact head boundaries; the live UI run was on initial head `718748e`, not rerun after `6f39ec6`.

V0.2.0 is complete. The next continuation point is the separately scoped v0.2.1 widgets/notifications design and implementation, only after explicit user authorization. No tag or public GitHub Release was created; until explicit authorization is given, no tag or release action is authorized.

## Task 2 Verification

Task 2 is complete. The bridge now provides:

- `needlbar_usage_snapshot_json`, `needlbar_quota_snapshot_json`, and `needlbar_diagnostics_json` C exports.
- `needlbar_free_string` with null acceptance and Rust-owned `CString` exact-once release semantics.
- Versioned JSON envelopes with `schemaVersion`, `ok`, `generatedAt`, `data`, and `errors` fields.
- The typed `BridgeError { provider: Option<String>, code: String, message: String }` contract.
- Panic containment at every exported snapshot/free boundary, returning a versioned `internalError` envelope when needed.

Verification evidence:

- RED: `source /Users/taejunoh/.cargo/env && cargo test -p needlbar-bridge --test ffi_contract` exited 101 with the expected missing `needlbar_diagnostics_json` and `needlbar_free_string` symbols.
- GREEN: `cargo test -p needlbar-bridge` passed with 3 tests and `make test` exited 0; Rust passed including `tokscale-core` (1372 passed, 0 failed, 1 ignored) and Swift passed 2 tests.
- Scoped formatting: `cargo fmt -p needlbar-bridge -- --check` exited 0 after formatting only Task 2-owned Rust files.
- No approved-baseline deviation was made.

## Task 2 Contract (Complete)

The completed Task 2 bridge contract is:

Primary files from the approved plan:

- `Sources/CNeedlbar/include/needlbar.h`
- `crates/needlbar-bridge/src/envelope.rs`
- `crates/needlbar-bridge/src/lib.rs`
- Task 2 bridge contract tests described in the implementation plan

Required exported C ABI:

```c
const char *needlbar_usage_snapshot_json(void);
const char *needlbar_quota_snapshot_json(void);
const char *needlbar_diagnostics_json(void);
void needlbar_free_string(const char *ptr);
```

Required JSON envelope fields:

- `schemaVersion`
- `ok`
- `generatedAt`
- `data`
- `errors`

The bridge must contain panic boundaries and clear Rust-owned string lifetime/freeing semantics. Do not add presentation logic to the bridge.

## Task 3 Verification

Task 3 is complete. The usage adapter owns only the bridge-facing aggregation and delegates discovery/parsing to the pinned `tokscale-core` public graph-report API:

- Builds `tokscale_core::ReportOptions` and calls `tokscale_core::generate_local_graph_report` through a short-lived Tokio runtime.
- Consumes `GraphResult.contributions[] -> DailyContribution.clients[]`; no Claude/Codex parser copies were added to Needlbar.
- Aggregates the exact upstream client IDs `claude` and `codex` into all-time, today, rolling 7-day, and rolling 30-day periods.
- Rejects negative/corrupt signed counters and invalid costs before converting to normalized unsigned bridge values.

Fixture totals are deterministic and sanitized:

| Provider | Input | Output | Cache read | Cache write | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Claude | 1000 | 250 | 400 | 100 | 1750 |
| Codex | 800 | 200 | 300 | 0 | 1300 |

Partial provider behavior is explicit: when one provider has no usage source, usable provider data remains in `data`, the envelope remains `ok: true`, and a provider-scoped `noUsageData` error is appended. When no providers have data, the envelope is `ok: false` with `noUsageData` errors.

Verification evidence:

- RED: `source /Users/taejunoh/.cargo/env && cargo test -p needlbar-bridge --test usage_contract` exited 101 before the adapter existed with the expected missing `usage::collect_usage_from_home` symbol (the partial-envelope test also intentionally exited 101 before extraction).
- GREEN: `cargo fmt -p needlbar-bridge -- --check`, `cargo test -p needlbar-bridge --test usage_contract`, `cargo test -p needlbar-bridge`, and `cargo test --manifest-path vendor/tokscale-core/Cargo.toml` all exited 0; the pinned engine reported 1372 passed, 0 failed, 1 ignored.
- GREEN project verification: `source /Users/taejunoh/.cargo/env && make test` exited 0; Rust passed including the pinned engine and Swift passed 2 tests.
- Task 2 CI run [31838440815](https://github.com/taejunoh/needlbar/actions/runs/31838440815) is green.
- No approved-baseline deviation was made; no vendor revision was changed.

## Task 4 Verification

Task 4 is complete. Needlbar now hydrates the pinned Tokscale-compatible Cursor usage cache before usage aggregation without adding a Cursor transcript/parser source or changing the pinned core revision.

Implementation and contract evidence:

- Credentials are resolved only from `~/Library/Application Support/Needlbar/cursor-session.json`, with private `0700` session directory and `0600` session/cache/marker/temp files on Unix. The session token is never logged or copied into bridge errors.
- The fixed request target is Cursor's proven Tokscale export endpoint, `https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens`, with a bounded 15-second HTTP timeout and the `WorkosCursorSessionToken` cookie only.
- The five-minute freshness gate skips transport calls for fresh cache/attempt markers; `force=true` bypasses it. Every attempt touches `usage.last-sync-attempt`.
- Cache writes are same-directory temporary-file `write_all`/`sync_all` followed by rename and parent-directory `sync_all`, preserving the previous cache on transport, malformed-response, or durability failure.
- CSV validation accepts the pinned parser's v1, v2, and v3 layouts, requires parser-valid rows, and rejects malformed or unsupported responses before replacement.
- Unix path handling is descriptor-relative and no-follow: intermediate directories use `openat`/`mkdirat` with `O_DIRECTORY | O_NOFOLLOW`, leaves reject symlinks/non-regular files, and rename/cleanup/fsync remain descriptor-relative.
- The bridge places `usage.csv` at `<fixture-home>/.config/tokscale/cursor-cache/usage.csv` and relies on the pinned core's normal `ReportOptions.home_dir` discovery; no custom cache-root fork was added.
- Production refresh calls `sync_cursor_cache(false)` before scanning Claude, Codex, and Cursor. A sync failure becomes a provider-scoped `cursorSyncFailed` warning while valid prior Cursor cache data remains usable.

Verification evidence:

- Original RED: `source /Users/taejunoh/.cargo/env && cargo test -p needlbar-source-sync --test cursor_sync` and `cargo test -p needlbar-bridge --test cursor_usage_contract` exited 101 with the expected missing source-sync API/imports and missing Cursor snapshot assertion.
- Original GREEN: `cargo fmt -p needlbar-source-sync -p needlbar-bridge -- --check`, `cargo test -p needlbar-source-sync`, `cargo test -p needlbar-bridge --test cursor_usage_contract`, `cargo test -p needlbar-bridge`, `cargo test --manifest-path vendor/tokscale-core/Cargo.toml`, and `source /Users/taejunoh/.cargo/env && make test` exited 0; the pinned engine reported 1372 passed, 0 failed, 1 ignored, and Swift passed 2 tests.
- Hardening GREEN: source-sync tests passed 4 tests after malformed-response/no-follow validation and 5 tests after descriptor-relative traversal/v1 compatibility; bridge cursor contract passed 1 test; scoped rustfmt and `make test` passed with the pinned engine at 1372 passed, 0 failed, 1 ignored and Swift at 2 passed.
- Task 3 CI run [31839252018](https://github.com/taejunoh/needlbar/actions/runs/31839252018) is green.
- No approved-baseline deviation was made and the `tokscale-core` vendor revision was not changed.

## Task 5 Verification

Task 5 is complete and review-approved. The shared quota domain and Claude adapter are implemented without Codex/Cursor quota code, browser scraping, Keychain access, login prompts, token-history parsing, bridge changes, or presentation changes.

Implementation and contract evidence:

- The quota domain provides `ProviderId`, checked `QuotaWindow`, `ProviderQuotaSnapshot`, `QuotaErrorCode`, `QuotaError`, and the async `QuotaProvider` trait. Percentages are finite and normalized to `0...100`; invalid values return `schemaChanged` without clamping.
- Claude credential precedence is exact: `CLAUDE_CONFIG_DIR/.credentials.json` when configured, otherwise `~/.claude/.credentials.json`. Background refresh uses existing file OAuth only, never Keychain/browser scraping; missing or unusable credentials return `requiresAuthentication`, and known expired evidence returns `authenticationExpired`.
- The bounded/redacting HTTP client uses the Anthropic OAuth usage endpoint with a 15-second timeout, validates the allowed HTTPS host before attaching bearer authorization, does not follow redirects, limits response bodies to 64 KiB, bounds `Retry-After`, and never exposes fixture tokens or response bodies in errors.
- Sanitized Claude fixtures produce stable `claude.session` and `claude.weekly` windows; malformed, missing-reset, and out-of-range payloads fail safely as `schemaChanged`.

Verification evidence:

- Claude integration suite: `cargo test -p needlbar-quota --test claude` — 11 passed, 0 failed.
- Quota package: `cargo test -p needlbar-quota` — 7 unit tests and 11 Claude integration tests passed.
- Scoped lint: `cargo clippy -p needlbar-quota --all-targets -- -D warnings` passed after preserving the separate Task 4 hygiene commit `1cef31c`.
- Full project gate: `PATH="$HOME/.cargo/bin:$PATH" make test` passed; Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored, and Swift had 2 passed.
- Formatting and `git diff --check` passed.
- Task 5/documented head `e0d3da0` is pushed and green in [run 31841873719](https://github.com/taejunoh/needlbar/actions/runs/31841873719).
- No approved-design deviation was made; the pinned `tokscale-core` revision and all prior v0.1 constraints are unchanged.

## Task 6 Verification

Task 6 is complete, review-approved, and has no open findings. Codex quota uses the authenticated primary source first and a bounded exact app-server fallback without launching an interactive TUI or login flow.

Implementation and contract evidence:

- Primary auth resolves `$CODEX_HOME/auth.json`, falling back to `~/.codex/auth.json`; OAuth evidence remains Rust-only and never enters presentation data or debug output.
- The primary source calls the allowlisted `https://chatgpt.com/backend-api/wham/usage` endpoint through the bounded redacting HTTP client. The fallback runs `codex -s read-only -a untrusted app-server` with a 20-second deadline, capped stdout/stderr, request-ID correlation, `kill_on_drop`, explicit kill/wait/reap, and stderr-task cleanup.
- The JSON-RPC transcript is exact: initialize → initialized → `account/read` with `params: {}` → `account/rateLimits/read` without params; matched responses require JSON-RPC 2.0 and tolerate notifications/mismatched IDs safely.
- Primary and secondary windows plus reset fields accept absent/null provider values; available windows are preserved, both missing windows produce a valid empty snapshot, and malformed present values or contradictory percentages fail closed as `schemaChanged`.
- Stable window IDs remain `codex.primary` and `codex.secondary`; executable-missing, authentication, deadline, and malformed-RPC cases map to the documented safe error categories.

Verification evidence:

- Transport unit tests: `cargo test -p needlbar-quota --lib providers::codex::tests` — 6 passed.
- Codex integration tests: `cargo test -p needlbar-quota --test codex` — 6 passed.
- Quota package: `cargo test -p needlbar-quota` — 30 passed.
- `cargo check -p needlbar-quota` and `cargo clippy -p needlbar-quota --all-targets -- -D warnings` passed.
- Full project gate: `make test` passed; Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored, and Swift tests passed.
- Task 6/documented head `7aada1a` is pushed and green in [run 31843385394](https://github.com/taejunoh/needlbar/actions/runs/31843385394).
- No approved-design deviation was made; all prior v0.1 constraints and the pinned `tokscale-core` revision remain unchanged.

## Task 7 Verification

Task 7 is complete and review-approved. The review has no open findings; the only deferred minor is logger-capture coverage, which is non-blocking because the bridge has no logging path.

Implementation and contract evidence:

- `CursorSessionStore` is shared by source sync and quota, remains Rust-owned, preserves descriptor-relative no-follow handling, and performs atomic durable saves with private `0600` permissions and safe clear/load behavior.
- Cursor quota uses the bounded `https://cursor.com/api/usage-summary` request with HTTPS/host validation, redirects disabled, a 15-second timeout, the session cookie only, and the existing 64 KiB response cap. Usage-source transport is likewise bounded and preserves the last valid cache on failure.
- Cursor windows are stable `cursor.plan` and `cursor.onDemand`; absent billing-cycle end remains `resetsAt: null`, while malformed/contradictory values fail closed as `schemaChanged`.
- Missing/invalid sessions and 401/403 errors carry structured serialized `action: "connectCursor"`; `BridgeError { provider, code, message }` remains unchanged.
- `needlbar_cursor_import_session_json` validates null/UTF-8/empty/whitespace/control input, verifies before saving, contains panics, returns only `{ "connected": true }`, and the ABI/redaction tests prove the token is absent from JSON/debug/captured-log surfaces.

Verification evidence:

- Source-sync suite: `cargo test -p needlbar-source-sync` — 12 tests passed (2 unit + 10 integration).
- Cursor quota suite: `cargo test -p needlbar-quota --test cursor` — 7 passed.
- Bridge suite: `cargo test -p needlbar-bridge` — 9 passed across unit and integration targets.
- Affected strict lint: `cargo clippy -p needlbar-source-sync -p needlbar-quota -p needlbar-bridge --all-targets -- -D warnings` passed; formatting checks passed.
- Full project gate: `make test` passed; Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored, and Swift tests passed.
- `vendor/tokscale-core` is clean and remains pinned at `53f9eefffd3278fd430076531548f7b1f5861f9a`.
- Task 7/documented head `fcc5d22` is pushed and green in [run 31845316146](https://github.com/taejunoh/needlbar/actions/runs/31845316146).
- No approved-design deviation was made; all prior v0.1 constraints remain unchanged.

## Task 8 Verification

Task 8 is complete and review-approved with no Critical or Important findings. One minor delayed-provider test remains deferred and is non-blocking.

Implementation and contract evidence:

- `quota::collect_quota()` runs Claude, Codex, and Cursor adapters concurrently with bounded provider-owned timeouts while preserving deterministic provider/error order: Claude, Codex, Cursor.
- Partial and all-provider failures preserve usable `data.providers` and provider-scoped errors with `ok: true`; only bridge-wide runtime, panic, or serialization failures return `ok: false`.
- Synchronous quota C ABI calls execute collection on a dedicated Rust thread with a short-lived Tokio runtime, preventing nested-runtime panics when the embedding process already runs Tokio.
- The additive structured `BridgeError.action` field propagates Cursor's `connectCursor` action without changing the required `provider`, `code`, and `message` fields. Usage and diagnostics ABI behavior remains compatible.

Verification evidence:

- Focused bridge contract: `cargo test -p needlbar-bridge --test quota_contract` — 2 passed.
- Full bridge suite: `cargo test -p needlbar-bridge` — 11 passed.
- `cargo fmt -p needlbar-bridge -- --check`, `cargo check -p needlbar-bridge`, and `cargo clippy -p needlbar-bridge --all-targets -- -D warnings` passed.
- Full project gate: `make test` passed; Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored, and Swift tests passed.
- Task 8/documented head `dc9f6d1` is pushed and green in [run 31846072025](https://github.com/taejunoh/needlbar/actions/runs/31846072025).
- No approved-design deviation was made; all prior v0.1 constraints and the pinned `tokscale-core` revision remain unchanged.

## Task 9 Verification

Task 9 is complete and review-approved with no Critical or Important findings. Three test-only minors are deferred: successful/null-pointer bridge coverage, successful quota live-shape coverage, and generic pre-success/partial routing coverage.

Implementation and contract evidence:

- Added normalized Swift provider, usage, quota, status, and merged snapshot models with additive/live wire decoding that tolerates unknown fields, providers, and actions without installing unknown providers.
- Decimal costs decode exactly from decimal strings and the existing Rust numeric representation, without a `Double` round-trip.
- The Rust bridge wrapper copies C bytes into Swift-owned data and frees every non-null Rust string exactly once on all decode paths, including decoding errors.
- Usage and quota repositories retain partial successes and provider-scoped errors independently. The actor-isolated snapshot store keeps independent usage/quota values and last-success timestamps, preserving prior values on refresh failures and applying authentication status only before any valid value exists.

Verification evidence:

- Focused Swift verification: `swift test --filter NeedlbarCoreTests` — 7 independently focused tests passed after the final decoding-error free-path regression.
- Full project gate: `source /Users/taejunoh/.cargo/env && make test` exited 0; Swift reported 8 tests passed, Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored.
- `source /Users/taejunoh/.cargo/env && make rust` exited 0.
- Remote CI remains green through Task 8 at [run 31846072025](https://github.com/taejunoh/needlbar/actions/runs/31846072025); Task 9 commit `f078ff7` is local and its CI push is pending.
- No approved-design deviation was made; all prior v0.1 constraints and the pinned `tokscale-core` revision remain unchanged.

## Task 10 Verification

Task 10 is complete and final concurrency/spec review-approved with no findings. Refresh coordination, file-system triggers, and the production forced Cursor synchronization path are implemented across the assigned Swift, Rust, and C bridge layers.

Implementation and contract evidence:

- Manual and scheduled refreshes coordinate bounded usage and quota work independently. Usage keeps the approved five-minute cadence, file changes debounce for one second, and popover-triggered retries use the approved 60-second retry window.
- The forced usage ABI reaches production `sync_cursor_cache(true)` through the Rust bridge and Swift `UsageRepository`, so a manual refresh actually bypasses the Cursor freshness gate while preserving the existing repository path and pinned `tokscale-core` discovery layout.
- Refresh effects are guarded by run generation, manual bursts coalesce, watcher startup/stop ownership is lifecycle-safe, and descriptor/file-descriptor leases remain safe across asynchronous callbacks and cancellation.
- Usage and quota remain independently refreshable and independently fallible; one side's failure does not erase the other's valid last-known-good state.

Task 10 implementation commits on `main`:

- `cba429c` — coordinate bounded usage and quota refresh.
- `4675a40` — force Cursor sync through the production refresh bridge.
- `06aff57` — guard refresh effects by run generation.
- `8a873e4` — coalesce forced refresh requests.
- `f37eb2a` — close refresh lifecycle races.
- `ae2d70b` — isolate stale watcher startup.
- `916a29d` — await quota refresh completion in the synchronization regression test.
- `7e345d5` — serialize semaphore-based refresh race suites to prevent CI executor starvation.

Verification evidence:

- `cargo fmt -p needlbar-bridge -- --check` and `cargo clippy -p needlbar-bridge --all-targets -- -D warnings` passed.
- `swift test --filter RefreshCoordinatorTests` — 8 tests passed.
- `swift test --filter UsageFileWatcherTests` — 5 tests passed.
- `source /Users/taejunoh/.cargo/env && make test` passed: Swift 21 tests, Rust including pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean.
- Final independent review approved with no Critical, Important, or Minor findings. A test-only synchronization defect was diagnosed as a wait-condition issue; production behavior was verified correct, and `916a29d` now waits for the first quota refresh to finish before issuing the retry.
- The first Task 10 CI run [31852585168](https://github.com/taejunoh/needlbar/actions/runs/31852585168) was cancelled after more than 16 minutes in the Test workspace. Its log ended after Swift Build completed with an orphan `swiftpm-testing` process, matching the diagnosed test-only cooperative-executor starvation from three concurrent semaphore-based race tests rather than a production defect. Commit `7e345d5` adds `@Suite(.serialized)` to preserve the assertions and contracts; the reviewer approved the correction with no findings.
- Root verification passed: `RefreshCoordinatorTests` ran 10 times with `--parallel --num-workers 2`; `make test` passed with Swift 21 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored; `git diff --check` and the vendor status check were clean.
- No approved-design deviation was made; the pinned `tokscale-core` revision and all v0.1 constraints remain unchanged.

- Remote verification is complete: Task 10 CI run [31853771074](https://github.com/taejunoh/needlbar/actions/runs/31853771074) passed in 7m1s at head `6b7b969`. This confirms the Task 10 retry containing `7e345d5`; Task 11 remains the next implementation task.

## Task 11 Verification

Task 11 is complete and rereview-approved with no findings. Module configuration and menu-bar title rendering now follow the approved v0.1 defaults and presentation boundary.

Implementation and contract evidence:

- The approved defaults are Overview enabled, all providers disabled, and `quotaRemaining` as the quota headline mode.
- Only non-secret UI preferences are stored in injected `UserDefaults`; credentials and provider session data remain outside the configuration layer.
- The enabled-provider quota headline selects the most constrained available Overview quota, while Overview token and cost totals aggregate every available usage snapshot.
- The pure menu-bar renderer uses a neutral unavailable state, deterministic number/cost formatting, deterministic reset formatting including `nil`, and checked `UInt64` aggregation without overflow wrapping.

Task 11 implementation commits on `main`:

- `5a00c3c` — implement module configuration and menu-bar title logic.
- `6dbd4a9` — resolve review findings and harden configuration/rendering behavior.

Verification evidence:

- Review round 1 found 2 Important and 1 Minor findings; all were resolved in `6dbd4a9`, and rereview approved with no findings.
- Root fresh verification passed: `ModuleConfigurationTests` — 2; `HeadlineQuotaSelectorTests` — 4; `MenuBarTitleRendererTests` — 5.
- `source /Users/taejunoh/.cargo/env && make test` passed with Swift 32 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean.
- No approved-design deviation was made; the pinned `tokscale-core` revision and all v0.1 constraints remain unchanged.
- Remote verification is complete: Task 11 CI run [31854765005](https://github.com/taejunoh/needlbar/actions/runs/31854765005) passed in 4m40s at head `84a1d7c`. Task 12 remains the next implementation task.

## Task 12 Verification

Task 12 is complete and rereview-approved with no findings. The native accessory runner and hybrid status-item shell now own lifecycle coordination while keeping normalized state and presentation logic in their assigned layers.

Implementation and contract evidence:

- The thin AppKit runner/accessory shell is wired to the existing `LSUIElement` application configuration; `Info.plist` already had `LSUIElement`, so no manifest churn was needed.
- `AppDelegate` owns one long-lived snapshot store, module configuration, refresh coordinator, Rust-backed repositories, watcher, and menu-bar controller for the application lifetime.
- Menu-bar handles reconcile incrementally. Snapshot and configuration observations are installed with explicit cleanup, avoiding duplicate observers and stale handles.
- Titles remain neutral when data is unavailable. `terminateLater` performs exactly-once awaited shutdown of the owned lifecycle resources.

Task 12 implementation commits on `main`:

- `b3cb0ca` — build the native accessory app and hybrid status items.
- `b491f32` — resolve lifecycle/shutdown review findings.

Verification evidence:

- Review round 1 found 1 Important shutdown finding; it was resolved in `b491f32`, and rereview approved with no findings.
- Root fresh verification passed: `MenuBarControllerTests` — 7; `AppDelegateLifecycleTests` — 1.
- `source /Users/taejunoh/.cargo/env && make test` passed with Swift 40 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean.
- Smoke verification initially hit the expected local-PATH-only failure when `make run` was invoked without the Cargo environment. After `source /Users/taejunoh/.cargo/env`, `make run` built and launched Needlbar; the foreground process group was interrupted and `pgrep` confirmed no Needlbar process remained.
- No approved-design deviation was made; the pinned `tokscale-core` revision, existing `LSUIElement` setting, and all v0.1 constraints remain unchanged.
- Remote verification is complete: Task 12 CI run [31855885744](https://github.com/taejunoh/needlbar/actions/runs/31855885744) passed in 4m39s at head `4988d10230c30c347d5ab2d92af1155a9aec684d`. Task 13 remains the next implementation task.

## Task 13 Verification

Task 13 is complete and the final reviewer approved it after three rounds. Overview, provider popovers, and Settings now cover partial data, provider connections, and the approved UI preferences without moving secrets into Swift persistence.

Implementation and contract evidence:

- `Overview`, provider popovers, and Settings use shared presentation models for partial usage/quota states, neutral unavailable rendering, provider rows, quota windows, resets, stale/error indicators, and the Settings action.
- The existing aggregate bridge/Core contract now has the additive `last7DaysDaily` field: exactly seven chronological dated `{date,totalTokens}` points, including legitimate zero days, with checked token aggregation. Swift treats an absent additive field as `[]` for compatibility.
- The Cursor Settings path adds the safe, idempotent `needlbar_cursor_clear_session_json` ABI backed by Rust-owned session clearing. It returns only the disconnect result, releases its response, and preserves token redaction.
- Cursor input remains transient `@State`; import/clear run off-main, clear the input before work completes, and serialize connect/reconnect/disconnect operations so rejected actions retain no token and cannot race an accepted action.

Task 13 implementation commits on `main`:

- `e10cad3` — add AI usage popovers and Settings.
- `0a9cda1` — harden enabled-provider quota selection and off-main secret handling.
- `7720c81` — serialize Cursor connection actions.

Verification evidence:

- TDD RED coverage first caught the missing presentation models, additive `last7DaysDaily` bridge/Core field, and missing `needlbar_cursor_clear_session_json`; subsequent RED regressions covered enabled-provider headline selection, transient-input clearing, and serialized slow Cursor actions.
- Final review completed three rounds and approved with no findings.
- Root fresh verification passed: `cargo test -p needlbar-bridge` — 8 unit plus 7 integration/contract tests (15 total); `swift test --filter PopoverPresentationTests` — 10 tests.
- `source /Users/taejunoh/.cargo/env && make test` passed with Swift 51 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean at pinned revision `53f9eefffd3278fd430076531548f7b1f5861f9a`.
- Bounded `make run` built and launched Needlbar; Ctrl-C stopped the foreground process group and a follow-up process check found no lingering Needlbar process.
- Live interactive menu-bar clicks and a real Cursor-session smoke were not performed in the noninteractive environment; automated seams cover secret clearing and connection ordering.
- The daily series and Cursor disconnect are deliberate additive bridge-contract extensions required by the Task 13 plan, not a product redesign or scope deviation. No other approved-design deviation was made.
- Remote verification is complete: Task 13 CI run [31857311990](https://github.com/taejunoh/needlbar/actions/runs/31857311990) passed in 4m49s at tested head `0d73338aa9d79f40de42192d5715a60a824c15a6`. Task 14 remains the next implementation task.

## Task 14 Verification

Task 14 is complete and the final reviewer approved the implementation in review round 2. Diagnostics, privacy guardrails, public documentation, and the full feature-only integration seam now enforce the approved v0.1 boundaries.

Implementation and contract evidence:

- Rust diagnostics use safe DTOs with fixed provider, subsystem-status, source, and error-code enums. Swift uses a strict diagnostics decoder. The bounded observation store records only actual usage/quota ABI statuses, timestamps, and safe codes; it performs no extra source, credential, or provider-response scans.
- Redaction coverage exercises the real exported C usage, quota, diagnostics, and free functions plus safe `BridgeError` serialization. `CLAUDE-CANARY-SECRET`, `CODEX-CANARY-SECRET`, and `CURSOR-CANARY-SECRET`, a raw path, and an email are absent while safe provider/code/action fields remain available.
- The feature-only fixture runtime drives the real C ABI through `RustBridge`, the usage/quota repositories, and `ProviderSnapshotStore` end to end. It covers usage and quota for all three providers, deterministic constrained Cursor selection, and partial Codex failure isolation without erasing other providers.
- Eight public documents lock the architecture, privacy, provider boundaries, security, contribution, and project usage contracts. Diagnostics and privacy surfaces exclude tokens, cookies, emails, raw paths, prompts, responses, and source code.
- The integration work discovered and fixed the `estimatedCostUsd` versus approved `estimatedCostUSD` wire mismatch with an explicit Rust serialization rename.
- The test harness feature is absent from the production C header and default bridge archive. `make swift-test` uses an exit/signal trap to restore the production bridge and clean SwiftPM artifacts, including after interrupted or failed test runs; archive/header checks found no `needlbar_test_*` markers.

Task 14 implementation commits on `main`:

- `5c0e339` — add diagnostics, privacy guardrails, public documentation, and feature-only integration coverage.
- `9e56abc` — harden ABI redaction, wire compatibility, and test artifact hygiene.

Verification evidence:

- TDD RED coverage first caught the absent diagnostics module/decoder and outcome mapper; follow-up RED coverage caught the real ABI `estimatedCostUSD` mismatch and stale SwiftPM static-library reuse.
- Root fresh `make test` exited 0 with Swift 54 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `cargo clippy --workspace --all-targets --all-features -- -D warnings` passed.
- `swift build -c release` exited 0. It emitted pre-existing, non-blocking macOS object-version/Apple linker warnings; the release build succeeded.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean at pinned revision `53f9eefffd3278fd430076531548f7b1f5861f9a`.
- Strings checks over the release archive and production header found no `needlbar_test` markers.
- The feature-only test harness is a deliberate test-only integration seam required by the Task 14 plan, not a production feature or design deviation. No other approved-design deviation was made.
- The first Task 14 CI run [31859272045](https://github.com/taejunoh/needlbar/actions/runs/31859272045) failed only after the builds because the Makefile symbol audit invoked unavailable `rg`; no test or build failed. Systematic diagnosis produced follow-up commits `c27b3b5` (portable `strings`/`grep` audit), `bd8b439` (trap-before-`mktemp` and signal cleanup), and `8e24654` (restoration-failure priority). Reviewers approved the fixes, and restricted-PATH local `make test` passed with Swift 54 and pinned core 1372 passed/1 ignored.
- Remote verification is complete: Task 14 CI run [31859898712](https://github.com/taejunoh/needlbar/actions/runs/31859898712) passed in 4m52s at tested head `8e246543ef89bc789582e646d81c2cc7a6807492`. Task 15 remains the next implementation task.

## Task 15 Verification

Task 15 completes the approved v0.1 implementation plan. The final independent reviewer approved the packaging, smoke, cleanup, and release-workflow implementation after the review rounds.

Implementation and artifact evidence:

- The production build is an arm64 macOS 14 Rust/Swift accessory app with no test-only runtime feature. Packaging produces `dist/Needlbar.app` and `dist/Needlbar-macos-arm64.zip`; the app bundle contains `Contents/Info.plist`, the arm64 `Contents/MacOS/Needlbar` executable, and `Contents/Resources/ThirdPartyNotices.txt`. The zip has `Needlbar.app` at its archive root.
- `make package` applies an ad-hoc signature accepted by strict `codesign` verification. `scripts/smoke-app.sh` validates plist, signature, and arm64 executable identity, launches the exact bundle executable, and performs bounded cleanup.
- Smoke cleanup captures the launched PID, parent PID, exact executable command, and `ps lstart` identity before signaling. PID reuse/identity mismatch, deferred `INT`/`TERM`, bounded mismatch return, fixture-directory cleanup, and exact-PID regressions are covered; cleanup never signals an unverified process.
- CI gates run workspace Cargo tests/strict Clippy, `make test`, package, packaged-app smoke, and arm64 artifact upload. The tag release workflow hard-gates stable publication on Developer ID certificate/keychain setup, Apple ID/team/app-specific-password secrets, then signs, notarizes, staples, re-verifies, and publishes the zip.
- README install/privacy requirements, MIT licensing, Tokscale attribution, and third-party notices are included. `MACOSX_DEPLOYMENT_TARGET=14.0` preserves the approved macOS 14 floor and removes the locally observed Rust object-version linker warning.

Task 15 implementation commits on `main`:

- `d120264` — package and verify the Needlbar macOS release.
- `6d1c240` — harden PID identity and deferred-signal cleanup.
- `fecb08c` — bound identity-mismatch cleanup without synchronous waiting.
- `5adaa7f` — close the fixture cleanup window around temporary directories and signals.
- `a8e82fc` — harden fixture child identity capture and exact cleanup.

Final acceptance evidence:

- From the initialized submodule checkout, the pinned revision check, `cargo test --workspace`, `cargo clippy --workspace --all-targets --all-features -- -D warnings`, `make test`, `make package`, `./scripts/smoke-app.sh`, and `git diff --check` all passed.
- Root final gate reported Swift 54 tests, pinned `tokscale-core` 1372 passed with 1 ignored, strict workspace Clippy success, clean vendor state at `53f9eefffd3278fd430076531548f7b1f5861f9a`, and clean plist/codesign/file/unzip/artifact checks. Focused smoke cleanup regressions passed repeatedly with no lingering Needlbar process or fixture directories.
- The first production `make run`/packaged-app smoke launched and terminated cleanly; the exact PID was cleaned and no Needlbar process remained.
- No implementation or approved-design deviation was made. The macOS 14 deployment-target setting is an explicit build correction that preserves the approved platform floor.

- Hosted Task 15 verification is complete: CI run [31861693135](https://github.com/taejunoh/needlbar/actions/runs/31861693135) passed in 8m33s at tested head `98203636d5c8a5d5dd99cc2e575f18fb2ae7cea7`. Rust workspace tests, strict Clippy, `make test`, package, cleanup regression, packaged smoke, and arm64 artifact upload all passed.
- Uploaded artifact `Needlbar-macos-arm64` has API id `9240875960`, size `5,139,200` bytes, was created `2026-08-15T03:32:10Z`, is not expired, and expires `2026-11-13T03:23:36Z`. Its downloaded `Needlbar-macos-arm64.zip` is 5,151,078 bytes with SHA-256 `1358d46f0c0ec29474e43d458a6b0c3751931df6ca9236d56a75a218ab7dccbe`; unzip integrity passed with `Needlbar.app` at the root, correct `Contents`, and no `dist` prefix, `__MACOSX`, or AppleDouble files.

Release acceptance intentionally not claimed:

- No git tag or GitHub Release was created.
- Local Developer ID signing, strict verification, and hardened-runtime checks passed. Notarization, stapling, and publication were not run because the required secrets were not provided; the release workflow refuses to publish an ad-hoc stable artifact when they are absent.
- Manual Accessibility click-through and partial live smoke were performed on 2026-08-15; the full provider matrix remains incomplete for Claude quota/auth fallback, Cursor usage/quota with an explicit session, and the Codex CLI fallback.

## Credentialed/Manual Release Acceptance — 2026-08-15

- On a supported Mac, the packaged app launched as an accessory/menu-bar app with Overview as the only initial item. macOS Accessibility click-through opened the Overview popover, Settings window, and Codex provider popover. Enabling Codex added a second menu item; disabling it restored the single Overview item. An immediately-read `AXValue` can be stale after a press, but defaults, menu state, and rendered state agreed; no product bug was found.
- A one-process ABI run returned usage successfully for Claude and Codex, with seven daily points each; Cursor returned `noUsageData`. Quota returned one successful Codex window; Claude observed `authenticationExpired` followed by `rateLimited`; Cursor returned `requiresAuthentication`/`connectCursor` because no session was available. Diagnostics reflected these statuses safely. The Codex CLI fallback was not forced because its primary source succeeded.
- A standalone usage scan completed in approximately 89 seconds on the large local history during the second controlled run. The UI stayed responsive and displayed last-known-good data; this is a non-blocking performance observation unless the approved specification changes.
- Gatekeeper rejected an unstapled/unnotarized copy as expected after the local Developer ID sign/strict-verification/hardened-runtime check. The GitHub repository secret list is empty, so the stable notarization workflow cannot run. No Cursor session was available.

Remaining release acceptance: retry Cursor explicit-session connection once with a fresh current session token obtained through the documented supported route, without broadening to browser crawling; then configure the required GitHub notarization/release secrets and run the notarize/staple/Gatekeeper gate. The Codex CLI fallback remains unforced. Only after those gates may the user authorize a v0.1 tag/release.

## Final v0.1 Continuation

The original fifteen-task implementation plan and hosted CI/artifact verification are complete. Release acceptance is now paused by the approved authentication amendment below; complete its separate follow-up plan and verification before returning to credentialed/manual release acceptance and a user-authorized v0.1 tag/release.

## Approved Authentication Amendment — 2026-08-25

> The provider-managed browser-login and Cursor-paste records below are historical records
> from before the approved 2026-08-26 Cursor local-usage/dashboard amendment. Their Claude
> and Codex requirements remain active; every Cursor session-token, private-endpoint, and
> connection requirement is superseded by the amendment and is not an active instruction.

The user approved a deliberate post-plan design change before release acceptance:

- Claude gains `Sign in with Claude`, launching `claude auth login --claudeai` as an explicit user action.
- Codex gains `Sign in with ChatGPT`, launching `codex login` as an explicit user action.
- The provider CLIs continue to own browser navigation, OAuth callbacks, token refresh, and credential storage.
- Needlbar does not add an OAuth client, persist or expose Claude/Codex tokens, read browser profiles, or retain child-process output.
- The user explicitly approved access to Claude Code's exact provider-owned macOS Keychain item after clicking Connect. Raw credentials remain ephemeral inside Rust quota code and never cross the C ABI; background refresh uses interaction-forbidden access and never displays Keychain UI.
- Cursor retains the current explicit validated session-token Connect/Reconnect/Disconnect path. Cursor's documented CLI browser login does not expose the personal usage/quota handoff required by Needlbar.
- AppKit owns login-process lifecycle; `NeedlbarCore` gains typed background/user-initiated quota intents; Rust adds dedicated Claude-only and Codex-only post-authentication quota exports but no login/OAuth callback API.

The approved delta spec is `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md`. The test-first execution plan is `docs/superpowers/plans/2026-08-25-provider-managed-browser-login.md`.

### Task 1 Follow-Up Verification

Task 1 of the provider-managed browser-login follow-up is complete and review-approved. The implementation was delivered in focused commits:

- `6611ac0` — add prompt-safe Claude credential resolution.
- `35cecf0` — cover Claude bearer canary redaction.
- `57331fa` — confine the Claude test endpoint seam.

TDD RED was observed for the missing credential-access API and the follow-up test seams before implementation. Final verification passed: Claude integration — 16 tests; full `needlbar-quota` — 46 tests; formatting check; Clippy with `-D warnings`; default Cargo check; and `git diff --check`.

No real Keychain access, UI interaction, or external provider call was performed. The spec-compliance review passed, and the code-quality review passed with no issues. The pre-existing Task 15 verification remains valid for the current code, but release acceptance remains paused; the full authentication amendment is not complete.

### Task 2 Follow-Up Verification

Task 2 of the provider-managed browser-login follow-up is complete and review-approved. The implementation was delivered in focused commits:

- `fc76d64` — map `PermissionDenied` through the bridge integration path, restoring the full workspace green after Task 1.
- `ca80091` — add provider-specific Claude/Codex quota ABI exports.
- `8b6fd5c` — resolve diagnostics/runtime review fixes.
- `09112dc` — scope fixture sessions and remove production fallback behavior.
- `7adc458` — harden zero-session handling.

The provider-specific exports are `needlbar_claude_user_initiated_quota_snapshot_json` and `needlbar_codex_quota_snapshot_json`. Claude's explicit login path uses `UserInitiatedAllowUI`; the all-provider path remains `BackgroundNoUI`; and the Codex-only path does not invoke unrelated providers.

Verification evidence:

- FFI contract — 3 tests; quota contract — 6 tests; redaction contract — 6 tests; full bridge suite passed.
- Clippy with `-D warnings` passed; full `make test` exited 0 with Swift 55 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- No real Keychain, network, or UI interaction was performed; only pre-existing linker warnings remain.
- Final spec-compliance and code-quality reviews approved with no Critical, Important, or Minor findings.

Release acceptance remains paused, and the full authentication amendment is not complete.

### Task 3 Follow-Up Verification

Task 3 of the provider-managed browser-login follow-up is complete and review-approved. Typed quota refresh intents, dedicated provider calls, and generation-scoped coordinator fairness are implemented without browser, Keychain, or network interaction.

Implementation and contract evidence:

- Typed background and user-initiated quota intents are carried through the bridge/repository/coordinator path; Claude and Codex use dedicated provider calls, while Cursor is explicitly unsupported for typed provider refresh.
- Rust-owned C strings are freed exactly once by exact pointer, and generation-scoped waiters complete exactly once. Requested-provider failures remain scoped to the requested provider.
- Background freshness gates and ticket fairness preserve the approved refresh behavior, and quota refresh has no usage side effects.

Task 3 implementation commits:

- `843d588` — initial typed quota refresh implementation.
- `0095163` — fix waiter generation and protocol behavior.
- `f910e9a` — add dedicated validation and fairness coverage.

Verification evidence:

- Final Bridge suite: 15 tests passed.
- Final coordinator suite: 23 tests passed.
- Final Swift suite: 80 tests passed.
- `make swift-test` and `make test` exited 0.
- The implementation is spec-compliant; the quality review found no Critical, Important, or Minor findings.
- No browser, Keychain, or network interaction was performed, and no provider login command was launched.

Release acceptance remains paused. Task 4's non-TTY manual gate is complete; continue with Task 5 before returning to the remaining release-acceptance checks.

### Task 4 Automated Verification

Task 4's automated implementation is complete and final spec-compliance and code-quality reviews passed with no open Critical or Important findings. The separate user-authorized non-TTY provider compatibility gate also passed, so Task 4 is accepted as complete.

Implementation commits through the current head `3364c3c` include the provider login coordinator, direct POSIX runner, bounded termination/reaping hardening, deterministic syscall seams, admission lifetime fixes, and the documented gate result. No provider credentials, account identifiers, or login URLs are recorded here.

Verification evidence:

- `make swift-test` passed in five consecutive runs, with 113 Swift tests each run.
- `make test` passed cleanly after the final Task 4 implementation and test hardening.
- `git diff --check` passed and the working tree is clean.
- The final automated review evidence covers process lifecycle, signal/reap races, exact executable/argv/env/fd/CLOEXEC contract, cancellation/timeout/stop coalescing, descendant isolation, and failure-path bounds.

### Task 4 Non-TTY Provider Compatibility Gate

The user-authorized non-TTY compatibility gate passed on 2026-08-25 using the implementation runner's exact contract: direct `posix_spawn`, exact executable path and fixed argv, stdin from `/dev/null`, stdout/stderr from `/dev/null`, allowlisted environment, and no shell, PTY, output parsing, or credential capture.

- Claude Code 2.1.238: the resolver selected `/Users/taejunoh/.local/bin/claude`; `auth login --claudeai` opened the provider-owned browser and exited with status 0 after 207.856 seconds. The sanitized status was `loggedIn: true`, `authMethod: claude.ai`.
- Codex CLI 0.142.5: the resolver selected `/opt/homebrew/bin/codex`; `login` opened the provider-owned browser and exited with status 0 after 17.626 seconds. The sanitized status was `Logged in` / `ChatGPT`.

No provider login child remained after either run. The production Rust archive was restored without test symbols, the temporary manual test was removed, and the worktree remained clean. No account identifiers, URLs, credentials, or provider CLI output were persisted in project files.

### Task 4 approved implementation deviation — direct POSIX spawn

The approved Task 4 implementation keeps AppKit as the application/lifecycle owner but replaces the planned Foundation transport with direct macOS `posix_spawn` and parent-owned nonblocking `waitpid`. Foundation Process was rejected because it can reap asynchronously and exposes only a numeric PID; direct spawn/waitpid preserves PID identity until Needlbar itself reaps the child.

The single session actor is the sole waitpid owner. The runner resolves an exact executable URL/path (never `posix_spawnp`), validates NUL-free executable/argv/envp values, passes the executable path as `argv[0]` followed by fixed arguments, builds an allowlisted `envp`, connects stdin to `/dev/null` read and stdout/stderr to `/dev/null` write through spawn file actions, and sets `POSIX_SPAWN_CLOEXEC_DEFAULT`. It polls `waitpid(WNOHANG)`, retries `EINTR`, treats `ECHILD` as an invariant violation with no further signal, switches to reap confirmation after `ESRCH`, and bounds other signal failures. Timeout, cancellation, and app stop coalesce into TERM, bounded grace, KILL, and final reap of the direct PID only; descendants are never targeted.

Task 4 verification included harmless real-child normal and TERM-only exits, TERM-to-KILL, cancellation, timeout, cancel-plus-stop coalescing, pre/post-spawn cancellation, syscall-seam `WNOHANG`/exit/`EINTR`/`ECHILD`/`ESRCH`/KILL-failure cases, exact argv/env/fd/CLOEXEC assertions, descendant isolation, and the user-authorized non-TTY provider command compatibility gate.

### Task 5 Verification

Task 5 is complete and final spec-compliance and code-quality reviews passed with no open findings. Settings and provider popovers expose the approved Claude/Codex browser-login actions, and app termination now preserves the required direct-child cleanup and retry semantics.

Implementation commits:

- `6f0a5fc` — expose Claude and Codex browser login.
- `fd5935c` — document the approved degraded termination behavior.
- `12cacf8` — report bounded login cleanup state.
- `a308b29` — keep the app alive while a login child is reaped.
- `675a713` — revalidate login process ownership.
- `c14cc39` — close login admission during termination.
- `3fdff59` — reopen login admission after a negative termination reply.
- `4eca8b5` — avoid nested task polling in the login runner.

Behavior and contract evidence:

- Login cleanup reports either `allChildrenReaped` or `backgroundReaping`. A persistent signal or `waitpid` failure sends exactly one negative AppKit reply, does not stop refresh, keeps the app/coordinator and affected provider admission alive while the actor reaps the exact child, and permits a later termination request to retry cleanup.
- Successful termination remains conditional on all login children being reaped before refresh shutdown. Concurrent termination requests coalesce, and admission closes during cleanup so no new login can race termination.
- The coordinator retains exact PID ownership through background reaping and resumes admission only after a denied termination decision; no credentials, account identifiers, or provider output are persisted.

Verification evidence:

- Repeated `make swift-test` runs were green, and the latest agent-reported `make test` completed successfully; final root verification remains the next verification step.
- Final Task 5 spec-compliance and code-quality reviews passed with no Critical, Important, or Minor findings.
- The Task 4 non-TTY compatibility gate remains accepted for Claude Code and Codex; no additional provider login was run during Task 5 implementation.

### Task 6 Final Verification and Claude Credentialed Acceptance — 2026-08-26

Task 6 implementation and Claude credentialed acceptance are complete for the exercised path. The following focused fixes were applied and reviewed:

- `3202474` — split the Claude Keychain lookup into reference and data phases while retaining the exact `Claude Code-credentials` service.
- `fe88442` — select the single accepted macOS Keychain item from the returned item list.
- `61e2d5f` — force the Swift release executable to relink during packaging without clearing SwiftPM caches.
- `226bda5` — accept explicit `null` Claude reset timestamps.
- `7d43804` — run the packaging relink regression through the default `make test` path.

Credentialed acceptance evidence:

- With Claude Code 2.1.238, the user-authorized `/Users/taejunoh/.local/bin/claude auth login --claudeai` flow completed successfully through the provider-owned browser.
- The exact Keychain service returned exactly one parseable item. No Keychain UI prompt appeared because access was already allowed; a prompt is not required when exact-item access succeeds.
- The live packaged app produced fresh Claude quota and fresh Codex quota. Claude Settings showed `Connected.` directly. The first Codex button attempt showed `Login incomplete.` because a new provider-auth tab was left incomplete and an already-successful tab was mistakenly treated as the current flow; this was an acceptance procedure error, not a product change.
- The exact `/opt/homebrew/bin/codex login` non-TTY revalidation completed the current provider flow for the account/workspace and exited 0. The Needlbar Codex button was then run again through a newly completed provider flow; Settings showed Codex `Connected.` and fresh Codex quota. Login-child completion was observed.
- Raw credentials and account data were never printed, persisted, or copied.

Fresh verification evidence:

- Claude integration: 17 tests passed; FFI contract: 3 passed; quota contract: 6 passed; redaction contract: 6 passed.
- Strict workspace Clippy passed. `make test` passed with the pinned `tokscale-core` suite at 1372 passed, 0 failed, 1 ignored, and Swift at 124 passed.
- The packaging regression passed through `make test`; codesign verification, zip creation, and packaged-app smoke passed. `vendor/tokscale-core` remained clean at the approved pinned revision.
- Specification and code-quality reviews were approved after the `package-test` CI linkage was added.
- Open PR #1 ([github.com/taejunoh/needlbar/pull/1](https://github.com/taejunoh/needlbar/pull/1)) remains open, unmerged, and currently `MERGEABLE`.
- The provider implementation/status head validated by hosted CI is `b3d116071d0ed3200b4ea431e2d65657329987ab`; run [32987657091](https://github.com/taejunoh/needlbar/actions/runs/32987657091) for that exact head completed `SUCCESS` at `2026-08-26T16:26:20Z`; the `test` job passed.
- The following status update is docs-only and changes no product code.
- Historical outage evidence: hosted CI run [32984248738](https://github.com/taejunoh/needlbar/actions/runs/32984248738) was queued with zero jobs while GitHub's official Actions status reported `major_outage` at `2026-08-26T15:11:58Z`.

### Cursor Explicit-Session Acceptance — 2026-08-26

- Packaged-app Settings showed Claude and Codex `Connected`; the Cursor session store was absent before the attempt.
- After the user's approved Connect action, the secure field was not read or exposed. The UI returned exactly the safe generic message `Cursor could not be connected.`, and the Cursor session store remained absent.
- This result does not establish a product bug or prove remote verification failure: input validation, network/provider verification, ABI/runtime, and post-verification save failures converge to the same safe generic UI, and success is returned only after save.
- The Settings secure field initially accepted typed input but not `Command-V` because the programmatic accessory app did not install a native Edit/Paste command. `ApplicationMenuInstaller` now installs or repairs `NSText.paste(_:)` with a `nil` target and the Command-`V` key equivalent so AppKit routes paste through the current first responder. Repeated installation does not create app-owned duplicates, and pre-existing external menu content is not deleted.
- TDD covered the missing installer, native selector/target/key contract, normal-path idempotence, malformed Paste repair, and preservation of pre-existing same-title menu content. The focused suite passed 3 tests; specification and code-quality reviews approved the final contract and implementation.
- Fresh root verification passed: `swift test --filter ApplicationMenuInstallerTests` ran 3 tests with 0 failures; `make test` exited 0 with the pinned `tokscale-core` suite at 1372 passed, 0 failed, 1 ignored and Swift at 127 passed; the package-app relink regression passed; `make package` produced the packaged app successfully.
- A packaged-app manual smoke copied only the harmless fixture `NEEDLBAR-PASTE-SMOKE`, focused the Cursor secure field, and pressed `Command-V`. Masked input appeared. The field and clipboard were immediately cleared, and Connect was not pressed. No provider token or clipboard contents were printed, logged, persisted, or exposed.
- Hosted CI run [32996703404](https://github.com/taejunoh/needlbar/actions/runs/32996703404) passed at Cursor paste implementation head `6c6f494d1fc66c0772dbae2ea4905dc245291bc8`: Rust tests and strict lint, complete project tests, arm64 packaging, cleanup regression, packaged-app smoke, and artifact upload all completed successfully.
- Blocker/next action: the user must paste a fresh current Cursor session token obtained through the documented supported route, without whitespace or newlines, and retry Connect once. Do not broaden the flow to browser crawling, and do not record or request the token in project documentation or chat.

Release remains unreleased: no tag or GitHub Release was created, and notarization/stapling/publication were not run.

## Required Next Action

Cursor amendment Tasks 1–5 are complete, the final whole-branch review is clean, and PR #1
remains open and `MERGEABLE`. The next external gate is the notarization/release-secrets
gate. Preserve the unreleased and unmerged status; no merge, tag, or release action is
authorized here, and never request or record a Cursor session token.

## Cursor Local Usage and Dashboard Amendment — 2026-08-26

The approved amendment replaces Cursor session-token authentication, remote usage hydration,
and personal quota retrieval with local-cache usage and a fixed Spending dashboard action.
The implementation is complete through Task 4; this section records the Task 5 acceptance
state and deliberately supersedes the older Cursor records above.

### Task 1–4 implementation commits

- `ec18fcd` — retire Cursor personal quota integration.
- `ebc6175` — make Cursor usage local-cache only and add the no-read cleanup migration.
- `b6251f5` — remove forced Cursor refresh state.
- `4b38fc7` — exclude retained Cursor quota windows from headlines.
- `5c79f49` — link Cursor quota-unavailable actions to the Spending dashboard.

### Task 1–4 verification summary

- Task 1 RED: the Cursor provider returned `RequiresAuthentication` with the old session
  path; GREEN: the provider and bridge contracts returned Cursor-scoped
  `providerUnavailable` with no action, and strict quota/bridge tests passed.
- Task 2 RED: the cleanup module was absent; GREEN: local-cache usage, no-read descriptor-
  relative cleanup, ABI removal, diagnostics, redaction, workspace Clippy, and bridge
  contracts passed.
- Task 3 RED: Swift still referenced the removed forced usage export and integration still
  expected a Cursor quota window; GREEN: one normal usage path, local Cursor usage, and
  unavailable Cursor quota passed the focused Core/presentation and full project gates.
- Task 4 RED: the typed Spending action and opener seam were absent; GREEN: popover,
  Settings, routing, packaging, smoke, and full project tests passed.

### Task 5 acceptance state

- Active documentation states that Cursor usage reads only an existing compatible
  `~/.config/tokscale/cursor-cache/usage.csv`; Needlbar does not create, refresh, or claim
  freshness for it.
- Cursor quota is unavailable inside Needlbar. Settings and the Cursor popover expose one
  typed `Open Cursor Spending` action to exactly `https://cursor.com/dashboard/spending`.
- Needlbar does not use Cursor credentials, browser cookies, private endpoints, or remote
  usage hydration. The one-shot migration removes only the obsolete Needlbar-owned
  `cursor-session.json` file without reading it and preserves the local usage cache.
- Safe existence-only preflight found no obsolete session file and no local cache in the
  acceptance home (`legacy_session_exists=false`, `cursor_cache_exists=false`). No file
  contents, clipboard, cookies, browser storage, or credential material were inspected.
- Fresh `cargo clippy --workspace --all-targets --all-features -- -D warnings`, `make test`,
  `make package`, `make smoke`, and `git diff --check` exited 0. `make test` reported 1372
  pinned-core tests passed with 1 ignored, 128 Swift tests passed, and package-test passed.
- The initial Task 5 run, before `dc7e29a`, recorded the required exact `cargo fmt --check`
  exiting 1 solely on pre-existing formatting differences throughout the non-owned
  `vendor/tokscale-core` submodule. The owned packages passed
  `cargo fmt -p needlbar-bridge -p needlbar-quota -- --check`; the submodule was not changed
  or reverted.
- Packaged-app launch was confirmed. In this GUI session, the LSUIElement status item had no
  Orca-accessible window and the status-bar surface is unavailable to the computer-use
  provider, so a live Settings/popover click-through could not be completed. Structural
  Swift tests passed for Claude/Codex login rows, the Cursor local-cache explanation, the
  single Spending action, no credential controls, both routes, and the exact URL.
- Existence-only post-launch checks remained `legacy_session_exists=false` and
  `cursor_cache_exists=false`; no file contents, clipboard, cookies, browser storage, or
  credential material were inspected. The packaged process was only inspected by exact path
  and was terminated after the smoke attempt.

Task 5's fix round replaces a stale positive `connectCursor` decoding fixture with a generic
future-action unknown-value assertion, so the retired action appears only in approved
historical or redaction-negative records. The workspace formatting boundary now excludes
the vendored path dependency, so literal stable `cargo fmt --check` covers the owned
workspace and passes; tokscale-core remains a pinned transitive dependency and is explicitly
tested and linted through its manifest in Makefile/CI, with no vendor source or revision
change. The live packaged UI was then verified on display 2: Settings showed Claude and Codex rows,
the Cursor local-cache explanation, one Spending button, and no Cursor credential controls;
the Settings action and Cursor popover action each opened the exact
`https://cursor.com/dashboard/spending` URL. Evidence is retained only as the
local-only cropped/redacted `local-only/task5-settings-connections.png` and
`local-only/task5-cursor-popover.png` under the Task 5 SDD directory. Fix-round commit
`dc7e29a44b521fa417b0ca20e5036e9afc2df7e`
passed exact-head CI run [33018740992](https://github.com/taejunoh/needlbar/actions/runs/33018740992),
including owned workspace tests, explicit vendored tokscale-core test and clippy, full
Swift/package verification, and packaged-app smoke checks. The follow-up cleanup restores the
existing CI workspace test's original feature scope while retaining bridge-test runtime
coverage in Makefile and the explicit vendor checks. The live-acceptance commit
`4ec1081ae982e3b03759230ace6ccc38d7e32934` passed exact-head CI run
[33019798610](https://github.com/taejunoh/needlbar/actions/runs/33019798610), with every step
successful, including the packaged visual-acceptance build path. This status-only update
records that completed run/head; any exact-head CI generated for this status-only commit will
be recorded only in the untracked Task 5 report, not through another STATUS commit, with no
tag or release action authorized here.

The follow-up nested-worktree review fix `893309a` excludes the `.worktrees` prefix
from Cargo workspace discovery and verifies the pinned vendor through a portable
detached-worktree helper; no vendor source or revision changed.

### Final whole-branch review and closeout

The final review is clean. Fix `bed1037` makes Cursor `providerUnavailable` render as
unavailable in NeedlbarCore and the bridge, and removes the stale controller copy. Exact-head
CI run [33025188508](https://github.com/taejunoh/needlbar/actions/runs/33025188508) completed
successfully. Independent verification also passed: `cargo fmt --check`, workspace Clippy,
`make test`, `make package`, `make smoke`, and `git diff --check`; the pinned
`tokscale-core` revision remains `53f9eefffd3278fd430076531548f7b1f5861f9a`. A direct
pre-merge vendor-Clippy invocation from this nested worktree can discover the outer Cargo
workspace; fresh-checkout CI vendor Clippy passed, and the portable detached-worktree helper
preserves local verification without changing the vendor.

## Release Validation Continuation — 2026-08-27

Task 5 of tagless release validation is documented and contract-checked. The reusable
fake-tested `scripts/notarize-app.sh` and split `.github/workflows/release.yml`
validate/publish workflow are implemented. Manual dispatch is tagless and produces only an
Actions artifact; `validate` is read-only, while `publish` is write-enabled only for future
`v*` push tags. This implementation did not configure or read a protected GitHub Environment
secret. No real notarization, stapling, Gatekeeper acceptance, merge to `main`, tag, public
GitHub Release, or distribution is claimed here.

The next gate is merge to `main`, authorized protected Environment setup outside chat, then
tagless manual validation. No tag or release action is authorized here. The older credentialed
release and Cursor-session records above remain historical; the active Cursor contract is
local-cache-only and never requests or records a Cursor session token.

## Credentialed Tagless Release Validation — 2026-08-29

This section supersedes the preceding continuation point while preserving it as historical
record. Credentialed tagless release validation is complete against remote `main` head
`eec51a57f9acd23ab238f1d02d546e2e6d568966` (merge commit `eec51a5`, PR #2).

- GitHub Actions Release run [33272883313](https://github.com/taejunoh/needlbar/actions/runs/33272883313)
  was dispatched with `workflow_dispatch` on `main`; it completed successfully, created at
  `2026-08-29T20:12:49Z`, and updated at `2026-08-29T20:24:01Z`.
- The `validate` job succeeded through Swift 6 toolchain selection, complete project
  verification, arm64 packaging, packaged-app smoke, Developer ID signing, Apple
  notarization, stapling, validation/Gatekeeper checks, and artifact upload. The `publish`
  job was skipped as required for tagless dispatch.
- At post-run API verification, artifact `Needlbar-macos-arm64-notarized` was present at
  5,180,723 bytes, was not expired, and was set to expire `2026-11-27T20:12:50Z`. API
  verification after the run reported zero GitHub releases and zero tags.
- Protected GitHub Environment `release` was configured with the six required secret names
  (`DEVELOPER_ID_APPLICATION`, `DEVELOPER_ID_APPLICATION_CERTIFICATE`,
  `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, and
  `APPLE_APP_SPECIFIC_PASSWORD`), without recording values. Required reviewer is `taejunoh`;
  `prevent_self_review` is false, admin bypass is disabled, and deployment policies are
  `main` and `v*`.
- The temporary exported local P12 was deleted after secret setup; the macOS Keychain source
  certificate was retained. No password, certificate bytes, Apple ID, or secret value is
  recorded. No Cursor credential was requested, inspected, or recorded.
- Before this documentation edit, the isolated-worktree baseline
  `source /Users/taejunoh/.cargo/env && cargo build && make test` exited 0: Needlbar Rust
  suites passed, pinned `tokscale-core` reported 1372 passed/0 failed/1 ignored, Swift
  reported 129 passed, and the package relink regression and notarize shell contracts passed.

No tag or public GitHub Release was created. Await explicit user authorization for any
version tag/public GitHub Release; until then do not create/push a tag or publish a release.

## v0.2.1 Widgets and Notifications — W1 Verification — 2026-08-31

Task W1 is complete on the isolated execution branch
`codex/v021-widgets-notifications`. The pure `NeedlbarWidgetSupport` SwiftPM target
contains only Foundation DTOs, the validated 64 KiB projection codec, and the
fixed freshness/current-day/reset display policy. It has no dependency on
`NeedlbarCore` or `CNeedlbar`. Document decoding performs its own nested provider
and allowlisted quota-window validation before aggregate checks.

Focused verification passed:

- `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=WidgetProjectionTests`
  — exit 0; named `WidgetProjectionTests` suite ran 12 tests with 0 failures.

Full verification passed:

- `source /Users/taejunoh/.cargo/env && make test` — exit 0; Rust workspace
  suites passed, pinned `tokscale-core` reported 1372 passed/0 failed/1 ignored,
  Swift reported 169 tests in 3 suites with 0 failures, package relink and
  notarization shell contracts passed.

The native signed macOS 14 arm64 widget acceptance remains an external final
gate. The next continuation point is Task W3: extension target and widget
presentation packaging.

## v0.2.1 Widgets and Notifications — W3 Verification — 2026-08-31

Task W3 is complete on the isolated execution branch
`codex/v021-widgets-notifications`. It adds one separately compiled, sandboxed
`NeedlbarOverview` system-medium WidgetKit extension and a synthetic command
contract that verifies its arm64/macOS 14, Swift 6, WidgetKit, source-boundary,
metadata, and entitlement inputs. The extension reads only the bounded
App-Group `NeedlbarWidgetProjection.json` cache and renders malformed,
unsupported, partial-file, or absent projections as unavailable; it performs no
provider, authentication, bridge, or network work. Today explicitly presents
both completeness and freshness, and lists each displayed contributor's own
timestamp so a newer value cannot hide an older stale contributor.

The host registers only `needlbar://overview`. Its strict handler rejects a
query, path, credentials, port, or fragment and opens the cached Overview
without module activation, refresh, bridge access, or login. If Overview is
disabled, a temporary status item is removed on popover close. No W4 host
embedding or packaging change has been made.

Focused verification passed:

- `bash scripts/tests/widget-extension-tests.sh` — exit 0; exact output
  `widget-extension build/metadata contract passed`.
- `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=MenuBarControllerTests`
  — exit 0; named `MenuBarControllerTests` suite and its selected file ran 11
  tests in 1 suite with 0 failures, including strict deep-link acceptance and
  rejection cases.
- `bash scripts/build-widget-extension.sh` — exit 0; an actual Swift 6.3.3
  compiler invocation used explicit `-swift-version 6` and
  `-target arm64-apple-macosx14.0`, produced an arm64 executable, and ad-hoc
  signed/verified it. The output plist reports minimum system version `14.0`.

Full verification passed:

- `source /Users/taejunoh/.cargo/env && make test` — exit 0; Rust workspace
  suites passed, pinned `tokscale-core` reported 1372 passed/0 failed/1
  ignored, Swift reported 186 tests in 5 suites with 0 failures, and the widget,
  package relink, and notarization shell contracts passed.

This ad-hoc native build and synthetic metadata contract do not prove signed
macOS 14 Widget Gallery or App Group acceptance; that remains Integration Task
1's external gate. The next continuation point is Task W4.

## v0.2.1 Widgets and Notifications — W2 Verification — 2026-08-31

Task W2 is complete on the isolated execution branch
`codex/v021-widgets-notifications`. `NeedlbarCore` now captures bounded,
Gregorian local-day provenance around the existing single usage repository call,
keeps that evidence separate from export capture, and preserves independently
stale last-good usage and quota state. It maps only the sanitized widget DTO,
publishes changed accepted bytes atomically through the existing writer, and
reloads the Overview timeline only after a successful changed write. The host
resolves only its configured App Group identifier and owns publisher start/stop;
the widget support target remains WidgetKit-free. No Rust, C bridge, or v0.2.0
export behavior changed.

Focused verification passed:

- `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=WidgetProjectionTests`
  — exit 0; named Core `WidgetProjectionTests` suite ran 24 tests with 0 failures.
- `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=RefreshCoordinatorTests`
  — exit 0; `RefreshCoordinatorTests` ran 26 tests with 0 failures.
- `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=UsageFileWatcherTests`
  — exit 0; `UsageFileWatcherTests` ran 5 tests with 0 failures after replacing
  bounded-yield fixture polling with deterministic completion evidence.

Full verification passed:

- `source /Users/taejunoh/.cargo/env && make test` — exit 0; Rust workspace and
  package contracts passed, pinned `tokscale-core` reported 1372 passed/0 failed/
  1 ignored, Swift reported 182 tests in 3 suites with 0 failures, and package
  relink and notarization shell contracts passed.

The native signed macOS 14 arm64 widget acceptance remains an external final
gate. The next continuation point is Task W3: extension target and widget
presentation packaging.

## v0.2.1 Widgets and Notifications — Task 4 Native Popover Acceptance — 2026-08-31

Task 4's current-host native acceptance was run by the primary agent against the exact
Developer ID-signed candidate
`.superpowers/native-validation/menu-panel.x6vzf2n2yv/Needlbar.app`, with host PID `32737`
confirmed healthy and running from that exact executable path. The candidate had already
passed the fresh full gates and strict nested code-signature verification recorded in the
Task 4 evidence report.

The AppKit display evidence recorded:

- Primary screen frame `(0, 0, 1512, 982)` and visible frame `(0, 0, 1512, 949)`.
- Secondary screen frame `(-503, 982, 2560, 1440)` and the same visible frame.
- On the secondary display, custom panel CoreGraphics bounds `X=1019, Y=-1410, W=300,
  H=353`; converted placement stayed within the visible frame and was centered under the
  clicked status-item anchor when not edge-clamped.
- The retained crop
  `.superpowers/native-validation/menu-panel.x6vzf2n2yv/panel-position-crop.png` shows the
  menu bar ending at approximately 60 px at 2x scale, the panel beginning near y=61, centered
  under the second AI status icon, with no native popover arrow/glass overlap.

Direct native interactions verified:

- Clicking Settings dismissed the panel and opened the Needlbar Settings window.
- Clicking the external SecurityAgent Deny control dismissed the panel.
- A same-app outside interaction dismissed once, but its synthetic click reported
  `unverified/window_not_focused`; no stronger same-app outside-click claim is made.
- Direct native Escape injection was not possible because the nonactivating panel could not be
  focused. Escape behavior remains covered by automated tests only and is not claimed as a
  native result.

This evidence disproves the prior hypothesis that the panel's native popover behavior was
accepted without an outside-click dismissal path. It confirms current-host positioning and
selected dismissal behavior, but does not establish installed-widget rendering/readback,
WidgetKit App Group lifecycle, deep-link/quit/reset/midnight behavior, notification delivery or
remaining permission cases, same-app outside-click behavior beyond the bounded observation,
native Escape, or macOS 14 arm64 compatibility. No tag, push, release upload, or Apple portal
mutation was performed.

The exact command exits, test counts, signing identity hash, bundle/executable paths, and
candidate evidence are retained in
`.superpowers/sdd/2026-08-31-needlbar-v0.2.1-popover-anchor-fix/task-4-report.md`.

## v0.2.1 Widgets and Notifications — Task 4 Final Review Follow-up — 2026-08-31

The final read-only review closed the P1/P3 findings with focused fix commit `dd426ab`
(`fix: guard stale menu panel dismissals`). `AppKitMenuPanelPresenter` now owns a monotonically
increasing presentation generation and captures it in each locally queued dismissal callback;
callbacks from an older presentation cannot dismiss or invoke `onDismiss` for a newer panel.
`StatusItemPresentationAnchor` derives `Equatable`, preserving a direct value-equality contract
for its button and visible-screen frames. The read-only re-review found no new P0–P2 findings.

The previously noted P2 deinit concern is withdrawn as an open finding. Explicit
`MenuBarController.stopObserving` teardown is invoked from both application termination paths and
cancels the presenter token on the main actor. A direct ordinary `deinit` cancellation probe was
rejected by Swift 6's actor isolation (`@MainActor` token cancellation from a synchronous
nonisolated deinitializer), so no `nonisolated(unsafe)` or compiler-baseline-risky workaround was
introduced.

Fresh final verification recorded by the primary agent:

- `source /Users/taejunoh/.cargo/env && make test` — exit 0; Rust workspace green, pinned
  `tokscale-core` 1372 passed / 0 failed / 1 ignored, Swift 245 tests in 11 suites passed, and
  widget-extension, package relink, and notarization shell contracts passed.
- Known linker warnings only: Rust objects built for macOS 26.5 were linked against the macOS
  14.0 deployment target; no test or gate failure resulted.
- `git diff --check` is the root agent's final verification step for this documentation pass.

Native caveats remain truthful: macOS 14 arm64 acceptance is unavailable on this macOS 26 host,
and direct native Escape injection was not accepted because the nonactivating panel could not be
focused. Automated Escape coverage remains green; it is not a native Escape claim.

## v0.2.1 Widgets and Notifications — Final Exact-Source Native Candidate — 2026-08-31

The final native evidence supersedes the earlier candidate path: source HEAD `dd426ab` was
packaged and signed as
`.superpowers/native-validation/final.Nb2q75/Needlbar.app`. PID `54409` remained alive from the
exact host executable path. The candidate uses App Group
`3BMF4LM6TM.com.taejunoh.needlbar`, extension-first Developer ID hardened-runtime signing with
`--timestamp=none`, and strict nested code-signature verification exited 0. The exact widget
extension registration listed one plug-in at the final candidate path. `open needlbar://overview`
exited 0; this command result does not claim a visual deep-link outcome.

The primary agent directly inspected the final screenshot
`.superpowers/native-validation/final.Nb2q75/panel-position-crop.png`. On the secondary display,
the AppKit screen frame was `(-503, 982, 2560, 1440)` and the custom panel CoreGraphics bounds
were `X=972, Y=-1410, W=300, H=353`. The visual evidence shows the menu bar bottom at 60 px and
the panel beginning immediately below near y=61 px at 2x scale, horizontally centered beneath the
second `AI —` status item, with no native arrow/glass overlap.

This final exact-source evidence confirms the bounded current-host panel placement and final
candidate signature/registration. macOS 14 arm64 acceptance remains unavailable. Final native
Escape and outside-click behavior are not newly claimed here; earlier external-system dismissal
evidence remains labeled only at its previously verified scope.

## v0.1 Constraints to Preserve

- macOS 14+.
- Apple Silicon first.
- Exactly Claude Code, Codex, and Cursor.
- Swift/AppKit owns the shell and presentation.
- `NeedlbarCore` owns normalized state, refresh scheduling, and last-known-good behavior.
- `tokscale-core` owns usage discovery/parsing/deduplication/aggregation/pricing.
- Cursor usage has no Needlbar-owned hydration layer; the pinned engine reads an existing
  local compatible cache only.
- `needlbar-quota` owns quota/auth/reset logic only.
- Usage and quota failures must not erase each other's valid last-known-good values.
- No backend/account system/telemetry or prompt/response/source-code upload.
- No extra v0.1 providers or opportunistic feature expansion.

## Status Update Rule

Whenever work moves forward, update this file with:

- completed task/step,
- verification commands and result,
- current CI state,
- any deliberate deviation from the approved plan,
- exact next continuation point.
