# Network Settings Information

Date: 2026-09-30
Scope: Settings → SYSTEM → Network
State: Written specification approved by the user. Cumulative traffic and
per-interface speeds excluded.

## Intent and chosen approach

Continue the CPU, RAM and Disk read-only Settings cards using the same native
layout and existing snapshot stream. The user considered a rates-only card
and fuller Network details, then approved the reduced expansion: Download,
Upload, interface list, and IP addresses when their existing options are on.
This reuses the current collection and adds only interface-name retention.
It does not implement cumulative usage, per-interface rates, interface
selection, Wi-Fi SSID, MAC addresses, link speed, connection-type detection,
latency checks, connectivity tests or connection-health warnings.

Reuse the approved card styling; no new visual-layout choice or browser
companion is needed for this information-scope decision.

## Screen contract

Mount one `Network information` section below the Settings surface picker and
above existing controls on all three Network tabs. Preserve the sidebar,
Menu bar / Dashboard / Alerts picker, visibility toggles, existing independent
local/public IP options and unsupported-system-threshold explanation.
Other module pages keep their own cards and never show this card.

- Prominent labeled Download in blue and Upload in orange, using monospaced
  binary byte-rate units. Real zero is `0 B/s`; unknown is `—`. Color is not
  the only distinction. No percentage, fabricated speed capacity or graph.
- A compact wrapped list titled `Reported interface names`, such as en0 or
  utun3. Do not relabel these as Wi-Fi, active, primary or connected devices.
  The list is not guaranteed to enumerate every counter contributing to rates.
- A full localized successful traffic date/time, specifically labeled
  `Traffic sampled` or `Last known traffic`, not a successful observation
  date for every field in the card.
- One short scope explanation: `Combined traffic across reported network
  interfaces. May include loopback and VPN traffic.` This is not an Internet
  bandwidth test, ISP usage measurement or deduplicated transmission count.
- On the Dashboard tab only, show Local IP and Public IP independently when
  their existing options are enabled. Hide each row immediately when its
  option is disabled, even while the previous snapshot retains its value.
  Menu bar and Alerts tabs never display either IP row, including with flags on.
- When an IP row is enabled but lacks a usable address, show `—`, not a
  disabled-looking option or implied successful lookup. Public IP may be cached;
  explain the existing cache without inventing its lookup timestamp.

Native light/dark, minimum 760×560 Settings content size and wrapped interface
lists must fit without horizontal clipping; longer content uses the existing
detail scroll area rather than a fixed-height card. IP identifiers use monospaced text
and may middle-truncate where needed, with the complete value in help and
accessibility. Download/Upload labels, rates, interface names, IP values and
Last known semantics have explicit accessibility text.

## Privacy and existing IP policy

The v0.3 system-monitor spec remains authoritative: IPs are in memory for
display only, never persisted in logs, exports, analytics or provider payloads.
Use inert documentation/test addresses in review fixtures and captures.
Do not inspect, record or export the user's real IPs during verification.

The user-approved opt-in Network Dashboard IP rows are a narrow exception to
the earlier Settings Studio phase-1 ban on Settings IP display. This exception
does not permit addresses on other tabs/pages or expose any credentials,
account identifiers, raw payloads, paths or diagnostics. Preserve all other
Settings privacy restrictions.

The local-IP option gates display, not native collection: the existing
collector already reads local addresses regardless of this option. Public-IP
collection remains controlled by the existing service flag, fixed HTTPS
endpoint, timeout and at-least-five-minute cache. Opening this card, changing
tab or visibility, or rendering addresses must not initiate a request. Enabling
the existing public-IP option retains its existing service behavior only.
Add no endpoint, timer, collector, refresh button or permission prompt.

Derive IP row visibility from the current selected tab and published
`systemMonitorModel.value`, not cached booleans in a presentation. The current
configuration notification refresh must hide opted-out rows without waiting
for a collector tick. Keep each address option independent of Network surface
visibility, matching the existing controls.

## Core data and collection semantics

The existing `SystemMetricsSnapshot.Network` holds independently optional
Download/Upload rates, local addresses and optional Public IP. Add only
`interfaceNames: [String]?`, with a trailing initializer parameter defaulted
to nil. Existing callers and fixtures stay source compatible. There is no
Rust bridge, Codable/wire-format, export or widget-schema change.

- nil means names are unknown: older snapshot, failed native query or absent
  metadata. Explicit [] means a successful query reported no eligible names;
  it does not mean disconnected.
- In `collectNetwork`, retain `trafficInterfaces.sorted()` from the existing
  AF_LINK + ifa_data loop. Do not add a second native query, filters, primary
  selection, new counter arithmetic or a wrapper builder for this set copy.
  Native failure returns nil names through the compatible initializer.
- Preserve names in `SystemMetricsService.replacingPublicIP(in:with:)`, which
  reconstructs Network on every normal tick. Both enabled/disabled public-IP
  paths and failed public lookup must retain names. The existing whole-record
  stale copy path retains them on a collector throw.

