# Needlbar Settings Module Studio Design

**Status:** Visual design approved; written specification awaiting user review.
**Date:** 2026-09-05
**Scope:** Rework native Settings around the approved Module Studio visual direction and add independently persisted menu-bar and dashboard visibility. This does not approve every Stats-like mockup proposal.

## 1. Authority and outcome

The approved visual direction is the revised Module Studio mockup, archived at:
`docs/superpowers/mockups/2026-09-05-settings-module-studio.html`
Its sidebar, larger module hierarchy, visual display-style strip, surface tabs,
and full-width aligned rows are the intended visual language. The mockup uses
sample values and labels some functionality as new work. It is not a runnable
product contract by itself.
This design makes two commitments:

1. Settings becomes a native, resizable Module Studio with a sidebar and one
   selected detail pane.
2. Visibility is independent for the menu bar and dashboard, for both system
   modules and AI providers.
All other proposed controls are explicitly phased below. Shipped Settings must
never display a button, picker, tab, or switch as functional when its backing
contract has not been implemented.
This design supersedes only Settings information architecture and visibility
ownership. It preserves the current provider, collection, privacy, export,
notification, panel, and presentation responsibilities unless a later approved
feature specification says otherwise.
## 2. Native window and hierarchy

The default Settings window is resizable at 960 × 720 points with a 760 × 560 minimum. Its maximum size is clamped to the available screen frame and never opens off-screen. At the minimum, sidebar/detail scrolling preserves native usable control sizes.
The sidebar contains these fixed groups:

| Group | Entries | Phase 1 content |
| --- | --- | --- |
| Layout | Menu bar & dashboard | shared order, per-surface visibility, read-only composition preview |
| System | CPU, RAM, Disk, Network, Battery | each module's per-surface visibility; Network also owns existing IP controls |
| AI providers | Claude, Codex, Cursor | per-surface visibility, shared metric, current connection/action state |
| Preferences | Notifications, Data & Privacy | existing global quota alerts; existing snapshot export and privacy copy |
There is no GPU, Sensors, Bluetooth, Clock, Remote, fan, process, or general
app-settings page in Phase 1. Those exist in reference applications, not in the
current Needlbar product contract.
Each detail pane has an eyebrow, a 24-point title, concise supporting copy, and
full-width aligned setting rows. Primary setting labels use 17-point text and
secondary explanatory text is visually subordinate. The layout page has a
compact visual strip for the current two-line menu-bar composition. That strip
is a read-only preview, not a second configurable widget surface or a style
picker.
## 3. Surface tabs and navigation behavior

System and provider pages expose exactly one selected surface tab at a time:
**Menu bar**, **Dashboard**, or **Alerts**. The active tab must change its
content, not merely its visual selected state.

- **Menu bar** shows that item's menu-bar visibility and the information needed
  to understand its current menu representation.
- **Dashboard** shows that item's dashboard visibility and the information
  needed to understand its dashboard representation.
- **Alerts** contains only existing alert behavior applicable to that item. In
  Phase 1, system modules and providers have no individual alert preference;
  system Alerts explains that system-threshold alerts are not available yet;
  provider Alerts points to the existing global quota setting in Notifications.
  It must not mutate dashboard visibility
  or appear to configure thresholds.
Notifications and Data & Privacy are not surface-specific pages and therefore
do not show surface tabs. Layout may show Menu bar and Dashboard only; it does
not expose an Alerts tab.
Keyboard focus moves predictably between sidebar, tabs, rows, and controls.
The sidebar selection has an accessible current-page value; tabs expose their
selected state and the matching content; switches and drag/reorder controls
have descriptive accessibility labels. The visual preview is ignored by
accessibility when it duplicates the adjacent textual setting summary.
## 4. Phase 1 executable contract

### 4.1 Shared order and independent visibility

System module order remains one ordered permutation of CPU, RAM, Disk, Network,
Battery, and AI. Provider order remains one ordered permutation of Claude,
Codex, and Cursor. Both orders are shared by menu-bar and dashboard rendering.
Phase 1 does not add independent order lists.
Each system module has two independent booleans:

- menu-bar visible;
- dashboard visible.
Each provider has two independent booleans with the same meaning. A provider's
selected display metric remains shared by both surfaces: `Remaining`, `Usage`,
`Cost`, or `Connection`. Hiding an item changes only its selected presentation
surface; it does not turn off collection, discard last-known-good data, alter
provider ordering, or alter the shared display metric.
The menu-bar renderer consumes only menu-bar-visible module/provider values.
The dashboard presentation consumes only dashboard-visible module/provider
values. Both continue to apply the one shared valid order. If all dashboard AI
providers are hidden while the AI module remains dashboard-visible, the existing
empty-state copy remains available; it must not substitute a different provider
or a token value.
### 4.2 Existing controls retained

