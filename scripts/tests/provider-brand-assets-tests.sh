#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
verifier="$root_dir/scripts/verify-provider-brand-assets.sh"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/needlbar-provider-brand-assets-tests.XXXXXX")
case "$tmp_dir" in
  "${TMPDIR:-/tmp}/needlbar-provider-brand-assets-tests."*) ;;
  *) echo "unexpected temporary directory: $tmp_dir" >&2; exit 1 ;;
esac
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

png_data='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
mkdir -p "$tmp_dir/source"
printf '%s' "$png_data" | base64 -D > "$tmp_dir/source/provider-brand-claude.png"
printf '%s' "$png_data" | base64 -D > "$tmp_dir/source/provider-brand-openai-blossom.png"
printf '%s' "$png_data" | base64 -D > "$tmp_dir/source/provider-brand-cursor-2d.png"

claude_hash=$(shasum -a 256 "$tmp_dir/source/provider-brand-claude.png" | awk '{print $1}')
openai_hash=$(shasum -a 256 "$tmp_dir/source/provider-brand-openai-blossom.png" | awk '{print $1}')
cursor_hash=$(shasum -a 256 "$tmp_dir/source/provider-brand-cursor-2d.png" | awk '{print $1}')
cat > "$tmp_dir/manifest.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>assets</key>
  <array>
    <dict>
      <key>id</key><string>provider-brand-claude</string>
      <key>provider</key><string>claude</string>
      <key>variant</key><string>officialOrange</string>
      <key>sourcePage</key><string>https://brandfolder.com/anthropic/collection/newsroom</string>
      <key>sourceAsset</key><string>Anthropic media resources/Anthropic logos/Claude logos/3 Claude Spark/PNG/Claude Spark - Clay.png</string>
      <key>mimeType</key><string>image/png</string>
      <key>rendering</key><string>original PNG pixels and transparency</string>
      <key>fallbackSFSymbol</key><string>sparkles</string>
      <key>file</key><string>provider-brand-claude.png</string>
      <key>sha256</key><string>$claude_hash</string>
    </dict>
    <dict>
      <key>id</key><string>provider-brand-openai-blossom</string>
      <key>provider</key><string>codex</string>
      <key>variant</key><string>systemMonochrome</string>
      <key>sourcePage</key><string>https://openai.com/brand/</string>
      <key>sourceAsset</key><string>OpenAI-logos/PNGs/OAI_OpenAI-Blossom_Black.png</string>
      <key>mimeType</key><string>image/png</string>
      <key>rendering</key><string>original PNG pixels and transparency</string>
      <key>fallbackSFSymbol</key><string>chevron.left.forwardslash.chevron.right</string>
      <key>file</key><string>provider-brand-openai-blossom.png</string>
      <key>sha256</key><string>$openai_hash</string>
    </dict>
    <dict>
      <key>id</key><string>provider-brand-cursor-2d</string>
      <key>provider</key><string>cursor</string>
      <key>variant</key><string>systemMonochrome</string>
      <key>sourcePage</key><string>https://cursor.com/en-US/brand</string>
      <key>sourceAsset</key><string>General Logos/Cube/PNG/CUBE_2D_LIGHT.png</string>
      <key>mimeType</key><string>image/png</string>
      <key>rendering</key><string>original PNG pixels and transparency</string>
      <key>fallbackSFSymbol</key><string>cursorarrow</string>
      <key>file</key><string>provider-brand-cursor-2d.png</string>
      <key>sha256</key><string>$cursor_hash</string>
    </dict>
  </array>
</dict>
</plist>
EOF
printf '%s\n' 'Provider brand assets remain property of their respective providers.' > "$tmp_dir/TRADEMARKS.md"
printf '%s\n' 'Needlbar is not sponsored by, not endorsed by, and not affiliated with Anthropic, OpenAI, or Cursor. Provider terms remain in force.' >> "$tmp_dir/TRADEMARKS.md"

make_fixture() {
  fixture="$tmp_dir/$1"
  mkdir -p "$fixture"
  cp "$tmp_dir/source"/*.png "$fixture/"
  cp "$tmp_dir/manifest.plist" "$fixture/ProviderBrandAssets.plist"
  cp "$tmp_dir/TRADEMARKS.md" "$fixture/TRADEMARKS.md"
}

expect_pass() {
  if ! "$verifier" "$1" >/dev/null 2>&1; then
    echo "expected verifier success: $1" >&2
    exit 1
  fi
}

expect_fail() {
  if "$verifier" "$1" >/dev/null 2>&1; then
    echo "expected verifier failure: $1" >&2
    exit 1
  fi
}

make_fixture valid
expect_pass "$tmp_dir/valid"

make_fixture missing-cursor
rm "$tmp_dir/missing-cursor/provider-brand-cursor-2d.png"
expect_fail "$tmp_dir/missing-cursor"

make_fixture empty-claude
: > "$tmp_dir/empty-claude/provider-brand-claude.png"
expect_fail "$tmp_dir/empty-claude"

make_fixture non-png-openai
printf '%s\n' 'not a PNG' > "$tmp_dir/non-png-openai/provider-brand-openai-blossom.png"
expect_fail "$tmp_dir/non-png-openai"

make_fixture changed-cursor-hash
printf '\000' >> "$tmp_dir/changed-cursor-hash/provider-brand-cursor-2d.png"
expect_fail "$tmp_dir/changed-cursor-hash"

make_fixture undeclared-png
cp "$tmp_dir/source/provider-brand-claude.png" "$tmp_dir/undeclared-png/extra.png"
expect_fail "$tmp_dir/undeclared-png"

printf '%s\n' 'provider brand asset fixture tests passed'
