.PHONY: rust swift swift-test test run

rust:
	./scripts/build-rust.sh

swift: rust
	swift build

swift-test:
	swift test

test: rust
	cargo test --workspace
	swift test

run: rust
	swift run Needlbar