The following controls move into the Module Studio but retain their current
behavior and wording where accurate:

- Layout: module/provider ordering and **Use compact defaults**.
- Network: local-IP display and public-IP display.
- Claude and Codex: provider-owned browser sign-in and live login state.
- Cursor: existing local-usage explanation and **Open Cursor Spending** only.
- Notifications: the existing one global quota-threshold-alert preference and
  macOS authorization status.
- Data & Privacy: user-initiated snapshot export and its success/failure state.
The compact-default action applies only to the surface currently selected in
Layout. It sets that surface's system visible set to CPU, RAM, and AI. It does
not change the other surface, either order, provider preferences, local/public
IP settings, alert preference, or provider authentication state.
Network remains the only Phase 1 system detail page with additional existing
controls. Local IP remains display-only in the dashboard. Public IP remains off
by default, uses the current fixed endpoint/cache/timeout behavior, and is not
exported, logged, or sent to a provider.
### 4.3 Preview and presentation updates

The Layout preview derives solely from the current combined snapshot, canonical
configuration, and existing two-line menu-bar renderer output. It performs no
provider refresh, system collection, network request, timer, separate cache, or
layout persistence. A missing or unavailable value is displayed using the
existing neutral representation. Phase 1 contains no graph, bar, ring, or other
style-choice controls.
Configuration writes continue to use the existing configuration-change
notification. The open dashboard and status item reconcile through their
existing update path; a visibility change may trigger the existing in-place
dashboard height measurement/resizing behavior, but must not replace the panel,
restart a refresh, reset scroll/disclosure state, or alter anchoring/dismissal.
## 5. Configuration migration and persistence

`SystemMonitorConfiguration` becomes the canonical home of two system visible
sets and two provider-visible flags. The names may be implementation-specific,
but their meaning is fixed by this specification:

| Value | New UserDefaults key family | Legacy source when new key is absent |
| --- | --- | --- |
| System menu-bar visibility | `needlbar.systemMonitor.menuBar.visible` | `needlbar.systemMonitor.visible` |
| System dashboard visibility | `needlbar.systemMonitor.dashboard.visible` | `needlbar.systemMonitor.visible` |
| Provider menu-bar visibility | `needlbar.systemMonitor.ai.<provider>.menuBar.visible` | `needlbar.systemMonitor.ai.<provider>.visible` |
| Provider dashboard visibility | `needlbar.systemMonitor.ai.<provider>.dashboard.visible` | `needlbar.systemMonitor.ai.<provider>.visible` |
For an existing installation, an absent new key derives its value from the
matching valid legacy shared value. Thus the first new build preserves the
current result on both surfaces. A configuration getter is read-only: it must
not write defaults, erase legacy values, or post notifications while deriving
fallbacks. The next explicit configuration setter writes all canonical new
keys.
Legacy shared keys remain untouched as migration sources. Divergent new values
cannot be represented by an older shared-visibility build; downgrade behavior
after divergence is unsupported and must not drive an ambiguous mirror value.
For a fresh install, both surfaces use today's default system visible set
`[CPU, RAM, AI]`; all three providers are visible on both surfaces; provider
metric defaults to `Remaining`; both IP flags remain off; and canonical order
is unchanged. An all-dashboard default is deliberately not introduced by this
design because it would change initial panel density and current expectations.
Invalid, duplicate, or incomplete order values still fall back to canonical
order. Invalid module identifiers are discarded from a visible set; a missing
or malformed new visible-set key follows its legacy source, then the fresh
default if the legacy source is also absent or malformed. A missing provider
flag, or a value that is not a stored Boolean, follows the matching valid legacy
provider flag, then its fresh default. An empty valid visible-set array means
hide all; it must not be mistaken for a missing key. Invalid
provider metrics continue to fall back to `Remaining`.
## 6. Collection, alerts, and safety invariants

Visibility must not affect collection or scheduling:

- `SystemMetricsService` retains its one-second collection loop.
- `RefreshCoordinator`, usage watcher, provider quota refreshes, and manual
  refresh retain their current scheduling and provider ownership.
- Opening Settings or changing a visibility flag does not authenticate, launch
  a browser, refresh data, request public IP, or create a new timer.
- The configuration observer continues to pass only the existing public-IP flag
  to the system service.
Quota alerts remain global, opt-in, and limited to the existing eligible fresh
Claude/Codex quota samples. Hiding any module or provider does not stop alert
evaluation, alter its ledger, request permission, or create a system metric
alert. Provider sign-in stays provider-owned: Claude/Codex retain their
browser/CLI handoff; Cursor retains no Needlbar credential/login flow and opens
only its provider Spending destination.
Native Claude, OpenAI Blossom/Codex, and Cursor brand assets remain present and
retain their existing decorative/accessibility semantics. Settings must not show
credentials, raw provider payloads, account identifiers, IP addresses, source
paths, raw diagnostics, or error details. Existing user-safe freshness,
unavailable, authentication-required, and export/login failure states remain
visible and actionable through their present actions.
## 7. Explicitly phased new functionality

