#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
vendor_root="$script_root/vendor/tokscale-core"

# A linked worktree can still discover an older parent Cargo workspace when
# Cargo evaluates an excluded path dependency. Find the parent of the highest
# ancestor manifest, then use a detached submodule worktree outside it.
temp_parent="$script_root"
highest_manifest=""
while [ "$temp_parent" != "/" ]; do
    if [ -f "$temp_parent/Cargo.toml" ]; then
        highest_manifest="$temp_parent"
    fi
    temp_parent=$(dirname "$temp_parent")
done
if [ -n "$highest_manifest" ]; then
    temp_parent=$(dirname "$highest_manifest")
fi

temp_root=$(mktemp -d "$temp_parent/needlbar-vendor-test.XXXXXX")
rmdir "$temp_root"
worktree_added=false
cleanup() {
    if [ "$worktree_added" = true ]; then
        git -C "$vendor_root" worktree remove --force "$temp_root" >/dev/null 2>&1 || true
    elif [ -d "$temp_root" ]; then
        rm -rf "$temp_root"
    fi
}
trap cleanup EXIT INT TERM

git -C "$vendor_root" worktree add --detach "$temp_root" HEAD >/dev/null
worktree_added=true
cargo test --manifest-path "$temp_root/Cargo.toml" --locked
