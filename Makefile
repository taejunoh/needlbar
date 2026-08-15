.PHONY: rust swift swift-test test run

rust:
	./scripts/build-rust.sh

swift: rust
	swift build

swift-test:
	@set -e; \
	symbols_file=$$(mktemp "$${TMPDIR:-/tmp}/needlbar-symbols.XXXXXX"); \
	restore_bridge() { \
		status=$$?; \
		trap - EXIT INT TERM; \
		restore_status=0; \
		if ! ./scripts/build-rust.sh; then restore_status=1; fi; \
		if [ $$restore_status -eq 0 ]; then \
			if ! strings target/release/libneedlbar_bridge.a > "$$symbols_file"; then \
				echo "failed to inspect restored bridge archive" >&2; \
				restore_status=1; \
			else \
				if grep -F 'needlbar_test_' "$$symbols_file" >/dev/null; then \
					echo "restored bridge archive contains test-only symbols" >&2; \
					restore_status=1; \
				else \
					grep_status=$$?; \
					if [ $$grep_status -gt 1 ]; then \
						echo "failed to inspect restored bridge symbols" >&2; \
						restore_status=1; \
					fi; \
				fi; \
			fi; \
		fi; \
		rm -f "$$symbols_file" || restore_status=1; \
		swift package clean || restore_status=1; \
		if [ $$restore_status -ne 0 ]; then exit $$restore_status; fi; \
		exit $$status; \
	}; \
	trap restore_bridge EXIT; \
	trap 'exit 130' INT; \
	trap 'exit 143' TERM; \
	./scripts/build-rust.sh --features bridge-test-runtime; \
	strings target/release/libneedlbar_bridge.a > "$$symbols_file"; \
	grep -F 'needlbar_test_install_fixture_runtime' "$$symbols_file" >/dev/null; \
	grep -F 'needlbar_test_clear_runtime' "$$symbols_file" >/dev/null; \
	swift package clean; \
	swift test

test:
	cargo test --workspace --features bridge-test-runtime
	$(MAKE) swift-test

run: rust
	swift run Needlbar
