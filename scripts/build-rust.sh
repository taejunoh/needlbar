#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGET="${NEEDLBAR_RUST_TARGET:-aarch64-apple-darwin}"
cargo build --workspace --release --target "$TARGET"
mkdir -p target/release
cp "target/$TARGET/release/libneedlbar_bridge.a" target/release/libneedlbar_bridge.a
