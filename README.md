# Needlbar

Needlbar is a native macOS menu-bar monitor for Claude Code, Codex, and Cursor. It presents locally aggregated token usage and estimated cost together with provider quota windows and reset times.

Needlbar v0.1 is local-first. It requires no Needlbar account, backend, hosted sync, or telemetry. Usage and quota are independent refresh streams, so a usable last-known-good value can remain visible when the other stream is unavailable.

## Availability

Needlbar v0.1 is currently unreleased. No public GitHub Release or notarized download is available yet. The source tree can be built and tested locally, and `make package` creates a local Apple Silicon bundle for evaluation. That pre-release bundle is ad-hoc signed and is not a substitute for the future Developer ID-signed, notarized release.

Maintainer-only release validation is performed through a protected, tagless GitHub Actions workflow. It can sign, notarize, staple, and validate a workflow artifact without creating a public release; it does not make a release available for download. Creating a version tag or public GitHub Release requires separate explicit authorization.

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

Needlbar has no backend, account system, cloud sync, analytics, or telemetry. It does not upload token history, prompts, assistant responses, source code, raw paths, account identifiers, or provider credentials. It displays normalized counts, estimated costs, quota percentages, reset timestamps, freshness, and safe error states—not conversation or source content.

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
