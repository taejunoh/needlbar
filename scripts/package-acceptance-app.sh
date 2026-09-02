#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${NEEDLBAR_ACCEPTANCE_OUTPUT_ROOT:-$ROOT/.build/native-acceptance}"
APP="$OUT/Needlbar.app"
IDENTITY="${NEEDLBAR_CODESIGN_IDENTITY:-}"
TEAM_ID="${NEEDLBAR_TEAM_ID:-}"
GROUP_ID="${NEEDLBAR_APP_GROUP_IDENTIFIER:-$TEAM_ID.com.taejunoh.needlbar}"
EXECUTABLE_SOURCE="$ROOT/.build/arm64-apple-macosx/release/Needlbar"
HOST_ENTITLEMENTS="$OUT/NeedlbarHostWidget.entitlements"

fail() { echo "package-acceptance-app: $*" >&2; exit 1; }

[[ "$OUT" == "$ROOT"/.build/* ]] || fail 'output root must be below repository .build'
[[ -n "$IDENTITY" && "$IDENTITY" != "-" ]] || fail 'Developer ID identity is required'
[[ -n "$TEAM_ID" ]] || fail 'team identifier is required'
[[ -f "$ROOT/Resources/Info.plist" ]] || fail 'missing Info.plist'
[[ -f "$ROOT/Resources/ThirdPartyNotices.txt" ]] || fail 'missing third-party notices'
[[ -f "$ROOT/Resources/NeedlbarHostWidget.entitlements" ]] || fail 'missing host entitlements'

rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/PlugIns"

MACOSX_DEPLOYMENT_TARGET=14.0 \
NEEDLBAR_RUST_TARGET=aarch64-apple-darwin \
  make -C "$ROOT" rust

rm -f -- "$EXECUTABLE_SOURCE"
swift build --package-path "$ROOT" -c release --arch arm64 -Xswiftc -DNEEDLBAR_ACCEPTANCE_DRIVER
[[ -f "$EXECUTABLE_SOURCE" ]] || fail 'release executable was not produced'

install -m 755 "$EXECUTABLE_SOURCE" "$APP/Contents/MacOS/Needlbar"
install -m 644 "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
install -m 644 "$ROOT/Resources/ThirdPartyNotices.txt" "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp "$ROOT/Resources/NeedlbarHostWidget.entitlements" "$HOST_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :NeedlbarAppGroupIdentifier $GROUP_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $GROUP_ID" "$HOST_ENTITLEMENTS"

NEEDLBAR_TEAM_ID="$TEAM_ID" \
NEEDLBAR_APP_GROUP_IDENTIFIER="$GROUP_ID" \
NEEDLBAR_CODESIGN_IDENTITY="$IDENTITY" \
  "$ROOT/scripts/build-widget-extension.sh"
cp -R "$ROOT/.build/widget-extension/NeedlbarWidgetExtension.appex" "$APP/Contents/PlugIns/"

codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  --entitlements "$HOST_ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

strings "$APP/Contents/MacOS/Needlbar" | grep -F -- '--acceptance-fixture' >/dev/null ||
  fail 'acceptance host parser missing'
! strings "$APP/Contents/PlugIns/NeedlbarWidgetExtension.appex/Contents/MacOS/NeedlbarWidgetExtension" \
  | grep -F -- '--acceptance-fixture' >/dev/null || fail 'extension contains acceptance parser'
! find "$APP" -type f \( -name '*.json' -o -path '*/Fixtures/*' \) -print -quit | grep -q . ||
  fail 'fixture entered acceptance bundle'
[[ ! -e "$OUT/Needlbar-macos-arm64.zip" && ! -e "$OUT/Needlbar-macos-arm64.zip.sha256" ]] ||
  fail 'acceptance package created release artifact'
