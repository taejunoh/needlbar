#!/bin/sh
set -eu

# A linked worktree can still discover the parent checkout's workspace when Cargo
# evaluates an excluded path dependency. Run the pinned submodule from an
# isolated Developer/LFG temporary directory so Makefile verification remains
# valid before the parent checkout receives the matching workspace exclusion.
temp_root=$(mktemp -d "/Users/taejunoh/Developer/LFG/needlbar-vendor-test.XXXXXX")
cleanup() {
    rm -rf "$temp_root"
}
trap cleanup EXIT INT TERM

rsync -a --exclude target --exclude .git vendor/tokscale-core/ "$temp_root/"
cargo test --manifest-path "$temp_root/Cargo.toml"
