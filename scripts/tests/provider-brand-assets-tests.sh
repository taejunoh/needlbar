#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
verifier="$root_dir/scripts/verify-provider-brand-assets.sh"
source_dir="$root_dir/Sources/Needlbar/Resources/ProviderBrands"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/needlbar-provider-brand-assets-tests.XXXXXX")
case "$tmp_dir" in
  "${TMPDIR:-/tmp}/needlbar-provider-brand-assets-tests."*) ;;
  *) echo "unexpected temporary directory: $tmp_dir" >&2; exit 1 ;;
esac
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

[ -d "$source_dir" ] || { echo "missing committed ProviderBrands directory" >&2; exit 1; }

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

assert_top_level_manifest() {
  manifest="$1/ProviderBrandAssets.plist"
  for resource_id in provider-brand-claude provider-brand-openai-blossom provider-brand-cursor-2d; do
    plutil -extract "$resource_id.provider" raw -o - "$manifest" >/dev/null 2>&1 || return 1
    plutil -extract "$resource_id.file" raw -o - "$manifest" >/dev/null 2>&1 || return 1
    plutil -extract "$resource_id.sourcePage" raw -o - "$manifest" >/dev/null 2>&1 || return 1
    plutil -extract "$resource_id.sourceAsset" raw -o - "$manifest" >/dev/null 2>&1 || return 1
    plutil -extract "$resource_id.variant" raw -o - "$manifest" >/dev/null 2>&1 || return 1
    plutil -extract "$resource_id.imageType" raw -o - "$manifest" >/dev/null 2>&1 || return 1
    plutil -extract "$resource_id.rendering" raw -o - "$manifest" >/dev/null 2>&1 || return 1
    plutil -extract "$resource_id.fallbackSymbol" raw -o - "$manifest" >/dev/null 2>&1 || return 1
    plutil -extract "$resource_id.sha256" raw -o - "$manifest" >/dev/null 2>&1 || return 1
  done
  ! plutil -extract assets raw -o - "$manifest" >/dev/null 2>&1
}

make_fixture() {
  fixture="$tmp_dir/$1"
  cp -R "$source_dir" "$fixture"
}

# Start from the real committed assets and manifest; do not synthesize a valid fixture.
make_fixture valid
expect_pass "$tmp_dir/valid"
if ! assert_top_level_manifest "$tmp_dir/valid"; then
  echo "expected top-level resource-ID manifest dictionaries" >&2
  exit 1
fi

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
cp "$source_dir/provider-brand-claude.png" "$tmp_dir/undeclared-png/extra.png"
expect_fail "$tmp_dir/undeclared-png"

printf '%s\n' 'provider brand asset fixture tests passed'
