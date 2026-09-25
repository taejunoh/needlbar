#!/usr/bin/env bash
set -euo pipefail

[[ -z "${NEEDLBAR_ACCEPTANCE_DRIVER:-}" ]] || {
  echo 'package-app: acceptance driver is forbidden in public packaging' >&2
  exit 1
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_PATH="$DIST_DIR/Needlbar.app"
ZIP_PATH="$DIST_DIR/Needlbar-macos-arm64.zip"
CONTENTS_PATH="$APP_PATH/Contents"
BRIDGE_ARCHIVE="$ROOT/target/release/libneedlbar_bridge.a"
INFO_PLIST="$ROOT/Resources/Info.plist"
NOTICES="$ROOT/Resources/ThirdPartyNotices.txt"
BRAND_VERIFIER="$ROOT/scripts/verify-provider-brand-assets.sh"
SOURCE_BRANDS="$ROOT/Sources/Needlbar/Resources/ProviderBrands"
PACKAGED_RESOURCE_BUNDLE="$CONTENTS_PATH/Resources/Needlbar_NeedlbarApp.bundle"
TEAM_ID="${NEEDLBAR_TEAM_ID:-TESTTEAMID}"
GROUP_ID="${NEEDLBAR_APP_GROUP_IDENTIFIER:-$TEAM_ID.com.taejunoh.needlbar}"
IDENTITY="${NEEDLBAR_CODESIGN_IDENTITY:--}"
HOST_ENTITLEMENTS_TEMPLATE="$ROOT/Resources/NeedlbarHostWidget.entitlements"
HOST_ENTITLEMENTS="$DIST_DIR/.NeedlbarHostWidget.entitlements"
WIDGET_APP="$CONTENTS_PATH/PlugIns/NeedlbarWidgetExtension.appex"

cd "$ROOT"

fail() {
  echo "package-app: $*" >&2
  exit 1
}

[[ -f "$INFO_PLIST" ]] || fail "missing Info.plist: $INFO_PLIST"
[[ -f "$NOTICES" ]] || fail "missing third-party notices: $NOTICES"
[[ -x "$BRAND_VERIFIER" ]] || fail "missing provider brand verifier: $BRAND_VERIFIER"
[[ -f "$HOST_ENTITLEMENTS_TEMPLATE" ]] || fail "missing host widget entitlements: $HOST_ENTITLEMENTS_TEMPLATE"
[[ -x "$ROOT/scripts/build-widget-extension.sh" ]] || fail "missing widget extension builder"
"$BRAND_VERIFIER" "$SOURCE_BRANDS"

# Build an arm64, featureless production bridge even when the host runner is
# Intel. Pin the Rust object deployment floor to the approved macOS 14 baseline.
if command -v rustup >/dev/null 2>&1 \
  && ! rustup target list --installed | grep -Fx 'aarch64-apple-darwin' >/dev/null; then
  rustup target add aarch64-apple-darwin
fi
MACOSX_DEPLOYMENT_TARGET=14.0 NEEDLBAR_RUST_TARGET="aarch64-apple-darwin" make -C "$ROOT" rust
[[ -f "$BRIDGE_ARCHIVE" ]] || fail "Rust bridge archive was not produced: $BRIDGE_ARCHIVE"

RELEASE_BIN_DIR="$(swift build --package-path "$ROOT" -c release --arch arm64 --show-bin-path)"
[[ "$RELEASE_BIN_DIR" == /* ]] || fail 'Swift release output directory was not resolved'
EXECUTABLE_SOURCE="$RELEASE_BIN_DIR/Needlbar"
HELPER_SOURCE="$RELEASE_BIN_DIR/NeedlbarClaudeStatusLine"
SWIFTPM_RESOURCE_BUNDLE="$RELEASE_BIN_DIR/Needlbar_NeedlbarApp.bundle"

# SwiftPM does not track the unsafe linker archive as a build input. Remove only
# the stale release executable so the next build relinks without discarding the
# Swift object and module caches.
rm -f -- "$EXECUTABLE_SOURCE" "$HELPER_SOURCE"

swift build --package-path "$ROOT" -c release --arch arm64
[[ -f "$EXECUTABLE_SOURCE" ]] || fail "release executable was not produced: $EXECUTABLE_SOURCE"
[[ -f "$HELPER_SOURCE" ]] || fail "release status-line helper was not produced: $HELPER_SOURCE"

# Never clear the whole output directory: these are the only two package targets.
rm -rf -- "$APP_PATH"
rm -f -- "$ZIP_PATH"
mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources" "$CONTENTS_PATH/PlugIns"
[[ -d "$SWIFTPM_RESOURCE_BUNDLE" ]] || fail "release provider resource bundle was not produced: $SWIFTPM_RESOURCE_BUNDLE"
cp -R "$SWIFTPM_RESOURCE_BUNDLE" "$CONTENTS_PATH/Resources/"
PACKAGED_BRANDS="$PACKAGED_RESOURCE_BUNDLE/ProviderBrands"
if [[ ! -d "$PACKAGED_BRANDS" ]]; then
  PACKAGED_BRANDS="$PACKAGED_RESOURCE_BUNDLE/Contents/Resources/ProviderBrands"
fi
"$BRAND_VERIFIER" "$PACKAGED_BRANDS"

install -m 755 "$EXECUTABLE_SOURCE" "$CONTENTS_PATH/MacOS/Needlbar"
install -m 755 "$HELPER_SOURCE" "$CONTENTS_PATH/MacOS/NeedlbarClaudeStatusLine"
install -m 644 "$INFO_PLIST" "$CONTENTS_PATH/Info.plist"
install -m 644 "$NOTICES" "$CONTENTS_PATH/Resources/ThirdPartyNotices.txt"
cp "$HOST_ENTITLEMENTS_TEMPLATE" "$HOST_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $GROUP_ID" "$HOST_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :NeedlbarAppGroupIdentifier $GROUP_ID" "$CONTENTS_PATH/Info.plist"

NEEDLBAR_TEAM_ID="$TEAM_ID" \
NEEDLBAR_APP_GROUP_IDENTIFIER="$GROUP_ID" \
NEEDLBAR_CODESIGN_IDENTITY="$IDENTITY" \
  "$ROOT/scripts/build-widget-extension.sh"
cp -R "$ROOT/.build/widget-extension/NeedlbarWidgetExtension.appex" "$CONTENTS_PATH/PlugIns/"

appex_count="$(find "$CONTENTS_PATH/PlugIns" -maxdepth 1 -type d -name '*.appex' -print | wc -l | tr -d '[:space:]')"
[[ "$appex_count" == 1 ]] || fail "expected exactly one embedded widget extension, found $appex_count"
[[ -x "$WIDGET_APP/Contents/MacOS/NeedlbarWidgetExtension" ]] || fail "embedded widget executable is missing"

! find "$APP_PATH" -type f \( -name '*AcceptanceFixture*' -o -path '*/Fixtures/*' \) -print -quit | grep -q . ||
  fail 'acceptance fixture file entered public app bundle'
! strings "$CONTENTS_PATH/MacOS/Needlbar" | grep -F -- '--acceptance-fixture' >/dev/null ||
  fail 'public host contains acceptance fixture parser'

# Build-widget-extension.sh has already signed the extension. Sign both inner
# executables before the enclosing app; do not use --deep here.
codesign --force --sign "$IDENTITY" "$CONTENTS_PATH/MacOS/NeedlbarClaudeStatusLine"
codesign --force --sign "$IDENTITY" --entitlements "$HOST_ENTITLEMENTS" "$APP_PATH"
codesign --verify --strict "$CONTENTS_PATH/MacOS/NeedlbarClaudeStatusLine"
codesign --verify --deep --strict "$APP_PATH"

# Archive from inside dist so Needlbar.app is the zip root rather than dist/.
# -X avoids host-specific extended attributes in this source-only app bundle.
(
  cd "$DIST_DIR"
  COPYFILE_DISABLE=1 /usr/bin/zip -qryX "$ZIP_PATH" "Needlbar.app"
)
[[ -f "$ZIP_PATH" ]] || fail "zip artifact was not produced: $ZIP_PATH"
