# Needlbar

Needlbar is a native macOS menu-bar monitor for Claude Code, Codex, and Cursor. It presents locally aggregated token usage and estimated cost together with provider quota windows and reset times.

Needlbar is local-first. It requires no Needlbar account, backend, hosted sync, or telemetry. Usage and quota are independent refresh streams, so a usable last-known-good value can remain visible when the other stream is unavailable.

## Availability

The reviewed public availability copy for the tag-triggered release is:

Needlbar v0.2.2 is prepared for public release for macOS 14 or later on Apple Silicon.
[Download Needlbar v0.2.2 for Apple Silicon](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip)

The future public artifact will be Developer ID-signed and notarized. It is for macOS 14 or later on Apple Silicon. The link becomes downloadable only when the tag-triggered workflow publishes it; until then, this preparation copy is not a claim that a current public asset exists. The source tree can be built and tested locally, and `make package` creates a local Apple Silicon bundle for evaluation. That local bundle is ad-hoc signed and is not a substitute for the future public artifact.

Maintainer-only release validation is performed through a protected, tagless GitHub Actions workflow. It can sign, notarize, staple, and validate a workflow artifact without creating a public release; this remains historical/pre-release validation and does not make a release available for download. Creating a version tag or public GitHub Release requires separate explicit authorization.

## Requirements

- macOS 14 or later
- Apple Silicon (`arm64`)
- Swift 6-compatible Xcode toolchain
- Rust toolchain with Cargo
- Claude Code, Codex, and/or Cursor local usage data; Claude and Codex authentication is used only for their quota features

The supported provider set is exactly Claude Code, Codex, and Cursor for v0.1. Intel-specific packaging is not supported by the v0.1 artifact.

## What v0.1 does

Needlbar creates menu-bar modules for:

- Overview (enabled by default)
- Claude, Codex, and Cursor provider modules (disabled by default)

Each enabled module can show one of three title metrics: quota remaining, tokens today, or cost today.

Click Overview to see today’s combined tokens and estimated cost, the most constrained eligible quota, a seven-day usage chart, provider status rows, and Settings. Click an enabled provider module to see today’s usage and cost, input/output/cache token counts, quota windows, reset information, freshness, and safe recovery states. Usage and quota failures are shown independently and do not replace a previously valid value with zero.

Settings controls which modules are visible and which title metric each module uses. It also provides provider-native sign-in actions for Claude and Codex, plus a Cursor row explaining that usage comes from an existing local cache and offering one `Open Cursor Spending` button. Claude and Codex buttons launch the installed provider CLI's browser flow; Needlbar does not implement a second OAuth flow. Cursor has no credential or connection workflow in Needlbar.

Settings also provides one JSON-only `Export snapshot…` action for the current normalized snapshot. Export does not refresh provider data, authenticate, or upload data.

The v0.2.0 export is a user-initiated local backup/automation file. It contains only the normalized usage, quota, freshness, and safe status fields defined by the export schema; it does not include credentials, account identifiers, raw paths or provider responses, prompts, assistant responses, source code, or raw diagnostics.

## v0.2.1 widgets and notifications (unreleased)

v0.2.1 adds one medium Overview widget backed by a sanitized local projection; the widget does not refresh providers.

Quota notifications are off by default, require explicit macOS permission, run only while Needlbar is running, and never contain credentials or raw provider data.

This branch contains the widget and notification implementation and automated package checks, but it is not a release. Cursor remains usage-only with quota unavailable. Native signed macOS 14 arm64 Widget Gallery/App Group and notification-permission acceptance still require external evidence; the local macOS 26 build is not that acceptance.

## v0.2.2 local repository analytics (prepared for public release)

Open **Overview → Analytics…** for a manual, on-demand view over the fixed,
closed 30-day interval ending at that analysis's capture time. It uses only
automatically observed local Claude, Codex, and Cursor workspaces: there is no
startup scan, timer, watcher, or background refresh. The view reports repository
totals, provider/model breakdowns, local commit rows, optional local PR-number
metadata, estimated cost, coverage, and **observed active AI-session time**.
That timing is derived from local session timestamps and is not human coding
time, keyboard time, elapsed wall time, or a productivity measure.

Analytics reads local Git metadata only for an observed workspace. It uses a
four-hour local commit-correlation window and may show a PR number only when a
local commit message contains one unambiguous marker such as `(#42)`; this is a
deterministic local time-window association, not causal attribution or measured
commit cost, and is best-effort local metadata. There is no remote PR or forge
integration. Estimated cost uses the existing cached/local cost basis; it is
not an invoice or subscription charge. Missing workspace, timestamp, pricing,
duration, provider, repository, or Git evidence remains visible as partial
coverage or Unattributed data rather than being converted to zero.

The analysis is local-only: it makes no remote Git command, forge API call,
provider authentication, network request, backend, or database access. The
v0.2.0 export schema and v0.2.1 widget/notification behavior are unchanged;
Analytics data is not added to exports or sent to widgets or notifications.

