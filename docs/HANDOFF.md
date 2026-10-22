# Claude continuation handoff

**Checkpoint:** 2026-10-22, updated after the v0.3.11 release (first written
2026-10-20, updated after the v0.3.10 release on 2026-10-21 and for credential
renewal increment 1 on 2026-10-22). This is a documentation handoff, not a new
product approval or a claim of fresh installation/runtime verification.

## Repository state

- Work from `main`. The 2026-10-20 handoff branch merged in PR #21, the
  v0.3.10 candidate in PR #22 and its public record in PR #23, and the v0.3.11
  candidate in PR #30 and its public record in PR #31. Do not assume other old
  branches have been merged.
- For an isolated continuation, clone `main` into a new directory and
  initialize submodules as part of the clone:

  ```bash
  git clone --recurse-submodules https://github.com/taejunoh/needlbar.git \
    needlbar-continuation
  ```

  Keep the existing primary checkout (stale `main` at `7ab113d`, with local
  notes) untouched. Do not pull, reset, stash, or clean it as part of handoff.
- The public release is v0.3.11, build 14, for macOS 14+ on Apple Silicon,
  published 2026-10-22. Its release and distribution checks are evidence
  recorded in `docs/STATUS.md`; they do not establish what is installed or
  running later.
- Treat prior local runtime receipts in STATUS as private machine history.
  They are not part of this handoff and must not be copied into public docs.

## What v0.3.9 contains

The approved Claude refresh reliability increment shipped with source-aware
quota freshness, wake/connectivity recovery coordination, and safe local
attempt diagnostics. Open Claude/provider, Overview, dashboard, and Settings
surfaces age cached values without issuing additional provider requests. The
opt-in Claude Code status-line bridge reports only emitted five-hour and
seven-day quota windows; it does not poll while Claude Code is inactive or
provide Fable quota. One direct quota recovery was observed historically, but
there is no evidence of durable unattended recovery.

Credential renewal, Keychain repair, and cancellation/deadline bounds for a
blocked synchronous Keychain call are not implemented. Overnight/wake/network,
quota-reset, and sustained unattended acceptance remain unverified. The
status-line values are not Fable, and a status-line receipt is not proof of a
direct provider fetch. Keep these distinctions in any docs or claims.

## What v0.3.10 adds

v0.3.10 contains no new product features. The status-line helper registers
its signal forwarding before it spawns the original command, so a terminate
during startup no longer orphans that command. The git analytics runner's pipe
readers stop at the deadline even if a descendant leaves the process group
while holding the pipes. Build and test gates were hardened: a fail-closed
widget dependency check with pinned CI ripgrep, unstripped host build units
for macOS 27 release builds, locale-independent release contracts, and
load-robust process fixtures. Signals the helper does not forward can still
orphan the command, and an escaped git descendant is not itself killed.

## What v0.3.11 adds

