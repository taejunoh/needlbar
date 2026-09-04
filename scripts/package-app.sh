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
EXECUTABLE_SOURCE="$ROOT/.build/arm64-apple-macosx/release/Needlbar"
BRIDGE_ARCHIVE="$ROOT/target/release/libneedlbar_bridge.a"
INFO_PLIST="$ROOT/Resources/Info.plist"
NOTICES="$ROOT/Resources/ThirdPartyNotices.txt"
BRAND_VERIFIER="$ROOT/scripts/verify-provider-brand-assets.sh"
SOURCE_BRANDS="$ROOT/Sources/Needlbar/Resources/ProviderBrands"
SWIFTPM_RESOURCE_BUNDLE="$ROOT/.build/arm64-apple-macosx/release/Needlbar_NeedlbarApp.bundle"
PACKAGED_BRANDS="$CONTENTS_PATH/Resources/Needlbar_NeedlbarApp.bundle/ProviderBrands"
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

# SwiftPM does not track the unsafe linker archive as a build input. Remove only
# the stale release executable so the next build relinks without discarding the
# Swift object and module caches.
rm -f -- "$EXECUTABLE_SOURCE"

swift build --package-path "$ROOT" -c release --arch arm64
[[ -f "$EXECUTABLE_SOURCE" ]] || fail "release executable was not produced: $EXECUTABLE_SOURCE"

# Never clear the whole output directory: these are the only two package targets.
rm -rf -- "$APP_PATH"
rm -f -- "$ZIP_PATH"
mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources" "$CONTENTS_PATH/PlugIns"
[[ -d "$SWIFTPM_RESOURCE_BUNDLE" ]] || fail "release provider resource bundle was not produced: $SWIFTPM_RESOURCE_BUNDLE"
cp -R "$SWIFTPM_RESOURCE_BUNDLE" "$CONTENTS_PATH/Resources/"
"$BRAND_VERIFIER" "$PACKAGED_BRANDS"

install -m 755 "$EXECUTABLE_SOURCE" "$CONTENTS_PATH/MacOS/Needlbar"
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

# build-widget-extension.sh has already completed the inner signature.
# Sign the host only after the extension is embedded; do not use --deep here.
codesign --force --sign "$IDENTITY" --entitlements "$HOST_ENTITLEMENTS" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

# Archive from inside dist so Needlbar.app is the zip root rather than dist/.
# -X avoids host-specific extended attributes in this source-only app bundle.
(
  cd "$DIST_DIR"
  COPYFILE_DISABLE=1 /usr/bin/zip -qryX "$ZIP_PATH" "Needlbar.app"
)
[[ -f "$ZIP_PATH" ]] || fail "zip artifact was not produced: $ZIP_PATH"
