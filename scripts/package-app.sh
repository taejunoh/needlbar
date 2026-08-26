#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_PATH="$DIST_DIR/Needlbar.app"
ZIP_PATH="$DIST_DIR/Needlbar-macos-arm64.zip"
CONTENTS_PATH="$APP_PATH/Contents"
EXECUTABLE_SOURCE="$ROOT/.build/arm64-apple-macosx/release/Needlbar"
BRIDGE_ARCHIVE="$ROOT/target/release/libneedlbar_bridge.a"
INFO_PLIST="$ROOT/Resources/Info.plist"
NOTICES="$ROOT/Resources/ThirdPartyNotices.txt"

cd "$ROOT"

fail() {
  echo "package-app: $*" >&2
  exit 1
}

[[ -f "$INFO_PLIST" ]] || fail "missing Info.plist: $INFO_PLIST"
[[ -f "$NOTICES" ]] || fail "missing third-party notices: $NOTICES"

# Build an arm64, featureless production bridge even when the host runner is
# Intel. Pin the Rust object deployment floor to the approved macOS 14 baseline.
if command -v rustup >/dev/null 2>&1 \
  && ! rustup target list --installed | grep -Fx 'aarch64-apple-darwin' >/dev/null; then
  rustup target add aarch64-apple-darwin
fi
MACOSX_DEPLOYMENT_TARGET=14.0 NEEDLBAR_RUST_TARGET="aarch64-apple-darwin" make -C "$ROOT" rust
[[ -f "$BRIDGE_ARCHIVE" ]] || fail "Rust bridge archive was not produced: $BRIDGE_ARCHIVE"

# SwiftPM does not track the unsafe linker archive as a build input. Remove only
# the stale release executable so the next build relinks without discarding the
# Swift object and module caches.
rm -f -- "$EXECUTABLE_SOURCE"

swift build --package-path "$ROOT" -c release --arch arm64
[[ -f "$EXECUTABLE_SOURCE" ]] || fail "release executable was not produced: $EXECUTABLE_SOURCE"

# Never clear the whole output directory: these are the only two package targets.
rm -rf -- "$APP_PATH"
rm -f -- "$ZIP_PATH"
mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"

install -m 755 "$EXECUTABLE_SOURCE" "$CONTENTS_PATH/MacOS/Needlbar"
install -m 644 "$INFO_PLIST" "$CONTENTS_PATH/Info.plist"
install -m 644 "$NOTICES" "$CONTENTS_PATH/Resources/ThirdPartyNotices.txt"

# Pre-release artifacts are deliberately ad-hoc signed. Stable releases re-sign
# this exact bundle with a Developer ID identity before publishing.
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

# Archive from inside dist so Needlbar.app is the zip root rather than dist/.
# -X avoids host-specific extended attributes in this source-only app bundle.
(
  cd "$DIST_DIR"
  COPYFILE_DISABLE=1 /usr/bin/zip -qryX "$ZIP_PATH" "Needlbar.app"
)
[[ -f "$ZIP_PATH" ]] || fail "zip artifact was not produced: $ZIP_PATH"