v0.3.11 explains expired Claude Code access instead of a generic quota failure
(PR #28, copy made factual for desktop-app users in PR #29): the Claude
popover, Settings and dashboard show "Claude Code access on this Mac expired",
with a factual detail line in the popover and Settings, or once on the Fable
line while status-line windows are recent. The status-line helper restores
whole saved signal dispositions (PR #27); it runs one command per process, so
its observable behavior is unchanged. The rest is test reliability: the
`RefreshCoordinatorTests` lost wakeup (PR #24) and explicit, time-bounded test
waits (PR #25). Credential renewal is not implemented, and the explanation
adds no button, link, sign-in or other action.

## Current bounded follow-up

The `rg` fail-closed follow-up (PR #21), the `RefreshCoordinatorTests` lost
wakeup (PR #24) and the follow-up test hygiene (PR #25: explicit readiness and
cancellation-aware waits, 30 s caps on the blocking fakes, serialized
in-process status-line runner tests) and the status-line signal restore fix
(PR #27: `SignalForwarder` keeps whole `sigaction` records, so a saved
`SIG_IGN` no longer ends the restore early) are complete; PRs #24, #25 and
#27 shipped in v0.3.11.

Known open items:

- Direct Claude quota retrieval on the maintainer's machine failed for over
  a day with origin `keychainCredentialExpired` while the display fell back to
  status-line values; it recovered on 2026-10-21 after Claude Code was used
  and renewed its own credential. The approved
  `docs/superpowers/specs/2026-10-22-claude-credential-renewal-design.md`
  (PR #26) authorizes option A, narrowed, and increment 1 only. Increment 1
  is implemented in PR #28, which follows PR #26, and shipped with its PR #29
  copy in v0.3.11: a local-expiry origin reads in the existing reason slot, or
  once on the Fable line while status-line windows are recent, with a detail
  line in the popover and Settings. The
  increment-1 copy was reworded on 2026-10-22 to be factual for desktop-app
  users: short "Claude Code access on this Mac expired"; detail "Needlbar reads
  the access the Claude Code command-line tool saves on this Mac. The Claude
  desktop app does not renew it, so it updates after Claude Code runs in
  Terminal." It names Terminal only as a fact, with no instruction, button, or
  action. Q4 is answered: the maintainer mostly uses the Claude desktop app's
  Code tab. Read-only log aggregates showed the saved access lasts about eight
  hours and desktop-app use does not renew it. The status-line bridge has
  received nothing since 2026-10-07 even though `~/.claude/settings.json`
  points `statusLine` at the Needlbar helper, because status-line commands run
  only in interactive terminal sessions, so the bridge helps only those
  sessions. Credential renewal is still not implemented and is not approved.
  The expired-credential notification (option D) is deferred; Q7
  (provider-policy review of the direct token path) stays open. See the plan
  `docs/superpowers/plans/2026-10-22-claude-access-expired-reason.md`.
- Native macOS 14 acceptance is not agent-automatable end to end. It needs a
  provisioned macOS 14 guest with a logged-in GUI user, the Developer ID
  acceptance build, network disabled in the guest, and GUI interaction for the
  widget and notification cases (see the 2026-09-01 native acceptance driver
  spec and `scripts/native-acceptance-run.sh`).

Useful verified source locations:

- `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift`
- `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`
- `Sources/Needlbar/App/QuotaRecoveryMonitor.swift`
- `Sources/NeedlbarCore/Repositories/ClaudeStatusLineCacheRepository.swift`
- `Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift`
- `Sources/NeedlbarCore/Diagnostics/ClaudeQuotaCompletionDiagnostics.swift`
- `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift`
- `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift`
- `Sources/NeedlbarWidgetSupport/WidgetProjection.swift`
- `WidgetExtension/NeedlbarOverviewWidget.swift`
- `scripts/tests/widget-extension-tests.sh`

## Approved work that is still separate

- The compact Claude quota overview released in v0.3.6 is existing behavior.
  The later refinement is only to name the most-constrained window explicitly
  and retain the other windows in details; it is not part of v0.3.9,
  v0.3.10 or v0.3.11. Use
  `docs/superpowers/specs/2026-10-07-claude-refresh-reliability-design.md`
  and `docs/superpowers/plans/2026-09-29-claude-compact-presentation.md` before
  touching it.
- AI cost/quota wording must keep local estimated token cost, subscription
  quota/reset, and provider billing separate. The Claude API billing link is
  only a link; the feasibility harness does not produce a production balance.
  See `docs/superpowers/specs/2026-09-13-claude-api-balance-design.md` and
  `docs/superpowers/plans/2026-09-13-claude-api-balance.md`.
- The October 7 competitor comparison contains research proposals, not approved
  implementation requirements. Read its snapshot disclaimer before relying on
  product comparisons.

## Read and verify

Read these before implementation:

1. `AGENTS.md`
2. `docs/STATUS.md`
3. `docs/superpowers/specs/2026-10-07-claude-refresh-reliability-design.md`
4. `docs/superpowers/plans/2026-10-07-claude-refresh-reliability.md`
5. `docs/superpowers/specs/2026-09-25-claude-statusline-quota-bridge-design.md`
6. `docs/superpowers/specs/2026-09-15-claude-passive-quota-recovery-design.md`

For a fresh checkout, initialize submodules, then run the project gate:

```bash
git submodule update --init --recursive
env PATH="$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make test
```

Preserve the existing toolchain and macOS 14 deployment target. Historical
reports of 726 Swift and 1549 Rust tests are not a current test run; one Rust
test was ignored in that recorded run. Do not use authentication inspection,
credential renewal, model requests, or release/security-gate bypasses as
verification.

## Ready-to-use continuation prompt

> Continue from `docs/HANDOFF.md` and obey `AGENTS.md`. Pick one known open
> item only with the user's agreement. Keep fixes narrow and test-first, run
> `make test` with the documented PATH and macOS 14 target, and report the
> exact diff and verification. Do not inspect credentials, make model
> requests, install the app, or publish a release.