To use it, click the menu-bar Overview, choose **Analytics…**, then choose
**Refresh** in the Analytics window. The feature is prepared for public release and remains local-only; no analytics history is retained after the in-memory state is discarded. A later failed refresh can leave the last successful in-memory snapshot marked stale, while an analysis with no successful result is Unavailable.

## Provider authentication and recovery

Needlbar reuses provider-native authentication for Claude and Codex. It does not own their credentials or provide separate disconnect controls.

| Provider | Local usage | Quota authentication and recovery |
| --- | --- | --- |
| Claude | `~/.claude/projects` and `~/.claude/transcripts`, parsed by the pinned `tokscale-core` engine | **Sign in with Claude** launches `claude auth login --claudeai` and opens Claude Code's provider-owned browser flow. After an explicit sign-in, Needlbar may request access to the exact macOS `Claude Code-credentials` Keychain item to verify quota. Background refresh is interaction-forbidden and never prompts. |
| Codex | `~/.codex/sessions` and archived sessions when available, parsed by `tokscale-core` | **Sign in with ChatGPT** launches `codex login` and opens Codex's provider-owned browser flow. Quota uses existing Codex auth, the provider API first, and the installed Codex CLI read-only app-server fallback. |
| Cursor | An existing compatible cache at `~/.config/tokscale/cursor-cache/usage.csv`, parsed by `tokscale-core`; Needlbar does not create or refresh this cache | Cursor quota is not collected in Needlbar. `Open Cursor Spending` opens the provider-owned dashboard at `https://cursor.com/dashboard/spending`. |

Provider-local paths and authentication behavior are documented in the [Claude](docs/providers/claude.md), [Codex](docs/providers/codex.md), and [Cursor](docs/providers/cursor.md) runbooks.

## Build, test, run, and package

From a checkout with the pinned usage engine initialized:

```bash
git submodule update --init --recursive
source "$HOME/.cargo/env"  # when Rust was installed with rustup
make test
```

`make test` is the project-wide verification command. It runs the Cargo workspace tests and Swift tests, including the pinned `vendor/tokscale-core` test suite.

To build and run the accessory menu-bar app in the foreground:

```bash
make run
```

Press Control-C to stop the foreground process. To create and smoke-test the local arm64 app bundle:

```bash
make package
make smoke
```

The package command writes `dist/Needlbar.app` and `dist/Needlbar-macos-arm64.zip`. `make smoke` checks the existing bundle’s metadata, arm64 executable, signature, launch behavior, and cleanup. The local package is ad-hoc signed; Developer ID signing, notarization, stapling, and GitHub publication are release-only steps and are not performed by this source build.

## Privacy and local-first boundaries

Needlbar has no backend, account system, cloud sync, hosted analytics service, or telemetry. Its local Analytics window does not upload data or create an analytics database. Needlbar does not upload token history, prompts, assistant responses, source code, raw paths, account identifiers, or provider credentials. It displays normalized counts, estimated costs, quota percentages, reset timestamps, freshness, and safe error states—not conversation or source content.

Usage reads only the documented provider-local sources above. Claude and Codex quota requests go directly to their providers over bounded HTTPS (with the Codex CLI fallback when applicable); Needlbar does not proxy them. Cursor usage is local-only and Cursor quota is represented by the fixed Spending dashboard action; Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration. Credentials, cookies, raw provider responses, and raw local paths remain out of Swift presentation state, diagnostics, logs, and bridge errors. On startup, the bridge may remove only an obsolete Needlbar-owned Cursor session file, without reading it; the local usage cache is preserved.

See [`docs/privacy.md`](docs/privacy.md) for the complete data-handling policy.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — layer ownership, data flow, and bridge boundaries.
- [`docs/privacy.md`](docs/privacy.md) — local reads, network requests, redaction, and user controls.
- [`docs/providers/claude.md`](docs/providers/claude.md), [`docs/providers/codex.md`](docs/providers/codex.md), [`docs/providers/cursor.md`](docs/providers/cursor.md) — provider sources, authentication, quota fallback, and recovery.
- [`SECURITY.md`](SECURITY.md) — security boundaries and vulnerability reporting.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — development setup, verification, and implementation rules.
- [`AGENTS.md`](AGENTS.md) and [`docs/STATUS.md`](docs/STATUS.md) — project continuation context and current release-acceptance status.
- [Approved v0.1 design specification](docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md) and [implementation plan](docs/superpowers/plans/2026-08-13-needlbar-v0.1.md).

## Credits and licenses

Needlbar embeds the pinned [Tokscale/tokscale-core](https://github.com/Nanako0129/tokscale-core) usage engine. `tokscale-core` is Copyright (c) 2025 Junho Yeo and is licensed under the MIT License; its complete notice is retained in [`vendor/tokscale-core/LICENSE`](vendor/tokscale-core/LICENSE) and packaged apps at `Needlbar.app/Contents/Resources/ThirdPartyNotices.txt`.

Needlbar-owned source is licensed under the MIT License; see [`LICENSE`](LICENSE).
