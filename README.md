# Needlbar

**Your AI coding usage at a glance.**

Needlbar is a native macOS menu bar monitor for AI coding usage, estimated cost, and subscription quota across Claude Code, Codex, and Cursor.

> Status: early development. Task 1 bootstrap is implemented; CI verification is currently blocked by a Swift 6 package-tools vs Swift 5.10 runner mismatch.

## Development Docs

For contributors and coding agents, use this reading order:

1. [`AGENTS.md`](AGENTS.md) — agent/Codex continuation instructions.
2. [`docs/STATUS.md`](docs/STATUS.md) — current state, blocker, and exact next task.
3. [`docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md`](docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md) — approved v0.1 design.
4. [`docs/superpowers/plans/2026-08-13-needlbar-v0.1.md`](docs/superpowers/plans/2026-08-13-needlbar-v0.1.md) — implementation plan.

## Verify

```bash
git submodule update --init --recursive
make test
```

`make test` is the project-wide verification entry point.
