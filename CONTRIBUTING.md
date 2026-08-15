# Contributing

Needlbar v0.1 follows the approved design and ordered implementation plan. Keep changes focused and preserve the layer boundaries described in [`docs/architecture.md`](docs/architecture.md).

## Local setup

```bash
git clone https://github.com/taejunoh/needlbar.git
cd needlbar
git submodule update --init --recursive
source "$HOME/.cargo/env"  # when Rust was installed with rustup
```

The `vendor/tokscale-core` submodule must remain at commit `53f9eefffd3278fd430076531548f7b1f5861f9a`. Do not update that revision without the fixture cross-check required by the approved design.

The supported baseline is macOS 14 or later on Apple Silicon (`arm64`) with Swift 6 and Rust 2021. CI selects Xcode 16.2 for the Swift toolchain.

## Verification

Run the narrow test for the code you are changing first, then run the full gate before handing off a task:

```bash
make test
cargo clippy --workspace --all-targets --all-features -- -D warnings
swift build -c release
git diff --check
```

`make test` initializes the Rust build and runs the workspace and Swift tests. Fixture tests must use synthetic data; never add reusable provider credentials or private user content.

## Implementation rules

- Use test-first changes where the implementation plan calls for them.
- Keep AppKit/SwiftUI presentation in `Needlbar`, normalized state, refresh scheduling, and last-known-good behavior in `NeedlbarCore`, and usage/quota/authentication in their assigned Rust crates.
- Usage and quota are independently refreshable and independently fallible. A failed refresh must not erase another subsystem's valid value or a provider's last-known-good value.
- `tokscale-core` owns local session discovery, parsing, deduplication, aggregation, pricing, and normalized usage. Do not copy its provider parsers into Needlbar.
- `needlbar-source-sync` owns Cursor usage-export hydration only. `needlbar-quota` owns subscription quota and provider authentication; it must not parse token-history files.
- `needlbar-bridge` owns the narrow C ABI, UTF-8 JSON envelopes, memory freeing, panic containment, and redaction boundary. Presentation logic does not belong there.
- Do not add providers or v0.1-excluded features opportunistically.

Keep commits focused, document task completion in `docs/STATUS.md`, and include the relevant tests and verification output in the handoff. Do not include raw credentials or private provider content in commits, logs, fixtures, screenshots, or bug reports.
