
## Task 4 preflight — Steps 1–2

Timestamp: 2026-08-31 (local host)

Scope completed by this preflight: fresh automated gates and a separate locally signed candidate. Native app registration, launch, termination, and UI operation were intentionally not performed; those remain for the primary agent's direct acceptance.

### Step 1 — fresh complete gates

All canonical commands were run from the worktree with `source /Users/taejunoh/.cargo/env` loaded:

- `make test`: exit 0. Rust tests: 1,459 passed, 0 failed, 1 ignored (including pinned vendor tests: 1,372 passed, 1 ignored); Swift: 243 tests in 11 suites passed. Widget-extension build/metadata contract, package relink regression, and notarize-app shell contracts passed.
- `make package`: exit 0. Fresh `dist/Needlbar.app` and ZIP packaging completed; package uses the default synthetic/ad-hoc identity as expected for this gate.
- `make smoke`: exit 0. `Needlbar app-bundle smoke passed`.
- `git diff --check`: exit 0 with no output.

Logs are retained under `native-validation/menu-panel.x6vzf2n2yv/logs/`:

- `make-test.log`
- `make-package.log`
- `make-smoke.log`
- `git-diff-check.log`

An initial standalone `make package` invocation without sourcing Cargo returned exit 2 (`cargo: command not found`); it was not the canonical gate environment. Its output is retained as `make-package-unsourced.log`; the sourced canonical rerun above is the gate result.

### Step 2 — separate real-Team local candidate

Fresh bounded candidate:

`.superpowers/native-validation/menu-panel.x6vzf2n2yv/Needlbar.app`

Exact executable and bundle paths:

- Host bundle: `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/v021-widgets-notifications/.superpowers/native-validation/menu-panel.x6vzf2n2yv/Needlbar.app`
- Host executable: `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/v021-widgets-notifications/.superpowers/native-validation/menu-panel.x6vzf2n2yv/Needlbar.app/Contents/MacOS/Needlbar`
- Widget bundle: `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/v021-widgets-notifications/.superpowers/native-validation/menu-panel.x6vzf2n2yv/Needlbar.app/Contents/PlugIns/NeedlbarWidgetExtension.appex`
- Widget executable: `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/v021-widgets-notifications/.superpowers/native-validation/menu-panel.x6vzf2n2yv/Needlbar.app/Contents/PlugIns/NeedlbarWidgetExtension.appex/Contents/MacOS/NeedlbarWidgetExtension`

Resolved non-secret signing metadata:

- App Group in host and widget Info.plist: `3BMF4LM6TM.com.taejunoh.needlbar`
- Signing identity: `Developer ID Application: Taejun Oh (3BMF4LM6TM)`
- Identity hash: `4C6503D0A78A9F51C86CC7C9683115E74A4902A7`
- Host and widget are arm64 Mach-O binaries.
- Extension was signed first, then host, each with `--options runtime --timestamp=none` and separate entitlements.

Entitlements observed after signing:

- Host: `com.apple.security.application-groups = [3BMF4LM6TM.com.taejunoh.needlbar]`; no sandbox entitlement.
- Widget: `com.apple.security.app-sandbox = true` and `com.apple.security.application-groups = [3BMF4LM6TM.com.taejunoh.needlbar]`.
- Both signatures report `Authority=Developer ID Application: Taejun Oh (3BMF4LM6TM)`, `TeamIdentifier=3BMF4LM6TM`, and `CodeDirectory flags=0x10000(runtime)`.

`codesign --verify --deep --strict --verbose=2` returned exit 0 for the candidate (including a repeat verification). Signing and entitlement evidence is retained in:

- `candidate-paths-and-identity.log`
- `codesign-widget.log`
- `codesign-host.log`
- `codesign-verify-deep-strict.log`
- `codesign-verify-deep-strict-repeat.log`
- `candidate-signing-entitlements.log`

### NEEDS_CONTEXT for primary-agent UI inspection

The candidate is ready for the primary agent's Step 3–4 native acceptance. This preflight deliberately did not terminate, unregister, register, launch, or operate any app. The primary agent must validate the exact prior candidate/PID before any replacement, then perform direct menu-panel interaction and record visible-frame/button/panel coordinates, dismissal behavior, process health, and secondary-display behavior if available. No UI/PID/frame evidence exists from this preflight.

Unrelated existing dirty files were preserved and not staged or reverted: `docs/STATUS.md`, `scripts/build-widget-extension.sh`, and `scripts/tests/widget-extension-tests.sh`.

## Task 4 native acceptance update — primary-agent evidence

The primary agent completed the bounded native inspection against the exact candidate
`.superpowers/native-validation/menu-panel.x6vzf2n2yv/Needlbar.app`. PID `32737` was healthy and
its executable path matched:

`/Users/taejunoh/Developer/LFG/needlbar/.worktrees/v021-widgets-notifications/.superpowers/native-validation/menu-panel.x6vzf2n2yv/Needlbar.app/Contents/MacOS/Needlbar`

Recorded AppKit display frames:

- Primary screen: frame `(0, 0, 1512, 982)`; visible frame `(0, 0, 1512, 949)`.
- Secondary screen: frame `(-503, 982, 2560, 1440)`; visible frame equal to that frame.
- Secondary-display custom panel CoreGraphics bounds: `X=1019, Y=-1410, W=300, H=353`.

