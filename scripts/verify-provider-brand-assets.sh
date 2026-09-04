#!/bin/sh
set -eu

die() {
  echo "provider brand asset verification failed: $*" >&2
  exit 1
}

[ "$#" -eq 1 ] || die "expected exactly one ProviderBrands directory"
provider_dir=$1
[ -d "$provider_dir" ] || die "not a directory: $provider_dir"

manifest="$provider_dir/ProviderBrandAssets.plist"
notice="$provider_dir/TRADEMARKS.md"
[ -f "$manifest" ] || die "missing ProviderBrandAssets.plist"
[ -f "$notice" ] || die "missing TRADEMARKS.md"

plutil -lint "$manifest" >/dev/null 2>&1 || die "invalid ProviderBrandAssets.plist"

notice_text=$(tr '[:upper:]' '[:lower:]' < "$notice")
printf '%s\n' "$notice_text" | grep -Eq 'anthropic' || die "notice does not name Anthropic"
printf '%s\n' "$notice_text" | grep -Eq 'openai' || die "notice does not name OpenAI"
printf '%s\n' "$notice_text" | grep -Eq 'cursor' || die "notice does not name Cursor"
printf '%s\n' "$notice_text" | grep -Eq 'property of|owned by' || die "notice does not state provider ownership"
printf '%s\n' "$notice_text" | grep -Eq 'not sponsored by' || die "notice is missing non-sponsorship language"
printf '%s\n' "$notice_text" | grep -Eq 'not endorsed by' || die "notice is missing non-endorsement language"
printf '%s\n' "$notice_text" | grep -Eq 'not affiliated with' || die "notice is missing non-affiliation language"
printf '%s\n' "$notice_text" | grep -Eq 'terms remain in force' || die "notice is missing terms language"

asset_count=0
while plutil -extract "assets.$asset_count.id" raw -o - "$manifest" >/dev/null 2>&1; do
  asset_count=$((asset_count + 1))
done
[ "$asset_count" -eq 3 ] || die "manifest must declare exactly three assets"
seen_claude=0
seen_codex=0
seen_cursor=0

read_field() {
  plutil -extract "assets.$1.$2" raw -o - "$manifest" 2>/dev/null || die "missing assets.$1.$2"
}

for index in 0 1 2; do
  id=$(read_field "$index" id)
  provider=$(read_field "$index" provider)
  variant=$(read_field "$index" variant)
  source_page=$(read_field "$index" sourcePage)
  source_asset=$(read_field "$index" sourceAsset)
  mime_type=$(read_field "$index" mimeType)
  rendering=$(read_field "$index" rendering)
  fallback=$(read_field "$index" fallbackSFSymbol)
  file_name=$(read_field "$index" file)
  expected_hash=$(read_field "$index" sha256)

  [ -n "$source_asset" ] || die "$id has an empty sourceAsset"
  [ -n "$rendering" ] || die "$id has an empty rendering"
  [ -n "$source_page" ] || die "$id has an empty sourcePage"
  case "$source_page" in
    https://*) ;;
    *) die "$id sourcePage must use HTTPS" ;;
  esac
  [ "$mime_type" = image/png ] || die "$id must declare image/png"
  printf '%s\n' "$expected_hash" | grep -Eq '^[0-9A-Fa-f]{64}$' || die "$id has an invalid SHA-256"

  case "$id" in
    provider-brand-claude)
      [ "$seen_claude" -eq 0 ] || die "duplicate Claude asset mapping"
      seen_claude=1
      [ "$provider" = claude ] || die "incorrect Claude provider mapping"
      [ "$variant" = officialOrange ] || die "incorrect Claude variant mapping"
      [ "$fallback" = sparkles ] || die "incorrect Claude fallback mapping"
      [ "$file_name" = provider-brand-claude.png ] || die "incorrect Claude file mapping"
      [ "$source_page" = https://brandfolder.com/anthropic/collection/newsroom ] || die "incorrect Claude source page"
      [ "$source_asset" = 'Anthropic media resources/Anthropic logos/Claude logos/3 Claude Spark/PNG/Claude Spark - Clay.png' ] || die "incorrect Claude source asset"
      ;;
    provider-brand-openai-blossom)
      [ "$seen_codex" -eq 0 ] || die "duplicate Codex asset mapping"
      seen_codex=1
      [ "$provider" = codex ] || die "incorrect Codex provider mapping"
      [ "$variant" = systemMonochrome ] || die "incorrect Codex variant mapping"
      [ "$fallback" = chevron.left.forwardslash.chevron.right ] || die "incorrect Codex fallback mapping"
      [ "$file_name" = provider-brand-openai-blossom.png ] || die "incorrect Codex file mapping"
      [ "$source_page" = https://openai.com/brand/ ] || die "incorrect Codex source page"
      [ "$source_asset" = 'OpenAI-logos/PNGs/OAI_OpenAI-Blossom_Black.png' ] || die "incorrect Codex source asset"
      ;;
    provider-brand-cursor-2d)
      [ "$seen_cursor" -eq 0 ] || die "duplicate Cursor asset mapping"
      seen_cursor=1
      [ "$provider" = cursor ] || die "incorrect Cursor provider mapping"
      [ "$variant" = systemMonochrome ] || die "incorrect Cursor variant mapping"
      [ "$fallback" = cursorarrow ] || die "incorrect Cursor fallback mapping"
      [ "$file_name" = provider-brand-cursor-2d.png ] || die "incorrect Cursor file mapping"
      [ "$source_page" = https://cursor.com/en-US/brand ] || die "incorrect Cursor source page"
      [ "$source_asset" = 'General Logos/Cube/PNG/CUBE_2D_LIGHT.png' ] || die "incorrect Cursor source asset"
      ;;
    *) die "undeclared asset mapping: $id" ;;
  esac

  asset_path="$provider_dir/$file_name"
  [ -f "$asset_path" ] || die "missing asset file: $file_name"
  [ -s "$asset_path" ] || die "empty asset file: $file_name"
  [ "$(file -b --mime-type "$asset_path")" = image/png ] || die "asset is not PNG: $file_name"
  actual_hash=$(shasum -a 256 "$asset_path" | awk '{print $1}')
  [ "$actual_hash" = "$expected_hash" ] || die "SHA-256 mismatch: $file_name"
done

[ "$seen_claude" -eq 1 ] || die "missing Claude asset mapping"
[ "$seen_codex" -eq 1 ] || die "missing Codex asset mapping"
[ "$seen_cursor" -eq 1 ] || die "missing Cursor asset mapping"

for entry in "$provider_dir"/* "$provider_dir"/.[!.]*; do
  [ -e "$entry" ] || continue
  base_name=${entry##*/}
  case "$base_name" in
    ProviderBrandAssets.plist|TRADEMARKS.md|provider-brand-claude.png|provider-brand-openai-blossom.png|provider-brand-cursor-2d.png) ;;
    *) die "undeclared files present: $base_name" ;;
  esac
done

printf '%s\n' "verified provider brand assets: $provider_dir"