The mockup's deeper controls are visual proposals. They are not enabled in
Phase 1 and must not be shipped as disabled-looking but otherwise interactive
controls, deceptive values, or placeholder settings.

| Proposed function | Why it is new | Required separate approved specification before implementation |
| --- | --- | --- |
| Graph, bars, ring, or style selection | Requires menu/dashboard rendering contracts and appearance/accessibility fallback | style values, rendering ownership, preview/real parity, migration, and visual acceptance |
| Unit preferences | Changes formatting semantics | supported units, scope by metric, persistence, localization, and regression values |
| Disk selection | Changes which collected volume represents Disk | selection identifier, removal/unavailable behavior, collector/presentation contract, and migration |
| Network interface selection | Changes counter source and IP relationship | interface matching, reset/warmup/error/privacy behavior, collector contract, and tests |
| Per-module intervals | Changes collection scheduling and energy behavior | scheduling ownership, bounds/coalescing, lifecycle, and no provider-refresh amplification |
| System/module alerts | Adds notification policy and permission/ledger behavior | eligibility, thresholds, de-duplication/rearm, privacy copy, lifecycle races, and native permission acceptance |
The recommended delivery sequence is Phase 1 Settings/visibility, Phase 2 styles
and units, Phase 3 disk/interface selection, then sampling intervals and system
alerts as separate bounded stages. This preserves the feature-expansion
direction instead of treating Phase 1 as the finished Stats replacement.
Each later stage requires its own detailed contract and verification plan;
the visual approval does not settle its missing behavioral requirements.
## 8. Component boundaries

Do not turn `SettingsView` into one giant sidebar, preview, navigation, and
provider-action implementation. The production decomposition must keep:

- a small Settings shell/window and selected-page navigation state;
- a configuration-backed model that validates and commits surface-specific
  visibility, shared order, provider metric, and existing IP values;
- focused reusable native row/section/preview views with no persistence or
  refresh ownership;
- provider connection/export action state in the existing `SettingsActions`;
  and
- alert preference state/service in the existing notification types.
AppKit continues to own the window. SwiftUI owns Settings layout. NeedlbarCore
owns canonical configuration and normalized snapshot state. System collection
and provider refresh remain outside Settings. Rust and the C bridge gain no
Settings presentation or visibility responsibility.
## 9. Verification contract for Phase 1

Focused automated coverage must prove:

1. legacy shared visibility migrates independently to both surfaces without
   getter writes; partial/corrupt new keys take the specified fallback;
2. fresh defaults, invalid metric fallback, canonical-order fallback, and shared
   order persist deterministically;
3. a system/provider change affects only its chosen surface; shared metric and
   order remain unchanged;
4. compact defaults affect only the selected surface and preserve provider
   preferences, order, and IP flags;
5. menu renderer and dashboard presentation filter the correct independent
   visibility values; unavailable data keeps existing neutral/error behavior;
6. a visible open dashboard remeasures/resizes through the existing callback
   without a new panel, anchor change, refresh, or scroll reset;
7. Network IP controls, provider actions/login states, Cursor Spending action,
   export states, and global notification preference preserve their current
   behavior; and
8. every exposed Phase 1 control writes or invokes a real supported contract;
   no mockup-only badge, sample value, or placeholder control ships.

Run focused configuration, renderer, dashboard, and Settings tests while
developing, then require `make test` to exit cleanly before implementation is
considered complete. Preserve the pinned submodule revision and unrelated local
changes; a dirty vendor checkout must not be silently reset to obtain a green run.

Native acceptance must inspect the exact development bundle at default and
minimum window sizes, window resizing/screen clamping, sidebar and keyboard
navigation, tab-content changes, explicit reorder affordances, light/dark
appearance, independent surface visibility, preview/error states, and existing
provider/export/notification actions without recording credentials or private
data. Prefer isolated fixture-backed state and action-routing checks; actual
sign-in, permissions, and account-affecting actions require explicit user scope.
Unsupported proposed features must be absent, not silently claimed as
working.
## 10. Out of scope and release state

Phase 1 does not alter release packaging, deployment targets, widget behavior,
analytics, JSON export schema, provider set, bridge ABI, dashboard width,
outside-click dismissal, or native macOS 14 acceptance status. It adds no new
provider, credential storage, telemetry, cloud sync, external endpoint, or
background history database.
No release, publish, signing, notarization, or release-readiness claim follows. The next step after user review is a scoped implementation plan naming production files, migrations, tests, native acceptance, and the first independent task.
