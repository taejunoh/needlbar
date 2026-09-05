# Settings UI Review — 2026-09-05

**Status: Revised visual mockup and independent visibility approved; written design under review.**

This note records a read-only comparison of Settings information architecture.
It is not a product specification, implementation plan, or approval to change
Needlbar behavior.

## Evidence reviewed

### Stats 3.0.14 (native, read-only)

All sidebar entries were opened and observed without changing a switch, picker,
or saved setting; the app was returned to its original GPU-details screen.

- Sidebar: Dashboard, CPU, GPU, RAM, Disk, Sensors, Network, Battery,
  Bluetooth, Clock, Remote, plus bottom-level app Settings.
- CPU/GPU/RAM/Disk/Network initially show gauges and history; their toolbar
  gear opens configuration. CPU configuration has Module, Widgets, Popup, and
  Notifications tabs. Its Module tab exposes intervals and top-process count;
  Widgets exposes a selected mini preview plus label, color, and alignment;
  Popup exposes shortcut, colors, and history; disabled notification thresholds
  are visibly unavailable.
- RAM includes combined-process options. Disk exposes interval, disk selector,
  removable-media, and SMART controls. Network exposes reader/interface,
  byte units, reset, public IP, refresh, threshold, and connectivity controls.
- Battery offers process/time formatting, widget preview/additional-info,
  hide-when-full, colorization, XL, and charger-state options. Sensors has
  categorized sensor toggles and fan options. Bluetooth showed an explicit
  no-devices empty state; Clock has an editable time-zone table; Remote shows
  a sign-in introduction (no login was initiated).
- App Settings groups update/general controls, combined-modules icon-strip
  order, spacing, separator, combined details, and export/import/reset. None
  of those actions was invoked.

### External documentation (read-only)

- [Stats upstream README](https://github.com/exelban/stats/blob/master/README.md?plain=1)
  contains official menu-bar and popup screenshots. It documents system modules
  and states that macOS menu-bar ordering uses Command-drag, not Stats-owned
  ordering.
- [iStat Menus official help](https://bjango.com/help/istatmenus7/welcome/)
  and its [Global-tab screenshot](https://bjango.com/images/help/istatmenus7/welcome-global.jpg)
  show a sidebar/global structure. The help describes global appearance,
  refresh, and spacing settings; per-item enablement; Command-drag ordering;
  and adding/removing visual elements inside an item.
- [CodexBar documentation](https://github.com/steipete/CodexBar) was read only:
  it documents per-provider enablement/source under Settings > Providers. No
  native CodexBar UI was observed. Neither CodexBar nor iStat Menus is proven
  to have been an initial Needlbar reference.

## Current Needlbar Settings inventory

The current window is a 540 × 720 `NSWindow`; its grouped SwiftUI `Form` has a
520-point content width. Its sections are, in order:

1. **Menu bar modules** — CPU, RAM, Disk, Network, Battery, and AI usage:
   visibility toggle and drag ordering; **Use compact defaults** makes only
   CPU/RAM/AI visible without changing provider preferences; independent local
   and public-IP toggles.
2. **AI provider display** — Claude, Codex, Cursor: per-provider visibility,
   drag ordering, and `Usage` / `Remaining` / `Cost` / `Connection` picker.
   New or invalid stored choices default to `Remaining`.
3. **Connections** — provider-owned Claude/Codex browser sign-in actions and
   states; Cursor has no credential field and offers **Open Cursor Spending**.
4. **Data Export** — user-initiated snapshot export with success/failure state.
5. **Notifications** — quota-threshold-alert toggle and macOS authorization
   status copy.

The current module visibility setting is shared: it controls both menu-bar
space and dashboard-popover rows. It is persisted with module/provider order,
IP flags, and provider display preferences. Current UI does not expose the
legacy provider-module configuration as separate controls.

## Research direction

The observed configuration density suggests a **hybrid grouped sidebar** as the
smallest coherent direction to assess:

- a sidebar with Menu & dashboard, system modules, individual AI providers,
  Notifications, and Data & Privacy, with a single selected detail pane;
- a small top preview of the current menu-bar composition where relevant;
- explicit drag handles for ordering rather than relying only on instructional
  copy; and
- Network/IP in Network; AI display and connection status together in the AI
  detail pane; Alerts and Data as distinct pages.

This is a research recommendation, not a commitment to copy Stats or iStat
Menus. Needlbar currently has a smaller supported setting surface; a full
Stats-style, per-module editor would be high-scope and sparse, while light
category tabs would be lower-scope but leave cross-category relationships less
visible. The hybrid sidebar best matches the current settings density while
leaving room for explicit descriptions and previews.

## Approved direction and constraints to preserve during evaluation

The user approved independent **menu-bar visibility** and **dashboard
visibility** for modules and AI providers. The visual mockup uses shared order
and provider metrics across the two surfaces; its example configuration is not
a change to new-install defaults. Provider display and connection controls
belong on the same page, without a redundant Connections page.
Evaluation should also preserve the current
meaning of provider-owned sign-in, Cursor's no-credential workflow, explicit
public-IP opt-in, and the existing immediate local persistence of settings.

No current Needlbar UI provides a full Stats-like editor for graphs, colors,
module-specific intervals, sensors, GPU, fan control, history databases,
import/reset, or per-module notifications. Those should not be described as
existing Needlbar functionality.

The interactive mockup is stored at
`.superpowers/brainstorm/99304-1788644733/content/settings-sidebar-preview.html`.
It uses example data only and does not change app preferences or access accounts.
Production implementation and migration details still require a design and plan.

## Visual revision after Stats comparison

The user rejected the first mockup as too different from Stats and approved a
revised design direction: larger module headings, a visual display-style strip,
Menu bar / Dashboard / Alerts tabs, and full-width aligned setting rows. The
revision is a feature-expansion concept, not approval that all Stats features
are implemented or committed to the next release. Proposed controls must be
marked as requiring new development.

- Existing capabilities to preserve: module/provider ordering, provider display
  metrics, local/public-IP flags, provider-owned sign-in, Cursor Spending,
  global quota alerts, and snapshot export.
- Approved new behavior under design: independent menu/dashboard visibility.
- Further proposed features: selectable graph/bar/ring styles, unit preferences,
  disk/interface selection, per-module sampling intervals, and system alerts.
  These need separate rendering, persistence, availability, scheduling, and
  notification contracts rather than settings controls alone.

Revised visual artifact:
`.superpowers/brainstorm/99304-1788644733/content/settings-module-studio-v2.html`.
The approved revision is archived at
`docs/superpowers/mockups/2026-09-05-settings-module-studio.html`.

Visibility must remain independent of collection and alert evaluation. The
current one-second system sampling loop and separate provider refresh schedule
are not changed by this mockup. No real settings, credentials, or network
requests are involved in preview interactions.

## Source locations

- `Sources/Needlbar/Settings/SettingsView.swift:48-92`
- `Sources/Needlbar/Settings/SystemMonitorSettingsView.swift:122-193`
- `Sources/Needlbar/Settings/SettingsWindowController.swift:14-29`
- `Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift:69-110`
- `Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift:151-177`
