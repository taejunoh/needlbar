# Disk Settings Information

Date: 2026-09-30
Scope: Settings → SYSTEM → Disk only
State: User approved the written design (capacity + read/write).

## Intent and approved scope

Continue the CPU and RAM Settings improvements with a compact, read-only Disk
information card. Reuse the approved native card and existing update stream;
there is no new layout-choice question or browser mockup needed for this step.
The user chose capacity plus read/write information over capacity-only and
SMART/lifetime expansion.

Show the system volume name, total volume capacity, used and available space,
used percentage, read/write rates, and successful sample date/time. Reuse the
existing root-volume and backing-device queries. Do not add SMART, lifetime,
temperature, SSD model/interface claims, external-volume selection, process
I/O, history graphs, manual refresh, or new settings.

## Screen contract

Preserve the Disk sidebar page, title, Menu bar / Dashboard / Alerts picker,
and existing controls. Mount one `Disk information` section below the picker
and above surface-specific controls on all three Disk tabs, not other pages.

- Identify the monitored scope as `System volume (/)`, with its display name.
  The volume name is not a device model or stable disk identifier.
- Show an explicitly labeled Total and prominent cyan used percentage.
  A compact cyan Used-versus-Available bar labels both values. Do not label
  Available as raw unallocated physical-device space.
- Group Read and Write rates compactly: blue Read, orange Write, with text
  labels and monospaced values. Use binary byte/rate units consistently with
  the existing dashboard. An actual zero remains `0 B/s`; unknown is `—`.
- Show a localized successful sample date and time. Stale dynamics, including
  rates, are explicitly Last known. Missing usable activity shows unavailable,
  not a supposed successful observation time.
- Include one short explanatory line: capacity describes the system volume;
  I/O describes its backing device and may include other volumes' activity.

Use native light/dark styling and accessible labels/values, not color alone.
Long volume names wrap without squeezing numeric values out of the minimum
Settings window. Detail rows wrap or become vertical where required. Preserve
the existing unsupported-system-threshold explanation on Alerts. Do not infer
drive health or create warning thresholds from space percentage.

## Data definitions and minimal Core changes

`SystemMetricsSnapshot.DiskVolume` already carries name, Used, Available
(`freeBytes`), Read bytes/second, and Write bytes/second. Add one independently
optional `totalBytes: UInt64?` with a trailing initializer argument defaulted
to nil. Existing callers and fixtures remain source compatible. There is no
Codable/wire-format or Rust bridge change.

The native collector already reads `.volumeNameKey`, `.volumeTotalCapacityKey`,
and `.volumeAvailableCapacityKey` together for `/`. Retain the actual Total
from that read; do not query twice or manufacture Total from Used + Available
in older snapshots. These are volume-capacity values, not physical SSD size.
APFS/shared-storage semantics need not match a physical-device allocation view.

Use a small pure capacity-normalization seam, tested independently of native
queries. Validate signed values before conversion: positive total, nonnegative
available, and available no greater than total. Then Used = Total − Available
with exact integer arithmetic. Missing, zero-total, negative, or inconsistent
inputs are unavailable; remove the current negative/excess-available clamp
that can manufacture a real-looking zero Used value. Keep a failed native
capacity read as an empty disk array, rather than introducing partial native
records or changing module availability. Native disk availability remains
fresh for a valid capacity record even when one or both I/O rates are unknown.

Keep the existing IORegistry counter query, elapsed-time conversion, service
loop, module availability policy, and counter-baseline behavior unchanged.
The rates are differences of backing `IOBlockStorageDriver` counters, not
guaranteed root-volume-only traffic. Nil rates can mean first sample, reset,
missing counters, or failure; do not claim a specific warmup/error cause or
show nil as zero. Each direction is independently optional.

Definitions were checked against the local SDK's Foundation `NSURL.h` volume
capacity keys and IOKit `IOBlockStorageDriver.h` counter definitions. Existing
source-ID and counter-gap policies are not being redesigned in this task.

