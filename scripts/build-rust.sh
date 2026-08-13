#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -n "${NEEDLBAR_RUST_TARGET:-}" ]]; then
  TARGET="$NEEDLBAR_RUST_TARGET"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  case "$(uname -m)" in
    arm64) TARGET="aarch64-apple-darwin" ;;
    x86_64) TARGET="x86_64-apple-darwin" ;;
    *) echo "Unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
  esac
else
  TARGET="$(rustc -vV | awk '/^host:/ { print $2 }')"
fi

cargo build --workspace --release --target "$TARGET"
mkdir -p target/release
cp "target/$TARGET/release/libneedlbar_bridge.a" target/release/libneedlbar_bridge.a
