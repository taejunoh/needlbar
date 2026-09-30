# RAM Settings Information

Date: 2026-09-30
Scope: Settings → SYSTEM → RAM only
State: Recommended scope approved; written specification awaiting user review.

## Intent and approved scope

Continue the SYSTEM Settings improvements using the CPU information card's
native layout and update flow. The user approved a RAM summary with total,
used, available, swap, pressure, sample freshness, and the inexpensive
compressed/Wired extension. Per-app and per-process memory are excluded.

The existing collector already reads the VM counters required for compressed
and Wired memory. Retain those counters in the normalized snapshot rather
than introducing another collector, process enumeration, or polling loop.

## Screen contract

Preserve the sidebar, RAM title, Menu bar / Dashboard / Alerts picker and
existing surface controls. Show one read-only RAM information area below the
picker and above those controls on all three RAM tabs:

1. Capacity: total physical memory with an explicit Total label.
2. Activity: prominent purple used percentage, Used bytes, and Available
   bytes. Use a compact used-versus-available bar with the same purple accent;
   label both sides and do not segment it into overlapping memory categories.
3. Details: Compressed, Wired, and Swap, in a compact responsive group. Use
   binary units consistently with the existing system dashboard. Unknown
   values are `—`; actual zero bytes remains a valid displayed value.
4. Memory pressure: the OS-reported Normal / Warning / Critical value. Use
   semantic green / orange / red accents plus text, not color alone. Missing
   pressure is Unknown, never implicitly Normal. Do not infer pressure from
   percentage or swap size, and do not label high RAM usage alone as a fault.
5. Freshness: localized successful sample date and time, or an explicit Last
   known / unavailable explanation. Never substitute a failed attempt time
   for the successful observation time.

Explain briefly, with help text rather than repeated lines, that Compressed
and Wired are already included in Used, and Swap occupies disk rather than
physical RAM. They are not independent additive slices of total RAM.

At narrow widths, detail fields wrap or use a vertical layout; nothing is
clipped at the existing minimum Settings size. Maintain native light/dark
styling, monospaced numeric values, and meaningful accessibility labels.
Do not add a fourth tab, history graph, manual refresh action, or new settings.
Alerts retains its truthful unsupported-system-threshold explanation.

## Data definitions and minimal model extension

Add three independently optional `UInt64` fields to the existing normalized
`SystemMetricsSnapshot.Memory`: `totalBytes`, `compressedBytes`, and
`wiredBytes`. Add trailing initializer parameters defaulted to nil so existing
callers and fixtures remain source compatible. This snapshot is not Codable;
do not add a wire format or Rust bridge migration for these fields.

- Total is the actual positive `ProcessInfo.processInfo.physicalMemory` value
  already used by the existing memory conversion. Preserve it independently
  when a VM statistics call or dynamic conversion fails. Do not derive an
  authoritative physical capacity from arbitrary `usedBytes + freeBytes` in
  older or partial snapshots. Missing total stays unknown.
- Used and Available keep the existing Activity-Monitor-compatible formula
  and `freeBytes` storage convention unchanged. The UI labels `freeBytes` as
  Available, not raw free pages. Derive percentage only from a validated
  positive, overflow-safe Used + Available denominator with Used no greater
  than that sum; where Total exists, reject inconsistent capacity arithmetic
  rather than clamping or inventing a percentage.
- Compressed is `compressor_page_count × host_page_size`: physical memory
  occupied by the compressor. It is not the uncompressed logical size
  `total_uncompressed_pages_in_compressor`.
- Wired is `wire_count × host_page_size`: physical memory that currently
  cannot be paged out. Do not describe it as per-app or kernel-only memory.
- Swap and pressure retain the existing independently optional native values
  and definitions. No new approximation or source is introduced.

Counter definitions were checked against the local SDK and the
[Apple XNU VM statistics header](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h).

Use checked integer page-to-byte multiplication with a positive page size.
Reject overflow and values exceeding known physical capacity as unknown for
that detail only. Do not turn malformed or missing counters into zero, and do
not let a bad new detail field invalidate otherwise usable existing metrics.
Conversely, showing valid Total does not make failed dynamic memory fresh.

## Collection, presentation, and failure boundaries

Read the extra values in the existing macOS memory collection function from
the same VM statistics result and page size. Capture Total before early VM
failure returns so independently available physical capacity is retained.
Keep current aggregate-failure returns free of dynamic values; retaining
Total does not introduce independently fresh swap or pressure in that branch.
Keep the existing aggregate conversion, module availability decision, one-
second service loop, and non-memory collection paths unchanged. Verify that
existing stale-snapshot copying preserves all added fields.

A focused RAM Settings presentation derives values from the existing
`CombinedUsageSnapshot` delivered to `SettingsWindowController`. Own one
presentation in that controller and forward it through default-compatible
Settings initializers, beside CPU's existing presentation. Mount the RAM card
only for the RAM page, before the surface-specific detail pane.

Dynamic values are displayed only with usable memory activity and `.fresh`
or `.stale(lastSuccessfulAt:)` module availability. Usable activity requires
a present Used value (including genuine zero), no greater than known Total;
it does not require optional pressure, swap, or detail values. Missing
Available or inconsistent capacity arithmetic suppresses the percentage and
bar without fabricating them. A stale card retains the
available detail values with an explicit Last known label for the whole
dynamic section, including pressure; never make old pressure look current.
Unavailable or missing module availability clears dynamic values and
successful sample time, even if an orphan payload remains. Known valid Total
may still display as capacity. Missing individual swap/pressure/detail values
remain unknown without suppressing other valid fields.
RAM has no CPU-style two-sample warmup. A stale availability entry without
usable dynamic activity must not display a supposed last-success timestamp.

No second UI last-known cache, Settings collector, timer, process scan,
network request, credential access, or provider refresh. Disabling RAM's
menu-bar/dashboard visibility does not stop the existing collection stream
or erase information on its Settings page.

## Verification and exclusions

Test model source compatibility and optional fields; checked page conversion
at zero, normal, overflow, and impossible-capacity boundaries; independently
retained Total on dynamic failures; and unchanged Used/Available arithmetic.
Test fresh and stale values, failed-versus-successful timestamps, unknown
pressure/details, missing availability and fresh-to-unavailable transitions.
Test controller updates with visibility disabled and RAM-only placement.

Use the existing exact-argument-guarded native Settings review executable
with inert RAM fixtures and isolated defaults. Inspect normal 960×720 light
and minimum 760×560 dark windows, all RAM tabs, wrapping, and accessibility
where supported. Do not treat fixture images as installed-app evidence;
explicitly record unverified native/VoiceOver/macOS 14 checks. Run focused
tests test-first, independent spec and quality review, and full `make test`.

Exclude per-app/process memory, App Memory estimates, speed/type/DIMM claims,
top processes, graphs/history, alert implementation, interval controls, Rust
changes, provider changes, and unrelated SYSTEM redesigns. Keep macOS 14.
No merge, push, release, reinstall, or new app bundle is authorized by this
design step. CPU PR #10 remains separate; this RAM branch starts at its
verified head `524e05c` and does not modify the CPU PR.

## Continuation

After the user's written-spec review, prepare the RAM-only test-first plan
with explicit Core and Settings ownership, sequential implementation and
independent reviews. Update `docs/STATUS.md` with exact verification results
and the next continuation point; integration and installation are separate.
