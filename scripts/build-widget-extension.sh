#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/widget-extension"
TEAM_ID="${NEEDLBAR_TEAM_ID:-TESTTEAMID}"
GROUP_ID="${NEEDLBAR_APP_GROUP_IDENTIFIER:-$TEAM_ID.com.taejunoh.needlbar}"
IDENTITY="${NEEDLBAR_CODESIGN_IDENTITY:--}"
APP="$OUT/NeedlbarWidgetExtension.appex"
INFO_TEMPLATE="$ROOT/WidgetExtension/NeedlbarWidgetExtension-Info.plist"
ENTITLEMENTS_TEMPLATE="$ROOT/WidgetExtension/NeedlbarWidgetExtension.entitlements"
PROJECTION_SOURCE="$ROOT/Sources/NeedlbarWidgetSupport/WidgetProjection.swift"
PRESENTATION_SOURCE="$ROOT/Sources/NeedlbarWidgetSupport/WidgetPresentation.swift"
WIDGET_SOURCE="$ROOT/WidgetExtension/NeedlbarOverviewWidget.swift"

fail() {
  echo "build-widget-extension: $*" >&2
  exit 1
}

[[ -f "$INFO_TEMPLATE" ]] || fail "missing extension Info.plist: $INFO_TEMPLATE"
[[ -f "$ENTITLEMENTS_TEMPLATE" ]] || fail "missing extension entitlements: $ENTITLEMENTS_TEMPLATE"
[[ -f "$PROJECTION_SOURCE" ]] || fail "missing pure projection source: $PROJECTION_SOURCE"
[[ -f "$PRESENTATION_SOURCE" ]] || fail "missing pure presentation source: $PRESENTATION_SOURCE"
[[ -f "$WIDGET_SOURCE" ]] || fail "missing widget source: $WIDGET_SOURCE"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
command -v codesign >/dev/null 2>&1 || fail "codesign is required"

rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$INFO_TEMPLATE" "$APP/Contents/Info.plist"
cp "$ENTITLEMENTS_TEMPLATE" "$OUT/NeedlbarWidgetExtension.entitlements"

/usr/libexec/PlistBuddy -c "Set :NeedlbarAppGroupIdentifier $GROUP_ID" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $GROUP_ID" \
  "$OUT/NeedlbarWidgetExtension.entitlements"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
[[ -n "$SDK" ]] || fail "xcrun did not return a macOS SDK path"

xcrun swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  -swift-version 6 \
  -application-extension \
  -parse-as-library \
  -Xlinker -e \
  -Xlinker _NSExtensionMain \
  -emit-executable \
  -module-name NeedlbarWidgetExtension \
  -framework SwiftUI \
  -framework WidgetKit \
  "$PROJECTION_SOURCE" \
  "$PRESENTATION_SOURCE" \
  "$WIDGET_SOURCE" \
  -o "$APP/Contents/MacOS/NeedlbarWidgetExtension"

[[ -x "$APP/Contents/MacOS/NeedlbarWidgetExtension" ]] ||
  fail "swiftc did not produce the extension executable"

codesign --force --sign "$IDENTITY" \
  --entitlements "$OUT/NeedlbarWidgetExtension.entitlements" \
  "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ "$TEAM_ID" == TESTTEAMID ]]; then
  echo "widget extension built with synthetic App Group identity"
fi
