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

manifest_dump=$(plutil -p "$manifest")
top_key_count=$(printf '%s\n' "$manifest_dump" | grep -Ec '^  "[^"]+" => \{' || true)
[ "$top_key_count" -eq 3 ] || die "manifest must contain exactly three resource IDs"
for resource_id in provider-brand-claude provider-brand-openai-blossom provider-brand-cursor-2d; do
  printf '%s\n' "$manifest_dump" | grep -Eq "^  \"$resource_id\" => \{" || die "missing resource ID: $resource_id"
done

field_count=$(printf '%s\n' "$manifest_dump" | grep -Ec '^    "[^"]+" =>' || true)
[ "$field_count" -eq 27 ] || die "manifest must contain exactly nine fields per resource"
field_lines=$(printf '%s\n' "$manifest_dump" | grep -E '^    "[^"]+" =>' || true)
while IFS= read -r field_line; do
  [ -n "$field_line" ] || continue
  field_name=$(printf '%s\n' "$field_line" | sed -E 's/^    "([^"]+)" =>.*/\1/')
  case "$field_name" in
    provider|file|sourcePage|sourceAsset|variant|imageType|rendering|fallbackSymbol|sha256) ;;
    *) die "unexpected manifest field: $field_name" ;;
  esac
done <<EOF
$field_lines
EOF
printf '%s\n' "$manifest_dump" | grep -Eq '^    "assets" =>' && die "legacy assets array is not allowed"

read_field() {
  plutil -extract "$1.$2" raw -o - "$manifest" 2>/dev/null || die "missing $1.$2"
}

verify_resource() {
  resource_id=$1
  expected_provider=$2
  expected_variant=$3
  expected_rendering=$4
  expected_fallback=$5
  expected_file=$6
  expected_page=$7
  expected_asset=$8

  provider=$(read_field "$resource_id" provider)
  file_name=$(read_field "$resource_id" file)
  source_page=$(read_field "$resource_id" sourcePage)
  source_asset=$(read_field "$resource_id" sourceAsset)
  variant=$(read_field "$resource_id" variant)
  image_type=$(read_field "$resource_id" imageType)
  rendering=$(read_field "$resource_id" rendering)
  fallback=$(read_field "$resource_id" fallbackSymbol)
  expected_hash=$(read_field "$resource_id" sha256)

  [ "$provider" = "$expected_provider" ] || die "incorrect provider mapping: $resource_id"
  [ "$variant" = "$expected_variant" ] || die "incorrect variant mapping: $resource_id"
  [ "$rendering" = "$expected_rendering" ] || die "incorrect rendering mapping: $resource_id"
  [ "$fallback" = "$expected_fallback" ] || die "incorrect fallback mapping: $resource_id"
  [ "$file_name" = "$expected_file" ] || die "incorrect file mapping: $resource_id"
  [ "$source_page" = "$expected_page" ] || die "incorrect source page: $resource_id"
  [ "$source_asset" = "$expected_asset" ] || die "incorrect source asset: $resource_id"
  [ -n "$source_asset" ] || die "$resource_id has an empty sourceAsset"
  [ -n "$variant" ] || die "$resource_id has an empty variant"
  [ "$image_type" = image/png ] || die "$resource_id must declare image/png"
  case "$source_page" in
    https://*) ;;
    *) die "$resource_id sourcePage must use HTTPS" ;;
  esac
  printf '%s\n' "$expected_hash" | grep -Eq '^[0-9A-Fa-f]{64}$' || die "$resource_id has an invalid SHA-256"

  asset_path="$provider_dir/$file_name"
  [ -f "$asset_path" ] || die "missing asset file: $file_name"
  [ -s "$asset_path" ] || die "empty asset file: $file_name"
  [ "$(file -b --mime-type "$asset_path")" = image/png ] || die "asset is not PNG: $file_name"
  actual_hash=$(shasum -a 256 "$asset_path" | awk '{print $1}')
  [ "$actual_hash" = "$expected_hash" ] || die "SHA-256 mismatch: $file_name"
}

verify_resource provider-brand-claude claude "Claude Spark - Clay" officialOrange sparkles \
  provider-brand-claude.png https://brandfolder.com/anthropic/collection/newsroom \
  'Anthropic media resources.zip :: Anthropic media resources/Anthropic logos/Claude logos/3 Claude Spark/PNG/Claude Spark - Clay.png'
verify_resource provider-brand-openai-blossom codex "OpenAI Blossom Black" systemMonochrome \
  chevron.left.forwardslash.chevron.right provider-brand-openai-blossom.png https://openai.com/brand/ \
  'openai-logos.zip :: OpenAI-logos/PNGs/OAI_OpenAI-Blossom_Black.png'
verify_resource provider-brand-cursor-2d cursor "Cursor Cube 2D Light" systemMonochrome cursorarrow \
  provider-brand-cursor-2d.png https://cursor.com/en-US/brand \
  'cursor-brand-assets.zip :: General Logos/Cube/PNG/CUBE_2D_LIGHT.png'

for entry in "$provider_dir"/* "$provider_dir"/.[!.]*; do
  [ -e "$entry" ] || continue
  base_name=${entry##*/}
  case "$base_name" in
    ProviderBrandAssets.plist|TRADEMARKS.md|provider-brand-claude.png|provider-brand-openai-blossom.png|provider-brand-cursor-2d.png) ;;
    *) die "undeclared files present: $base_name" ;;
  esac
done

printf '%s\n' "verified provider brand assets: $provider_dir"
