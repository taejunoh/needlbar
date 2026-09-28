# Task 1 Report: Status-Line Quota Parsing and Merge

## Result

Implemented the pure Claude Code status-line quota parser and deterministic per-window merger. The parser accepts only the documented `rate_limits.five_hour` and `rate_limits.seven_day` fields, limits input to 256 KiB, validates finite percentages in `[0, 100]`, and accepts reset values only when they are integral Unix seconds. It returns schema version 1 and the supplied connection generation and receipt time. Missing or invalid windows remain unavailable independently; no Fable value is inferred.

The merger retains missing windows and their timestamps, ignores identical replays, older resets, reductions at the same reset, and reductions for undated windows. A changed nonregressing window gets the incoming receipt time. A reset advance can accept a lower percentage.

## RED

Command:

```text
swift test --filter StatusLineQuotaRecordTests
```

Observed failure before implementation:

```text
error: 'needlbar': Source files for target NeedlbarClaudeStatusLineSupport should be located under 'Sources/NeedlbarClaudeStatusLineSupport', or a custom sources path can be set with the 'path' property in Package.swift
```

This was the expected missing support-target source failure.

## GREEN

The focused test command requires the repository's test-only Rust bridge symbols. The prebuilt archive initially lacked those symbols, so I prepared the fixture archive with:

```text
PATH=/Users/taejunoh/.cargo/bin:$PATH ./scripts/build-rust.sh --features bridge-test-runtime
```

It exited 0 (`Finished release profile`). Then:

```text
swift test --filter StatusLineQuotaRecordTests
```

passed all 12 tests, including missing Fable/window, malformed and out-of-range values, invalid reset values, the 256 KiB cap, independent window merging, identical replay, older reset, same-reset regression, and undated-window rules.

Project-wide verification:

```text
PATH=/Users/taejunoh/.cargo/bin:$PATH make test
```

Exited 0. Rust workspace tests passed; vendored `tokscale-core` reported 1,379 passed and 1 ignored; Swift tests passed, including the 12 new tests; bridge, assets, widget, packaging, and notarization contract checks passed.

`git diff --check` exited 0.

## Changed files

- `Package.swift` — registered the support and test targets.
- `Sources/NeedlbarClaudeStatusLineSupport/StatusLineQuotaRecord.swift` — added record types, allowlist parser, and per-window merger.
- `Tests/NeedlbarClaudeStatusLineSupportTests/StatusLineQuotaRecordTests.swift` — added 12 focused parser and merger tests.

## Self-review and concerns

- No user Claude settings, credentials, or live status-line data were accessed or modified.
- The first direct focused test attempt could not link the existing Core test bundle because its Rust archive lacked test-only fixture symbols. Rebuilding the fixture archive resolved this; the prescribed focused command and full `make test` then passed.
- The project emitted existing Swift/macOS linker warnings during the full build; they did not fail verification and were outside Task 1 scope.
- No remaining Task 1 concerns identified.
