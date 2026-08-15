# Needlbar

Needlbar is a native macOS menu-bar monitor for Claude Code, Codex, and Cursor. It shows locally aggregated token usage and estimated cost alongside provider subscription quota and reset windows.

Needlbar v0.1 is local-first: it requires no Needlbar account, backend, or telemetry. Usage and quota are refreshed independently, so a provider's last usable reading remains visible when the other subsystem is unavailable.

## Supported baseline

- macOS 14 or later
- Apple Silicon (`arm64`)
- Claude Code, Codex, and Cursor
- Swift 6 and Rust 2021

Provider-native sign-in is reused for Claude and Codex. Cursor connection is an explicit action in Settings; Needlbar never silently imports browser cookies.

## Build and run

```bash
git submodule update --init --recursive
source "$HOME/.cargo/env"  # when Rust was installed with rustup
make test
make run
```

`make test` is the project-wide verification entry point. `make run` builds the Rust bridge and launches the accessory menu-bar app. The repository currently describes the v0.1 development build; a packaged release is not implied by a source checkout.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — layer ownership and data flow.
- [`docs/privacy.md`](docs/privacy.md) — local data access, network boundaries, and redaction policy.
- [`docs/providers/claude.md`](docs/providers/claude.md), [`docs/providers/codex.md`](docs/providers/codex.md), [`docs/providers/cursor.md`](docs/providers/cursor.md) — provider-specific sources, authentication, quota fallback, and recovery.
- [`SECURITY.md`](SECURITY.md) — security scope and reporting guidance.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — development setup, tests, and implementation rules.
- [`AGENTS.md`](AGENTS.md), [`docs/STATUS.md`](docs/STATUS.md), and the approved [design specification](docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md) — project continuation context.
