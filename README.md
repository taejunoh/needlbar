# Needlbar

Needlbar is a native macOS menu-bar monitor for Claude Code, Codex, and Cursor. It shows locally aggregated token usage and estimated cost alongside provider subscription quota and reset windows.

Needlbar v0.1 is local-first: it requires no Needlbar account, backend, or telemetry. Usage and quota are refreshed independently, so a provider's last usable reading remains visible when the other subsystem is unavailable.

## Requirements

- macOS 14 or later
- Apple Silicon (`arm64`)
- Providers: Claude Code, Codex, and Cursor

Provider-native sign-in is reused for Claude and Codex. Cursor connection is an explicit action in Settings; Needlbar never silently imports browser cookies.

## Install

Download `Needlbar-macos-arm64.zip` from [GitHub Releases](https://github.com/taejunoh/needlbar/releases), unzip it, then move `Needlbar.app` to Applications or another preferred location. The v0.1 release artifact supports macOS 14+ on Apple Silicon only.

## Privacy

Needlbar is local-first: it has no telemetry and requires no Needlbar account. It reads only the documented provider-local usage and authentication sources needed for its features, and sends no prompts, responses, source code, token history, paths, or credentials to a Needlbar service. See [`docs/privacy.md`](docs/privacy.md) for the complete policy.

## Build and run

```bash
git submodule update --init --recursive
source "$HOME/.cargo/env"  # when Rust was installed with rustup
make test
make run
```

`make test` is the project-wide verification entry point. `make run` builds the Rust bridge and launches the accessory menu-bar app. `make package` creates `dist/Needlbar.app` and `dist/Needlbar-macos-arm64.zip`; `make smoke` verifies an existing bundle.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — layer ownership and data flow.
- [`docs/privacy.md`](docs/privacy.md) — local data access, network boundaries, and redaction policy.
- [`docs/providers/claude.md`](docs/providers/claude.md), [`docs/providers/codex.md`](docs/providers/codex.md), [`docs/providers/cursor.md`](docs/providers/cursor.md) — provider-specific sources, authentication, quota fallback, and recovery.
- [`SECURITY.md`](SECURITY.md) — security scope and reporting guidance.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — development setup, tests, and implementation rules.
- [`AGENTS.md`](AGENTS.md), [`docs/STATUS.md`](docs/STATUS.md), and the approved [design specification](docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md) — project continuation context.

## Credits and licenses

Needlbar embeds the pinned [Tokscale/tokscale-core](https://github.com/Nanako0129/tokscale-core) usage engine. `tokscale-core` is Copyright (c) 2025 Junho Yeo and is licensed under the MIT License; its complete notice is retained in [`vendor/tokscale-core/LICENSE`](vendor/tokscale-core/LICENSE) and in packaged apps at `Needlbar.app/Contents/Resources/ThirdPartyNotices.txt`. Needlbar-owned source is also MIT licensed; see [`LICENSE`](LICENSE).