Rates sum all AF_LINK entries with statistics, not just the primary interface.
There is currently no IFF_UP, loopback, VPN or virtual-interface filter in the
traffic branch. Primary-interface discovery only sorts local addresses.
Do not imply a named interface's independent rate or attach rates to an IP.
Names can exist when rates are unavailable on the first sample, source-set
change or counter reset. An unnamed statistics entry may still contribute to
the aggregate, so the list is a reported-name inventory, not a complete
traffic-attribution map.

## Presentation and freshness boundaries

Use a focused MainActor ObservableObject with one published derived DTO,
injected through default-compatible Settings initializers and updated by
the existing SettingsWindowController CombinedUsageSnapshot stream. There is
no additional UI last-known cache or asynchronous collection task.

Traffic dynamics require a system snapshot, explicit fresh or stale Network
availability, and at least one nonnil rate. Preserve directions independently,
including zero. Both nil, missing availability, unavailable or missing system
clears both rates and the successful traffic date, including orphan payloads.
Fresh time is the availability capturedAt; stale time is lastSuccessfulAt,
never the failed attempt's system/combined timestamp. Stale traffic labels
and accessibility values state Last known. Do not infer a warmup/error cause
from nil or let metadata establish a successful traffic date.

Interface metadata is independent of usable rates. Names in the current
snapshot can display on a rates-unavailable first sample. nil metadata or
missing system clears old names; never recover them from a separate cache.
If the original Network availability is stale, retained names are Last known
even when both rates are nil and traffic itself is unavailable. No separate
interface sample date is provided or inferred.

Normalize names for display only: trim whitespace; reject empty/control-
character names and names exceeding 64 UTF-8 bytes; case-sensitive deduplicate
and fixed lexical sort. Show at most 16 names. If invalid entries or the count
limit omit any name, state `Some reported names are not shown`. Do not truncate
an individual name into a fictitious identifier or alter sourceIDs used by the
collector. Original [] shows `No interface names reported`; a nonempty list
with every name rejected shows unknown plus the omission note. Native names
are short; these limits defend malformed injected values and narrow layouts.

IP values are independently displayable snapshot metadata, not evidence of
usable traffic. Validate each candidate as a numeric IPv4/IPv6 literal using
inet_pton (no DNS); trim surrounding whitespace, then discard control
characters, invalid/empty values and values exceeding 45 UTF-8 bytes,
deduplicate local addresses while retaining existing order, and preserve a
valid full address for accessibility/help. Do not log rejected candidates.
Missing system or missing values clears address state. A stale Network snapshot
marks retained addresses Last known without fabricating an address-success
timestamp. Public-IP cache age is not supplied by this model; traffic time
must not imply a new public-IP lookup. Opt-out/tab gating occurs at render
time even if valid address data remains in the DTO.

## Verification contract

Core tests cover trailing nil initializer compatibility, explicit [] and
names preservation, service public-IP off/on/failure reconstruction, and
success → collector throw preserving names and original successful time.
Existing rate conversions and baseline policy remain unchanged.

Presentation tests cover two/one/no rates, real zero, fresh/stale cross-day
dates, orphan rates with unavailable/missing availability, data-less stale,
missing system, recovery and transition clearing. Metadata tests include
first-sample names without rates, stale names without usable traffic, nil vs
[], sorting/dedup, controls/long names, limit/omission and all-rejected names.
IP tests cover validated IPv4/IPv6 vs malformed input, independent options,
Menu bar/Alerts hiding with options on, Dashboard visibility, immediate hide
with the same retained snapshot, missing addresses, stale marking and no new
request path. Visibility-off controller updates keep read-only information.

Use the existing guarded native review executable with isolated defaults and
inert rates/interface/documentation-address fixtures, not the installed app.
Check light 960×720 and dark 760×560, all tabs, visibility off, independent IP
flags, long names/IPv6 and unchanged CPU/RAM/Disk cards/Alerts copy. Inspect
supported accessibility output; distinguish actual VoiceOver, contrast and
macOS 14 hardware acceptance from source/fixture checks. Test first, obtain
independent spec/quality reviews and require focused plus full `make test`.
Do not claim real getifaddrs failure or interface appearance/disappearance
injection from pure/fake tests.

## Known existing limitations and exclusions

Current native if_data byte counters are UInt32; promoting them for sums does
not repair wrap or masked per-interface resets. Shared transfer-rate Double
boundary conversion, empty eligible interface sets, same-name interface
recreation and service fallback stale policy are pre-existing limitations.
This Settings feature preserves them rather than silently broadening into a
collector overhaul. It promises existing aggregate estimates, not accurate
lifetime/cumulative or interface-specific traffic. The traffic-data guard
prevents displaying a fabricated successful date on data-less stale input.

## Branch and continuation

Local branch `codex/network-settings-information` reuses the attached worktree
from Disk head `b138836`, with no new folders or app bundles. Disk PR #12, RAM
PR #11 and CPU PR #10 remain unchanged dependencies. No push, retarget, merge,
installation or release is authorized by this design step.

After written-spec approval, prepare a test-first plan with sequential bounded
Core-name-retention and Settings-card tasks, independent reviews and final
verification. Update STATUS with the exact continuation and evidence.
