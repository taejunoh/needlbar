#!/usr/bin/env bash
set -euo pipefail

# Release builds strip debuginfo by default. Rust before 1.98 strips macOS
# dylibs with rust-objcopy, which can leave the __LINKEDIT string pool 4-byte
# aligned; macOS 27 dyld then refuses to load proc-macro dylibs and a clean
# release build fails (rust-lang/rust#157750). Host-only build units must stay
# unstripped. The shipped bridge archive is a staticlib and is never stripped.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "rust-release-profile-tests: $*" >&2
  exit 1
}

host_build_units_unstripped() {
  awk '
    /^[[:space:]]*\[/ {
      section = $0
      sub(/#.*/, "", section)
      gsub(/[[:space:]]/, "", section)
      next
    }
    section == "[profile.release.build-override]" &&
      /^[[:space:]]*strip[[:space:]]*=[[:space:]]*(false|"none")[[:space:]]*(#.*)?$/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$1"
}

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/needlbar-rust-release-profile.XXXXXX")"
trap 'rm -rf -- "$temp_root"' EXIT
manifest="$temp_root/Cargo.toml"

printf '%s\n' '[profile.release.build-override]' 'strip = false' > "$manifest"
host_build_units_unstripped "$manifest" || fail 'unstripped build-override was rejected'

printf '%s\n' '[profile.release.build-override]' 'strip = "none" # host only' > "$manifest"
host_build_units_unstripped "$manifest" || fail 'strip = "none" build-override was rejected'

printf '%s\n' '[workspace]' 'members = []' > "$manifest"
if host_build_units_unstripped "$manifest"; then
  fail 'manifest without a build-override strip setting was accepted'
fi

printf '%s\n' '[profile.release]' 'strip = false' > "$manifest"
if host_build_units_unstripped "$manifest"; then
  fail 'release-wide strip setting was accepted as a build-override'
fi

printf '%s\n' '[profile.release.build-override]' 'strip = "debuginfo"' > "$manifest"
if host_build_units_unstripped "$manifest"; then
  fail 'stripped build-override was accepted'
fi

host_build_units_unstripped "$ROOT/Cargo.toml" ||
  fail 'Cargo.toml must set strip = false under [profile.release.build-override]'

echo 'rust release profile contract passed'