## Presentation, freshness, and failure boundaries

A focused Disk presentation owns one published derived value, updated from
the existing `CombinedUsageSnapshot` delivered to `SettingsWindowController`.
Inject it through default-compatible Settings initializers beside CPU/RAM.
No UI last-known cache, additional collector, timer, task, network request,
credential access, process scan, or provider refresh is permitted.

Use the first disk record under the existing single-root-volume contract;
do not search by name, select the largest volume, or invent selection state.
Trim its display name; empty or control-character-containing labels use
`System volume`. Invalid names do not invalidate otherwise usable values.
If the record disappears, its name and Total also disappear. An unavailable
record may retain only valid name and positive Total from that input record,
never metadata recovered from a separate presentation cache.

Dynamic values require `.fresh` or `.stale(lastSuccessfulAt:)` Disk
availability and present Used (including zero), no greater than known Total.
An explicitly zero Total is invalid capacity and suppresses dynamics; it is
not the same as an old snapshot omitting Total. Invalid individual Available
exceeding known Total becomes unknown and does not fabricate a percentage.
Missing optional rates do not invalidate
valid capacity; unsupported rates remain unknown independently.

Calculate percentage only from overflow-safe Used + Available > 0. If Total
is present, both values must be bounded by it and their sum must equal it.
Otherwise show no percentage/bar. An older record with no Total can show a
valid percentage from its checked sum, but Total stays unknown. Never clamp
inconsistent raw capacity into a percentage or physical-capacity estimate.

Fresh time comes from Disk availability's successful captured time; stale
time comes from lastSuccessfulAt, not the combined snapshot's failed attempt.
Unavailable/missing availability, missing record, or unusable Used clears
Used, Available, percentage, both rates, and successful date even if an orphan
payload remains. Data-less stale availability must not establish success.
Disabling Disk visibility on either surface does not erase its Settings card.

The existing service can assign a fallback stale date after an unavailable
sample. The presentation's usable-data guard prevents that orphan date from
being shown. Do not broaden this task into a global stale-service-policy fix.

## Verification and exclusions

Use test-first checks for initializer compatibility; signed capacity nil,
zero, negative, excess available, valid zero Used/Available; exact Total and
subtraction; and forwarding through the existing collector/service path.
Service failure tests distinguish successful and failed times and preserve
the full disk record including Total.

Presentation tests cover fresh/stale dates, cross-day rendering, old no-Total
records, explicit zero Total, nil/overflow/inconsistent capacity, rates that
are zero/nil/one-sided, unavailable/missing availability/orphan transitions,
missing volume, long/invalid names, and visibility-off controller updates.
Verify Disk-only placement and unchanged CPU/RAM pages and controls.

Use the existing guarded native Settings review executable with inert Disk
fixtures and isolated defaults, not live collection or a new app bundle.
Inspect light 960×720 and dark minimum 760×560 content windows, all three tabs,
visibility-off retention, wrapping, and supported accessibility output.
Run focused tests, independent spec and quality reviews, and full `make test`.
Report actual evidence and distinguish fixture rendering from installed-app,
VoiceOver, macOS 14 hardware, and injected native-query validation.

The previously identified shared transfer-rate floating-point boundary issue
is independent of this Settings card. Do not silently change shared conversion
or counter identity semantics in this task; record rather than claim repair.

## Branch and continuation

Local branch `codex/disk-settings-information` reuses the existing clean
attached worktree from RAM head `7546602`, avoiding additional folders/apps.
CPU PR #10 and RAM PR #11 remain separate and unchanged. They are explicit
dependencies of later Disk integration; do not merge, retarget, push, release,
reinstall, or create a persistent app bundle in this design step.

After the user reviews this written spec, prepare the Disk-only test-first
plan with bounded Core/Settings ownership. Execute sequentially with reviews
and final verification; update STATUS with results and the next continuation.
