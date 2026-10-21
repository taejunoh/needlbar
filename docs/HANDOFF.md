# Claude continuation handoff

**Checkpoint:** 2026-10-20. This is a documentation handoff, not a new product
approval or a claim of fresh installation/runtime verification.

## Repository state

- Work from branch `codex/claude-handoff-2026-10-20`, based on `main`
  `b270736e09803c18b0025ce1fd8321f78aa7729b` (the public documentation PR #20
  merge). Do not assume other old branches have been merged.
- For an isolated continuation, clone this branch into a new directory and
  initialize submodules as part of the clone:

  ```bash
  git clone --branch codex/claude-handoff-2026-10-20 --recurse-submodules \
    https://github.com/taejunoh/needlbar.git needlbar-claude-continuation-2026-10-20
  ```

  Keep the existing primary checkout (stale `main` at `7ab113d`, with local
  notes) untouched. Do not pull, reset, stash, or clean it as part of handoff.
- The public release is v0.3.9, build 12, for macOS 14+ on Apple Silicon. The
  October 7 release and distribution checks are historical evidence recorded
  in `docs/STATUS.md`; they do not establish what is installed or running now.
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

## Current bounded follow-up

The known CI limitation is in `scripts/tests/widget-extension-tests.sh`: its
negated `rg` search treats a missing search executable like “no forbidden
match.” Add a fail-closed tool-availability guard and a missing-`rg`
regression. If the user asks to continue implementation, first inspect the
script and its focused test contract, then make only this narrow test-first
repair. Do not expand into widget redesign or provider behavior.

Useful verified source locations:

- `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift`
- `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`
- `Sources/Needlbar/App/QuotaRecoveryMonitor.swift`
- `Sources/NeedlbarCore/Repositories/ClaudeStatusLineCacheRepository.swift`
- `Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift`
- `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift`
- `Sources/NeedlbarWidgetSupport/WidgetProjection.swift`
- `WidgetExtension/NeedlbarOverviewWidget.swift`
- `scripts/tests/widget-extension-tests.sh`

## Approved work that is still separate

- The compact Claude quota overview released in v0.3.6 is existing behavior.
  The later refinement is only to name the most-constrained window explicitly
  and retain the other windows in details; it is not part of v0.3.9. Use
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

> Continue from `docs/HANDOFF.md` and obey `AGENTS.md`. First review the
> fail-closed `rg` guard gap in `scripts/tests/widget-extension-tests.sh` and
> its existing tests. If the narrow test-first fix is clear, implement only
> that guard and missing-`rg` regression, run the focused widget contract and
> `make test` with the documented PATH and macOS 14 target, and report the
> exact diff and verification. Do not inspect credentials, make model
> requests, install the app, or publish a release.
