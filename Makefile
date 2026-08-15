.PHONY: rust swift swift-test test run

rust:
	./scripts/build-rust.sh

swift: rust
	swift build

swift-test:
	@set -e; \
	restore_bridge() { status=$$?; trap - EXIT INT TERM; ./scripts/build-rust.sh; ! nm -gU target/release/libneedlbar_bridge.a 2>/dev/null | rg 'needlbar_test_'; swift package clean; exit $$status; }; \
	trap restore_bridge EXIT; \
	trap 'exit 130' INT; \
	trap 'exit 143' TERM; \
	./scripts/build-rust.sh --features bridge-test-runtime; \
	nm -gU target/release/libneedlbar_bridge.a 2>/dev/null | rg 'needlbar_test_(install_fixture_runtime|clear_runtime)'; \
	swift package clean; \
	swift test

test:
	cargo test --workspace --features bridge-test-runtime
	$(MAKE) swift-test

run: rust
	swift run Needlbar