After coordinate conversion, the panel satisfied the visible-frame bottom constraint and was
centered under the clicked status-item anchor when not edge-clamped. The retained crop
`.superpowers/native-validation/menu-panel.x6vzf2n2yv/panel-position-crop.png` was inspected by
the primary agent: the menu bar ends at approximately 60 px at 2x scale, the panel begins near
y=61, and it is centered under the second AI status icon without native popover arrow/glass
overlap.

Verified direct interactions:

- Settings dismissed the panel and opened the Needlbar Settings window.
- Clicking the external SecurityAgent Deny control dismissed the panel.
- One same-app outside interaction dismissed the panel, but the synthetic click command reported
  `unverified/window_not_focused`; this is not treated as a fully verified same-app outside-click
  result.
- Native Escape injection was blocked because the nonactivating panel could not be focused;
  automated Escape tests remain green, but no native Escape result is claimed.

This current-host evidence disproves the prior native-popover hypothesis for the observed
outside-app dismissal case and verifies the bounded placement constraints. It does not establish
installed-widget rendering/readback, WidgetKit App Group lifecycle, deep-link/quit/reset/midnight
behavior, notification delivery or remaining permission cases, same-app outside-click behavior
beyond the bounded observation, native Escape, or macOS 14 arm64 compatibility. No additional app
registration/launch/termination operation was performed by this documentation update, and no
tag, push, release upload, or Apple portal mutation occurred.

## Task 4 follow-up — stale presenter callbacks, anchor equality, and P2 deinit probe

### RED

- Added `staleDismissalFromPriorPresentationCannotDismissNewPresentation`: before the presenter
  generation guard existed, the test change could not prove the required stale-callback behavior;
  the focused presenter compile/run was blocked by the independent missing `Equatable`
  conformance on `StatusItemPresentationAnchor`.
- Added `presentationAnchorsCompareByFrames`: the focused compile failed with the expected Swift
  errors that `StatusItemPresentationAnchor` did not conform to `Equatable`.
- A temporary `deinit { dismissalMonitoringToken?.cancel() }` probe was compiled under the current
  Swift 6 baseline. It failed with exit 1 and the compiler diagnostic
  `call to main actor-isolated instance method 'cancel()' in a synchronous nonisolated context`
  (`[#ActorIsolatedCall]`). The temporary probe was removed; no `nonisolated(unsafe)` workaround
  was introduced.

### GREEN

- `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=MenuPanelPresenterTests`
  — exit 0; 9 tests in 1 suite passed, including stale callback isolation.
- `source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=MenuPanelPlacementTests`
  — exit 0; 9 tests in 1 suite passed, including direct anchor equality.
- `source /Users/taejunoh/.cargo/env && make swift-test` — exit 0; 245 tests in 11 suites
  passed. Existing compiler output still contains the known macOS 26.5 object versus macOS 14
  deployment warning; there were no test failures.
- `git diff --check` — exit 0.

### Implementation and P2 conclusion

`AppKitMenuPanelPresenter` now owns a monotonically increasing presentation generation. A
successful `present` advances and captures the generation in its monitor dismissal callback;
`dismiss` advances it again before tearing down the current token. A callback queued for an older
presentation therefore becomes a no-op and cannot dismiss the newer panel or call `onDismiss`.
Existing re-present cancellation and toggle/dismiss behavior remain covered by the focused suite.
`StatusItemPresentationAnchor` now derives `Equatable` from its two `NSRect` values.

The P2 deinit cleanup is mitigated by explicit owner teardown: the menu-bar lifecycle calls the
presenter's main-actor `dismiss` path while stopping observation, which cancels the monitoring
token on the correct actor. A direct presenter `deinit` cancellation is not safely implementable
under the current Swift baseline because deinitializers are synchronous/nonisolated while the
token's `cancel()` is `@MainActor`; the probe above provides the compiler evidence. The code keeps
the safe explicit teardown and does not use `nonisolated(unsafe)` or other baseline-risky access.

## Task 4 final review follow-up

Final read-only review closed the P1/P3 findings with focused fix commit `dd426ab` (`fix: guard
stale menu panel dismissals`) and found no new P0–P2 findings. The presenter-owned monotonically
increasing generation guards each locally queued dismissal callback, so a callback retained from
an earlier presentation cannot dismiss the newer panel or call `onDismiss`. The
`StatusItemPresentationAnchor: Equatable` contract is covered by direct equality/inequality tests.

The P2 deinit concern is withdrawn as an open finding: explicit
`MenuBarController.stopObserving` teardown is invoked by both application termination paths and
cancels the presenter token on the main actor. The direct `deinit` cancellation probe failed under
the current Swift 6 baseline because a synchronous nonisolated deinitializer cannot call the
token's `@MainActor cancel()` (`[#ActorIsolatedCall]`). No `nonisolated(unsafe)` workaround was
introduced.

Fresh final gate evidence from the primary agent:

- `source /Users/taejunoh/.cargo/env && make test` — exit 0; Rust workspace green, pinned
  `tokscale-core` 1372 passed / 0 failed / 1 ignored, Swift 245 tests in 11 suites passed, and
  widget-extension, package relink, and notarization shell contracts passed.
- Known linker deployment warnings were the only caveat: macOS 26.5 Rust objects linked against
  the macOS 14.0 deployment target; no gate failed.
- The root agent will run the final `git diff --check` for this docs-only pass.

Native caveats remain unchanged: macOS 14 arm64 acceptance is unavailable on this macOS 26 host.
Direct native Escape injection was not accepted because the nonactivating panel could not be
focused; automated Escape tests remain green but do not establish native Escape acceptance.
