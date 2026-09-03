# Claude Fable Quota Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Show a separate Fable weekly remaining percentage and reset beneath Claude without changing its existing headline, menu bar, exports, widgets, or notifications.

**Architecture:** Reuse the existing Claude fetch and generic quota-window bridge/store. Parse one exact optional Fable entry into `claude.fable.weekly`; exclude that exact Claude window from headline and v1 export projections before the parser can emit it. Render an independently labeled dashboard detail using the existing quota freshness and date formatter, without introducing independent refresh state.

**Tech Stack:** Rust, serde/serde_json, chrono, Tokio, Swift 6, Swift Testing, SwiftUI/AppKit; existing Makefile verification.

---

## Authority, workspace, and execution gate

Approved design: `docs/superpowers/specs/2026-09-02-claude-fable-quota-design.md`, approved 2026-09-03. Read `AGENTS.md`, `docs/STATUS.md`, and the original v0.1 design/plan first. The focused approved Fable design governs this change; do not resume the stale bootstrap continuation text in AGENTS.

Worktree: `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/integration-main.d16P79`, branch `codex/claude-fable-quota`, starting implementation-plan parent `0343ccb`. Do not use Documents, modify the unrelated root checkout, or create another worktree over this work. The main agent orchestrates; use the AGENTS-prescribed Terra/Luna roles, give each worker explicit file ownership, and require spec/quality review between numbered tasks. Workers share this worktree and must preserve one another's changes. Do not push, merge, publish, alter credentials, or change user preferences without authorization.

**Task 0 PASSED on 2026-09-03 after provider-owned sign-in.** Its same-response semantics evidence is recorded below and in the approved design/STATUS. Tasks 1–4 may now proceed. All implementation fixture values below remain synthetic, not captured account responses.

Shell commands run from this worktree. Before Cargo/Make commands:

```bash
source /Users/taejunoh/.cargo/env
```

Use `make swift-test SWIFT_TEST_FILTER='pattern'` for narrow Swift tests: the target installs the bridge test runtime and restores the production archive. A bare `swift test` may fail to link test-only symbols. Never weaken assertions, extend unrelated process timeouts, or treat serial success as the normal full gate passing.

## File ownership map

| Task | Production files | Fixtures/tests |
| --- | --- | --- |
| 1: projections | `Sources/NeedlbarCore/Models/QuotaSnapshot.swift`, `Sources/NeedlbarCore/Presentation/HeadlineQuotaSelector.swift`, `Sources/NeedlbarCore/Export/SnapshotExporter.swift` | `Tests/NeedlbarCoreTests/HeadlineQuotaSelectorTests.swift`, `Tests/NeedlbarCoreTests/SnapshotExporterTests.swift` |
| 2: source adapter | `crates/needlbar-quota/src/providers/claude.rs` | new `Fixtures/quota/claude/usage-fable-success.json`, `crates/needlbar-quota/tests/claude.rs`, `crates/needlbar-bridge/tests/quota_contract.rs` |
| 3: presentation/state regression | `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`, `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift` | `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`, `Tests/NeedlbarCoreTests/ProviderSnapshotStoreTests.swift`, `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift` |
| 4: integration | no new production behavior | downstream regression files listed in Task 4, `README.md`, `docs/STATUS.md`, approved design evidence |

The Rust domain, C ABI, bridge envelope schema, widget/notification/acceptance allowlists, Settings, preferences, authentication, and shared bridge test runtime fixture remain unchanged. Preserve arbitrary pre-existing non-Fable quota IDs in headline selection; this is not a new four-ID allowlist.

### Task 0: Corroborate `percent` semantics before implementing numeric output

**Files:** Record sanitized evidence in the approved design and `docs/STATUS.md`; no application changes.

- [x] Obtain first-party evidence that the exact Fable `limits[].percent` field is used/utilization, not remaining or fraction of a shared weekly pool. Accept a first-party client/UI mapping, or a same-response comparison establishing that session/weekly `limits[].percent` equal corresponding legacy `five_hour.utilization` / `seven_day.utilization`. Reject static co-occurrence of unrelated strings, guessed legacy aliases, and token/cost-derived estimates. If evidence contradicts the mapping assumed below, revise the design with the user before implementation.
- [x] Keep investigation read-only and bounded. Reuse the production `BackgroundNoUI` resolver and exact existing HTTPS endpoint only; no browser cookies, raw credentials, new login, redirects, or persisted raw response. Any future diagnostic needs an outer wall-clock bound around credential resolution **and** transport, not just the HTTP timeout. Emit only phase markers and explicitly allowlisted semantic comparisons. Do not repeatedly rerun a stuck probe or open permission UI implicitly.
- [x] Record the source, check time, precise matching fields and conclusion without account identifiers or secrets. Task 0 passes only on actual semantics evidence; a successful synthetic test or HTTP 200 alone is insufficient.

Historical evidence before sign-in: two earlier HTTP 200 responses established Fable identity and field types, not its numeric meaning. On 2026-09-03 a corrected diagnostic's synthetic test mapped session 37 / weekly 64 / Fable 13 correctly. Its one live attempt emitted no output and exceeded 30 seconds despite a 15-second HTTP cap. Exact process 48962 was terminated and confirmed gone; the diagnostic was returned to Trash. There was no live numeric result, no extra retry, and no product change. The cause of that delay is not established.

Follow-up diagnostic evidence (2026-09-03): one authorized non-interactive attempt with flushed phase markers and a 20-second outer watchdog returned `credential_resolution=unavailable` after 6.849 seconds; it never reached HTTP. Synthetic tests prove actual timestamp equality (not merely format), exact-child termination, and final-output preservation. They do not close the live semantics gate. No retry or prompt occurred; the helper is recoverably in Trash. Explicit user permission for any diagnostic Keychain prompt has been requested but not granted. Do not run a prompt-capable diagnostic or implement Tasks 1–4 on this evidence alone.

Subsequent authorization (2026-09-03): the user approved one diagnostic macOS Keychain prompt for the exact `Claude Code-credentials` item. A bounded `UserInitiatedAllowUI` diagnostic is now authorized as a narrow exception to the earlier no-prompt diagnostic restriction. The user must make the system permission choice; do not automate it or persist credentials. This changes neither product background behavior nor the requirement to corroborate source semantics before Tasks 1–4.

Result of that one-shot authorization (2026-09-03): `UserInitiatedAllowUI` credential resolution returned `expired` after 4.868 seconds, before HTTP. No prompt was reported and no credential or HTTP body was printed or retained. The helper was returned to Trash without retry. That authorization is now consumed. Ask the user to complete provider-owned **Sign in with Claude** in Needlbar Settings; do not repeatedly request Keychain permission or silently refresh credentials. Task 0 stays unchecked until the renewed credential yields corroborating first-party semantics.

**Passing evidence after the user completed sign-in:** at `2026-09-03T14:16:43.832932Z`, one bounded `BackgroundNoUI` request returned HTTP 200 in 3.902 seconds. Session percent 59 equaled five-hour utilization 59 and both reset timestamps matched exactly. Weekly-all percent 12 equaled seven-day utilization 12, again with equal resets. Exactly one Fable entry matched all four identity fields, with percent 14 and reset `2026-09-10T09:59:59.792368Z` (`is_active=false`, not an availability filter). These non-50 same-response comparisons close the approved meaning gate: Fable normalized usedPercent is 14 and derived remaining at capture was 86%. No new UI/login/refresh/retry occurred, no raw body/credential was retained, and the helper was returned to Trash. The earlier blocked instructions in this history are superseded by this passing result.

### Task 1: Protect existing headline and export projections

**Files:** Task 1 row above. Add tests before implementation, using literal Fable IDs in RED tests so failure is behavioral rather than an undefined constant.

- [x] Append this regression to `HeadlineQuotaSelectorTests.swift`:

```swift
@Test func fableDoesNotChangeHeadlineButOtherUnknownWindowsRemainEligible() throws {
    func snapshot(_ windows: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(provider: .claude, usage: nil, quota: .init(windows: windows),
                         usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: .now)
    }
    let base = try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil)
    let fable = try QuotaWindow(id: "claude.fable.weekly", title: "Fable weekly", usedPercent: 100, resetsAt: nil)
    let unknown = try QuotaWindow(id: "claude.future", title: "Future", usedPercent: 99, resetsAt: nil)
    #expect(HeadlineQuotaSelector.mostConstrained([snapshot([base, fable])]) == base)
    #expect(HeadlineQuotaSelector.mostConstrained([snapshot([base, fable, unknown])]) == unknown)
    #expect(HeadlineQuotaSelector.mostConstrained([snapshot([fable])]) == nil)
}
```

- [x] Append this regression to `SnapshotExporterTests.swift`. Reuse its existing private fixture helpers and handwritten golden; `replacingProvider` returns an `ExportCapture`, not a provider state.

```swift
@Test func fableWindowIsOmittedFromV1ExportWithoutChangingCanonicalBytes() throws {
    let baseline = try validExportCaptureWithPrivacyCanaries()
    let claude = baseline.providers[0]
    let fable = try QuotaWindow(id: "claude.fable.weekly", title: "Fable weekly",
        usedPercent: 100, resetsAt: try date("2026-08-30T12:00:00.000Z"))
    let capture = replacingProvider(claude,
        quota: QuotaSnapshot(windows: (claude.quota?.windows ?? []) + [fable]), in: baseline)
    #expect(try SnapshotExporter().encode(capture)
        == Data(completeHandWrittenV1GoldenJSONWithFinalNewline.utf8))
}
```

- [x] Run RED:

```bash
make swift-test SWIFT_TEST_FILTER='fableDoesNotChangeHeadline|fableWindowIsOmitted'
```

Expected: Fable wrongly wins the headline; export throws for the otherwise valid Fable window. Record those failures before changing production code.

- [x] Append the shared identifier to `QuotaSnapshot.swift`:

```swift
public extension QuotaWindow {
    static let claudeFableWeeklyID = "claude.fable.weekly"
}
```

Replace `HeadlineQuotaSelector.mostConstrained` only:

```swift
public static func mostConstrained(_ snapshots: [ProviderSnapshot]) -> QuotaWindow? {
    snapshots
        .filter { $0.provider == .claude || $0.provider == .codex }
        .flatMap { snapshot in
            (snapshot.quota?.windows ?? []).filter {
                !(snapshot.provider == .claude && $0.id == QuotaWindow.claudeFableWeeklyID)
            }
        }
        .min { $0.remainingPercent < $1.remainingPercent }
}
```

- [x] In the existing private `SnapshotExportValidation` extension add:

```swift
static func v1Windows(_ quota: QuotaSnapshot, for provider: ProviderID) -> [QuotaWindow] {
    quota.windows.filter {
        !(provider == .claude && $0.id == QuotaWindow.claudeFableWeeklyID)
    }
}
```

Change its window-validation loop header to `for window in v1Windows(quota, for: state.provider) {`; retain the entire existing validation body, including all unknown-ID rejections. In `SnapshotExportProvider.init(_:)`, replace only the quota assignment:

```swift
quota = .init(
    data: state.quota.map { SnapshotExportQuota($0, provider: state.provider) },
    status: .init(state.quotaStatus, lastSuccessfulAt: state.quotaLastSuccessfulAt)
)
```

Replace `SnapshotExportQuota`'s initializer, leaving canonical JSON serialization unchanged:

```swift
init(_ quota: QuotaSnapshot, provider: ProviderID) {
    windows = SnapshotExportValidation.v1Windows(quota, for: provider)
        .map(SnapshotExportQuotaWindow.init)
}
```

- [x] Run GREEN and existing rejection/golden tests:

```bash
make swift-test SWIFT_TEST_FILTER='fable|mostConstrained|Export|export'
git diff --check
make test
```

Expected: focused tests pass, golden bytes unchanged, unknown IDs still rejected. Record the actual full result; a known infrastructure failure is not a passing task-completion gate. Update STATUS with evidence before committing a checkpoint.

- [x] Commit only these scoped files and STATUS:

```bash
git add Sources/NeedlbarCore/Models/QuotaSnapshot.swift Sources/NeedlbarCore/Presentation/HeadlineQuotaSelector.swift Sources/NeedlbarCore/Export/SnapshotExporter.swift Tests/NeedlbarCoreTests/HeadlineQuotaSelectorTests.swift Tests/NeedlbarCoreTests/SnapshotExporterTests.swift docs/STATUS.md
git commit -m "fix: preserve quota projections when Claude adds Fable"
```

### Task 2: Parse one optional exact Fable window

**Files:** Task 2 row above. No credential/transport/domain/bridge implementation edits.

- [x] Create synthetic `Fixtures/quota/claude/usage-fable-success.json`:

```json
{
  "five_hour": {"utilization": 42.5, "resets_at": "2030-02-01T01:00:00Z"},
  "seven_day": {"utilization": 80, "resets_at": "2030-02-08T01:00:00Z"},
  "limits": [{
    "kind": "weekly_scoped", "group": "weekly",
    "scope": {"model": {"display_name": "Fable", "id": null}, "surface": null},
    "is_active": false, "percent": 25,
    "resets_at": "2030-02-09T01:00:00Z"
  }]
}
```

- [x] In `crates/needlbar-quota/tests/claude.rs` add these fixture-driven tests. Existing imports already expose `ClaudeQuotaProvider`; use fully qualified serde_json in the new helpers.

```rust
const FABLE_SUCCESS_FIXTURE: &str =
    include_str!("../../../Fixtures/quota/claude/usage-fable-success.json");

fn fable_payload() -> serde_json::Value {
    serde_json::from_str(FABLE_SUCCESS_FIXTURE).unwrap()
}

#[test]
fn fable_is_an_additive_used_percent_window_even_when_inactive() {
    let snapshot = ClaudeQuotaProvider::parse_usage_payload(FABLE_SUCCESS_FIXTURE).unwrap();
    assert_eq!(snapshot.windows.len(), 3);
    assert_eq!(snapshot.windows[0].used_percent(), 42.5);
    assert_eq!(snapshot.windows[1].used_percent(), 80.0);
    let fable = &snapshot.windows[2];
    assert_eq!(fable.id(), "claude.fable.weekly");
    assert_eq!(fable.title(), "Fable weekly");
    assert_eq!(fable.used_percent(), 25.0);
    assert_eq!(fable.resets_at().unwrap().timestamp(), 1_896_829_200);
}

#[test]
fn malformed_or_unmatched_fable_preserves_both_base_windows() {
    use serde_json::{json, Value};
    let mut cases = Vec::new();
    let mut missing = fable_payload();
    missing.as_object_mut().unwrap().remove("limits");
    cases.push(missing);
    for limits in [Value::Null, json!({}), json!("invalid"), json!([]), json!([null])] {
        let mut payload = fable_payload();
        payload["limits"] = limits;
        cases.push(payload);
    }
    for (pointer, invalid) in [
        ("/limits/0/percent", json!(-1)),
        ("/limits/0/percent", json!(101)),
        ("/limits/0/percent", json!("25")),
        ("/limits/0/percent", Value::Null),
        ("/limits/0/resets_at", json!("not-a-date")),
        ("/limits/0/resets_at", json!(123)),
        ("/limits/0/kind", json!("weekly_all")),
        ("/limits/0/group", json!("session")),
        ("/limits/0/scope/model/display_name", json!("Omelette")),
        ("/limits/0/scope/surface", json!("cli")),
    ] {
        let mut payload = fable_payload();
        *payload.pointer_mut(pointer).unwrap() = invalid;
        cases.push(payload);
    }
    for (object, field) in [("/limits/0", "percent"), ("/limits/0/scope", "surface")] {
        let mut payload = fable_payload();
        payload.pointer_mut(object).unwrap().as_object_mut().unwrap().remove(field);
        cases.push(payload);
    }
    let mut duplicate = fable_payload();
    let entry = duplicate["limits"][0].clone();
    duplicate["limits"].as_array_mut().unwrap().push(entry);
    cases.push(duplicate);
    for (index, payload) in cases.into_iter().enumerate() {
        let snapshot = ClaudeQuotaProvider::parse_usage_payload(&payload.to_string()).unwrap();
        assert_eq!(snapshot.windows.len(), 2, "case {index}");
        assert_eq!(snapshot.windows[0].used_percent(), 42.5);
        assert_eq!(snapshot.windows[1].used_percent(), 80.0);
    }
}

#[test]
fn fable_unknown_reset_and_opaque_metadata_remain_valid() {
    for remove_reset in [false, true] {
        let mut payload = fable_payload();
        payload["limits"][0]["resets_at"] = serde_json::Value::Null;
        if remove_reset {
            payload["limits"][0].as_object_mut().unwrap().remove("resets_at");
        }
        payload["limits"][0]["percent"] = serde_json::json!(0);
        payload["limits"][0]["scope"]["model"]["id"] = serde_json::json!("synthetic-opaque-id");
        payload["limits"][0].as_object_mut().unwrap().remove("is_active");
        let snapshot = ClaudeQuotaProvider::parse_usage_payload(&payload.to_string()).unwrap();
        assert_eq!(snapshot.windows.len(), 3);
        assert_eq!(snapshot.windows[2].used_percent(), 0.0);
        assert_eq!(snapshot.windows[2].resets_at(), None);
    }
}

#[test]
fn optional_fable_does_not_relax_required_base_window_validation() {
    let mut payload = fable_payload();
    payload["five_hour"]["utilization"] = serde_json::json!(101);
    assert!(ClaudeQuotaProvider::parse_usage_payload(&payload.to_string()).is_err());
}
```

- [x] Run RED: `cargo test -p needlbar-quota --test claude`. The valid additive and unknown-reset tests must fail with only two windows before the implementation.

- [x] In `claude.rs`, add `use serde_json::Value;`, and add `#[serde(default)] limits: Option<Value>` to the existing `UsageResponse`. Replace only the existing associated parser:

```rust
pub fn parse_usage_payload(payload: &str) -> Result<ProviderQuotaSnapshot, QuotaError> {
    let response: UsageResponse = serde_json::from_str(payload).map_err(|_| schema_error())?;
    let session = parse_window(response.five_hour, "claude.session", "Session")?;
    let weekly = parse_window(response.seven_day, "claude.weekly", "Weekly")?;
    let mut windows = vec![session, weekly];
    if let Some(fable) = parse_fable_window(response.limits.as_ref()) {
        windows.push(fable);
    }
    Ok(ProviderQuotaSnapshot { provider: ProviderId::Claude, windows })
}
```

Add these private helpers outside the impl, using its existing chrono imports:

```rust
fn is_fable_weekly_candidate(limit: &Value) -> bool {
    limit.get("kind").and_then(Value::as_str) == Some("weekly_scoped")
        && limit.get("group").and_then(Value::as_str) == Some("weekly")
        && limit.pointer("/scope/model/display_name").and_then(Value::as_str) == Some("Fable")
        && limit.pointer("/scope/surface").is_some_and(Value::is_null)
}

fn parse_optional_fable_reset(limit: &Value) -> Option<Option<DateTime<Utc>>> {
    match limit.get("resets_at") {
        None | Some(Value::Null) => Some(None),
        Some(Value::String(value)) => DateTime::parse_from_rfc3339(value)
            .ok().map(|value| Some(value.with_timezone(&Utc))),
        Some(_) => None,
    }
}

fn parse_fable_window(limits: Option<&Value>) -> Option<QuotaWindow> {
    let mut candidates = limits?.as_array()?.iter()
        .filter(|value| is_fable_weekly_candidate(value));
    let candidate = candidates.next()?;
    if candidates.next().is_some() { return None; }
    let percent = candidate.get("percent")?.as_f64()?;
    let resets_at = parse_optional_fable_reset(candidate)?;
    QuotaWindow::new("claude.fable.weekly", "Fable weekly", percent, resets_at).ok()
}
```

The domain already rejects non-finite/out-of-range percentages. Optional decoding via `Value` prevents a malformed limits shape from failing required base data. Count identity matches before validating numeric/reset fields: a second matching entry is ambiguous even if malformed. Do not filter on `is_active`, or infer Fable from a model ID/legacy field.

- [x] Add this additive-envelope regression to `crates/needlbar-bridge/tests/quota_contract.rs`, reusing `RecordingClaudeSource` and existing imports. It requires no bridge implementation change:

```rust
#[tokio::test]
async fn bridge_keeps_fable_as_an_additive_claude_window() {
    let accesses = Arc::new(Mutex::new(Vec::new()));
    let collection = collect_claude_user_initiated_with_source(Arc::new(RecordingClaudeSource {
        accesses: Arc::clone(&accesses),
        result: Ok(ClaudeQuotaProvider::parse_usage_payload(include_str!(
            "../../../Fixtures/quota/claude/usage-fable-success.json"
        )).unwrap()),
    })).await;
    let value = serde_json::to_value(envelope_from_collection(collection)).unwrap();
    let windows = &value["data"]["providers"][0]["windows"];
    assert_eq!(*accesses.lock().unwrap(), vec![ClaudeCredentialAccess::UserInitiatedAllowUI]);
    assert_eq!(windows.as_array().map(Vec::len), Some(3));
    assert_eq!(windows[2]["id"], "claude.fable.weekly");
    assert_eq!(windows[2]["usedPercent"].as_f64(), Some(25.0));
    assert_eq!(windows[2]["resetsAt"], "2030-02-09T01:00:00Z");
    assert_eq!(value["errors"], serde_json::json!([]));
}
```

- [x] Run GREEN:

```bash
cargo fmt --all
cargo test -p needlbar-quota --test claude
cargo test -p needlbar-bridge --test quota_contract
cargo clippy -p needlbar-quota -p needlbar-bridge --all-targets -- -D warnings
git diff --check
make test
```

Expected: valid Fable emits a third window, optional failures preserve the two base windows, base failures still reject the snapshot. Record actual full-gate status in STATUS.

- [x] Commit scoped files:

```bash
git add Fixtures/quota/claude/usage-fable-success.json crates/needlbar-quota/src/providers/claude.rs crates/needlbar-quota/tests/claude.rs crates/needlbar-bridge/tests/quota_contract.rs docs/STATUS.md
git commit -m "feat: normalize optional Claude Fable weekly quota"
```

### Task 3: Present separate Fable remaining/reset with existing freshness

**Files:** Task 3 row above. Keep the fixed 360-point width, maximum height and scroll container unchanged.

- [x] Extend the existing `dashboardFixtureSnapshot` helper in `SystemDashboardPopoverTests.swift`: insert `claudeQuotaWindows: [QuotaWindow]? = nil` after `claudeHasQuota`. Replace only its provider quota expression with:

```swift
quota: {
    if (provider == .claude && !claudeHasQuota) || (provider == .cursor && !cursorHasQuota) { return nil }
    if provider == .claude, let claudeQuotaWindows { return QuotaSnapshot(windows: claudeQuotaWindows) }
    return QuotaSnapshot(windows: [try! QuotaWindow(
        id: "window", title: "Window", usedPercent: provider == .codex ? 45 : 68, resetsAt: nil)])
}(),
```

Append these tests in that file:

```swift
@Test func dashboardFableDetailIsSeparateAndUsesQuotaFreshness() throws {
    let reset = Date(timeIntervalSince1970: 20_000)
    let windows = [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
        try QuotaWindow(id: "claude.fable.weekly", title: "Fable weekly", usedPercent: 100, resetsAt: reset)
    ]
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeQuotaWindows: windows),
        configuration: SystemMonitorConfiguration())
    let claude = try #require(presentation.ai.first { $0.provider == .claude })
    #expect(claude.value == "32%")
    #expect(claude.fable?.remaining == "0%")
    #expect(claude.fable?.resetCaption == String(localized: "Resets \(MetricFormatter.reset(reset)!)"))
    #expect(claude.fable?.freshness == .fresh)
    #expect(presentation.ai.filter { $0.provider != .claude }.allSatisfy { $0.fable == nil })
    let stale = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeQuotaStatus: .stale(lastSuccessfulAt: reset), claudeQuotaWindows: windows),
        configuration: SystemMonitorConfiguration())
    #expect(stale.ai.first { $0.provider == .claude }?.fable?.freshness == .stale)
}

@Test func dashboardFableMissingAndUnknownResetNeverInventCapacity() throws {
    let configuration = SystemMonitorConfiguration()
    let missing = SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: configuration)
    let absent = try #require(missing.ai.first { $0.provider == .claude })
    #expect(absent.fable?.remaining == "—")
    #expect(absent.fable?.freshness == .unavailable)
    #expect(absent.action == nil)
    let quota = [try QuotaWindow(id: "claude.fable.weekly", title: "Fable weekly", usedPercent: 25, resetsAt: nil)]
    let unknownReset = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeQuotaWindows: quota), configuration: configuration)
    #expect(unknownReset.ai.first { $0.provider == .claude }?.fable?.remaining == "75%")
    #expect(unknownReset.ai.first { $0.provider == .claude }?.fable?.resetCaption == String(localized: "Reset unavailable"))
    for hasQuota in [false, true] {
        let failed = SystemDashboardPresentation(
            snapshot: dashboardFixtureSnapshot(claudeQuotaStatus: .requiresAuthentication, claudeHasQuota: hasQuota),
            configuration: configuration)
        #expect(failed.ai.first { $0.provider == .claude }?.fable?.remaining == "—")
    }
}

@Test func dashboardFableOnlyAppearsForVisibleClaudeRemaining() {
    var configuration = SystemMonitorConfiguration()
    for metric in [AIProviderDisplayMetric.usage, .cost] {
        configuration.ai[.claude] = AIProviderDisplayPreference(isVisible: true, metric: metric)
        let presentation = SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: configuration)
        #expect(presentation.ai.first { $0.provider == .claude }?.fable == nil)
    }
    configuration.ai[.claude] = AIProviderDisplayPreference(isVisible: false, metric: .remaining)
    let hidden = SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: configuration)
    #expect(!hidden.ai.contains { $0.provider == .claude })
}
```

- [x] Run RED: `make swift-test SWIFT_TEST_FILTER='dashboardFable'`. Initially expect missing `fable` presentation API; this is the intended new model contract.

- [x] In `SystemDashboardPresentation`, introduce the nested detail and append the optional field to nested `AIProvider`:

```swift
public struct FableQuotaDetail: Equatable, Sendable {
    public let remaining: String
    public let resetCaption: String
    public let freshness: PresentationFreshness
}
```

```swift
public let fable: FableQuotaDetail?
```

In its sole AIProvider construction retain all existing arguments and append:

```swift
fable: Self.fableDetail(provider: provider, metric: preference.metric, snapshot: providerSnapshot)
```

Add the private helper inside `SystemDashboardPresentation`:

```swift
private static func fableDetail(
    provider: ProviderID, metric: AIProviderDisplayMetric, snapshot: ProviderSnapshot?
) -> FableQuotaDetail? {
    guard provider == .claude, metric == .remaining else { return nil }
    guard let window = snapshot?.quota?.windows.first(where: { $0.id == QuotaWindow.claudeFableWeeklyID }) else {
        return .init(remaining: "—", resetCaption: String(localized: "Reset unavailable"), freshness: .unavailable)
    }
    let resetCaption = MetricFormatter.reset(window.resetsAt)
        .map { String(localized: "Resets \($0)") } ?? String(localized: "Reset unavailable")
    return .init(remaining: MetricFormatter.quotaRemaining(window.remainingPercent),
                 resetCaption: resetCaption,
                 freshness: PresentationFreshness(snapshot?.quotaStatus ?? .unavailable))
}
```

- [x] In `SystemDashboardPopoverView`'s existing provider `ForEach`, wrap the existing header `HStack` **including its existing accessibility modifiers** in a `VStack(alignment: .leading, spacing: 4)`. Add the following sibling after the header. Do not put it beneath the header's explicit accessibility label, which would mask the new detail.

```swift
if let fable = provider.fable {
    VStack(alignment: .leading, spacing: 2) {
        HStack {
            Text("Fable weekly")
            Spacer(minLength: 8)
            Text("\(fable.remaining) remaining").monospacedDigit()
        }
        Text("\(fable.resetCaption) · \(fable.freshness.label)")
            .font(.caption2)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.leading, 24)
    .accessibilityElement(children: .combine)
}
```

Use SwiftUI localized literal text and the existing absolute localized date formatter. `resetCaption` already includes its prefix; never produce “Reset Reset unavailable.” This child has no button, separate authentication action, network request, or persistent state.

- [x] Append an independent store regression in `ProviderSnapshotStoreTests.swift` (within its suite):

```swift
@Test func fableLastKnownGoodSurvivesFailureButSuccessfulOmissionClearsIt() async throws {
    let date = Date(timeIntervalSince1970: 20_000)
    let store = ProviderSnapshotStore(now: { date })
    let base = try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil)
    let fable = try QuotaWindow(id: "claude.fable.weekly", title: "Fable weekly", usedPercent: 25, resetsAt: date)
    await store.applyQuota(.init(windows: [base, fable]), for: .claude, at: date)
    await store.markQuotaFailure(for: .claude, status: .requiresAuthentication, at: date)
    let failed = await store.snapshot(for: .claude)
    #expect(failed.quota?.windows == [base, fable])
    #expect(failed.quotaStatus != .fresh)
    await store.applyQuota(.init(windows: [base]), for: .claude, at: date)
    let success = await store.snapshot(for: .claude)
    #expect(success.quota?.windows == [base])
    #expect(success.quotaStatus == .fresh)
    #expect(success.usageStatus == .unavailable)
}
```

- [x] Append a generic bridge-decoding regression to `BridgeDecodingTests.swift`:

```swift
@Test func quotaEnvelopePreservesAdditiveFableWindow() throws {
    let payload = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2030-02-01T00:00:00Z","errors":[],
     "data":{"providers":[{"provider":"claude","windows":[
      {"id":"claude.session","title":"Session","usedPercent":68,"resetsAt":null},
      {"id":"claude.fable.weekly","title":"Fable weekly","usedPercent":25,"resetsAt":"2030-02-09T01:00:00Z"}
     ]}]}}
    """
    let envelope = try BridgeDecoder().decodeQuotaEnvelope(Data(payload.utf8))
    let provider = try #require(envelope.data?.providers.first)
    #expect(provider.quota.windows.map(\.id) == ["claude.session", "claude.fable.weekly"])
    #expect(provider.quota.windows.last?.remainingPercent == 75)
    #expect(provider.quota.windows.last?.resetsAt == BridgeDecoder.date("2030-02-09T01:00:00Z"))
}
```

- [x] Run GREEN, including existing layout and independent freshness tests:

```bash
make swift-test SWIFT_TEST_FILTER='dashboard|ProviderSnapshotStoreTests|quotaEnvelope|PopoverPresentation'
git diff --check
make test
```

Expected: fixed width/height tests remain green, no missing-data token fallback, stale label follows quota not usage, successful omission removes the old Fable detail. Existing provider detail renders the generic Fable window without another special-case view. Record full-gate status in STATUS.

- [x] Commit scoped files:

```bash
git add Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift Tests/NeedlbarTests/SystemDashboardPopoverTests.swift Tests/NeedlbarCoreTests/ProviderSnapshotStoreTests.swift Tests/NeedlbarCoreTests/BridgeDecodingTests.swift docs/STATUS.md
git commit -m "feat: show separate Claude Fable remaining and reset"
```

### Task 4: Verify downstream contracts and native presentation

**Files:** `Tests/NeedlbarCoreTests/WidgetProjectionTests.swift`, `Tests/NeedlbarCoreTests/QuotaAlertPolicyTests.swift`, `Tests/NeedlbarTests/QuotaNotificationServiceTests.swift`, `Tests/NeedlbarTests/MenuBarTitleRendererTests.swift`, `Tests/NeedlbarTests/MenuBarDashboardRendererTests.swift`, `Tests/NeedlbarTests/AcceptanceFixtureTests.swift`; README and STATUS. Never broaden widget/notification/acceptance allowlists to make a test pass.

- [x] In `WidgetProjectionTests.swift`, append this entry to the local `claudeQuota` array in `mapperFiltersProviderAndBreaksHeadlineTiesByLexicalID`. Keep its expected headline `.claudeSession` unchanged:

```swift
try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "private",
               usedPercent: 100, resetsAt: now.addingTimeInterval(3600)),
```

In `QuotaAlertPolicyTests.swift`, append to `keyAllowsOnlyFourKnownProviderWindows`:

```swift
#expect(throws: QuotaAlertLedgerStoreError.self) {
    _ = try QuotaAlertKey(provider: .claude, windowID: QuotaWindow.claudeFableWeeklyID)
}
```

In `QuotaNotificationServiceTests.swift`, replace the two Claude `applyQuota` calls in `allowlistedWindowsAreIndependentAndProcessedInStableIDOrder` with the following, retaining the existing reconcile/baseline steps between them and the two existing expected submissions. This helper accepts **remaining**, unlike `QuotaWindow.init`:

```swift
await fixture.applyQuota(
    windows: [("claude.session", 80), ("claude.weekly", 80), ("claude.fable.weekly", 80)],
    for: .claude
)
```

```swift
await fixture.applyQuota(
    windows: [("claude.session", 20), ("claude.weekly", 10), ("claude.fable.weekly", 0)],
    for: .claude
)
```

- [x] Append these menu regressions in their named files, reusing existing helpers without broad fixture changes. `MenuBarTitleRendererTests.swift`:

```swift
@Test func fableDoesNotChangeClaudeQuotaTitle() throws {
    let defaults = freshDefaults()
    let configuration = ModuleConfiguration(defaults: defaults)
    configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
    let base = snapshot(provider: .claude, usedPercent: 68)
    let fable = try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID,
        title: "Fable weekly", usedPercent: 100, resetsAt: nil)
    let augmented = ProviderSnapshot(
        provider: base.provider, usage: base.usage,
        quota: .init(windows: (base.quota?.windows ?? []) + [fable]),
        usageStatus: base.usageStatus, quotaStatus: base.quotaStatus, updatedAt: base.updatedAt)
    #expect(MenuBarTitleRenderer.render(module: .claude, snapshot: augmented,
        allSnapshots: [augmented], configuration: configuration) == "Claude 32%")
}
```

`MenuBarDashboardRendererTests.swift`:

```swift
@Test func fableDoesNotChangeAdaptiveMenuTitleOrTooltip() throws {
    var configuration = fixtureMonitorConfiguration()
    configuration.visibleModules = [.ai]
    configuration.ai[.claude] = AIProviderDisplayPreference(isVisible: true, metric: .remaining)
    let base = fixtureCombinedSnapshot()
    let fable = try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID,
        title: "Fable weekly", usedPercent: 100, resetsAt: nil)
    let augmented = CombinedUsageSnapshot(
        system: base.system,
        providers: base.providers.map { snapshot in
            guard snapshot.provider == .claude else { return snapshot }
            return ProviderSnapshot(
                provider: snapshot.provider, usage: snapshot.usage,
                quota: .init(windows: (snapshot.quota?.windows ?? []) + [fable]),
                usageStatus: snapshot.usageStatus, quotaStatus: snapshot.quotaStatus,
                updatedAt: snapshot.updatedAt)
        },
        capturedAt: base.capturedAt, systemAvailability: base.systemAvailability)
    let before = MenuBarDashboardRenderer.render(snapshot: base, configuration: configuration, availableWidth: 240)
    let after = MenuBarDashboardRenderer.render(snapshot: augmented, configuration: configuration, availableWidth: 240)
    #expect(after.title == before.title)
    #expect(after.tooltip == before.tooltip)
}
```

- [x] Add this tuple to the existing `malformedValuesReturnOnlyStableCode` argument table in `AcceptanceFixtureTests.swift`. It proves this narrowly scoped feature does not expand the separate acceptance fixture contract:

```swift
(#"{"schemaVersion":1,"timeZone":"America/New_York","startAt":"2026-09-01T12:00:00.000Z","events":[{"delaySeconds":0,"localDay":"2026-09-01","usage":{},"quota":{"claude":[{"id":"claude.fable.weekly","remainingPercent":75,"resetsAt":"2026-09-02T12:00:00.000Z"}]}}]}"#, "fixtureUnknownID", 0),
```

- [x] Run the complete focused consumer suites alongside the new Fable regressions:

```bash
make swift-test SWIFT_TEST_FILTER='Fable|fable|Widget|QuotaAlert|QuotaNotification|MenuBar|Popover|SnapshotExport|Export|AcceptanceFixture'
make acceptance-test
```

Expected: the exact additive fixtures above do not change consumer results. The dedicated acceptance target enables `NEEDLBAR_ACCEPTANCE_DRIVER`; ordinary Swift tests alone do not run those conditional tests. These are compatibility regressions expected to remain GREEN, not new product behavior requiring allowlist changes.

- [x] Run normal full verification first and retain its exit status and log:

```bash
make test
make package
make smoke
git diff --check
```

Expected: exit 0 for each. The latest pre-feature plain `make test` had analytics process-fixture failures (first ENOENT, then guard poisoning); do not attribute them to Fable without comparison. If they recur, record a blocked normal gate and run this diagnostic separately:

```bash
RUST_TEST_THREADS=1 make test
```

Serial success is evidence only for the serial configuration. Do not claim ordinary `make test`, CI, or native macOS 14 passed on that basis. Do not alter unrelated tests or process deadlines. Review all implementation diffs for auth/credential/raw-body changes; none are expected.

- [x] Load the computer-use skill before native interaction. Identify the exact development bundle/process, package and launch that build, and avoid operating on a second installed/release copy. Use the user's existing Claude login. If auth is unavailable, report the native numeric comparison as pending; do not request secret contents or synthesize a live percentage.
- [x] Compare actual Fable remaining and reset with first-party evidence only after Task 0 passes. Confirm the existing Claude headline/menu title/full tooltip do not change merely because Fable is lower; the child is separately labeled. Verify visible Claude Remaining, hidden Claude, and Usage/Cost configurations; restore settings changed solely for testing. Check missing Fable, unknown reset, 0% remaining and stale behavior with synthetic test data only, never spoof live state.
- [ ] Inspect the native 360-point dashboard and short-screen scrolling, Settings reachability, and VoiceOver/accessibility tree. Confirm the Fable child is readable separately from the existing Claude header and does not add an auth button. Capture a sanitized native screenshot without account identifiers, IPs, or credentials; do not replace README screenshots with generated mockups. Native macOS 14 acceptance stays deferred.

  Partially verified on 2026-09-03: native 360×680 rendering, separate AX content,
  Settings reachability, and sanitized screenshot passed. Native short-display
  scrolling is not verified: the AX scroll action timed out; the 400-point layout
  passed automated AppKit fitting tests. Spoken VoiceOver and macOS 14 remain unclaimed.
- [x] Update README's existing feature description with the factual sentence: “Claude quota details can show Fable weekly remaining and reset when the provider supplies a supported Fable limit; Fable shares the plan's weekly pool and is not additional independent capacity.” Record implementation commits, exact test commands/results, native comparison evidence, and next continuation in STATUS. Leave any unfinished gate explicitly open.
- [x] Request scoped spec/quality review through the prescribed subagents, fix verified in-scope findings with regression tests, and rerun affected tests. Root reviews the result and only then records the feature complete if every required gate is satisfied. Commit scoped test/docs changes; stop before push/merge/release unless requested.

## Execution acceptance checklist

- [x] Task 0 has first-party semantics evidence, not only identity/types or synthetic success.
- [x] Parser matching is exact and surface must be explicitly null; is_active/model ID do not gate availability.
- [x] Optional malformed/duplicate data omits only Fable; required legacy validation remains intact.
- [x] Domain stores usedPercent, not remaining; reset is localized and unknown remains explicit.
- [x] Only Claude remaining shows the child; menu/headline/tooltip retain old behavior.
- [x] Export v1 is byte-identical without Fable, other unknown IDs still rejected; widget/notification/acceptance contracts unchanged.
- [x] Store/bridge preserve generic windows and correct LKG/omission semantics without another state machine.
- [x] No credential/raw response/Settings/refresh/schema/version changes; no unverified live number is claimed.
- [x] Normal, serial, CI, and native macOS 14 evidence are reported as separate gates.

## Planning review — 2026-09-03

The main agent reviewed coverage against the approved spec, searched for
placeholders, and checked cross-task types/signatures and existing helper
contracts. Task 0 covers provenance; Task 1 protects projections; Task 2 covers
optional decoding and bridge forwarding; Task 3 covers presentation and state;
Task 4 covers closed consumers and native/full verification. The acceptance
fixture uses `remainingPercent`, while source/domain tests use `usedPercent`.
The header's explicit accessibility label remains on the header only, so it
cannot suppress the separate Fable child. Snippets are planned changes, not
executed or compiled implementation evidence. At plan creation every execution
checkbox was open; the later Task 0 passing evidence is recorded separately above.

## Execution checkpoint — 2026-09-03

Tasks 1–3 and Task 4 automated/downstream checks plus current-host native value
parity passed; independent spec and quality reviews approved the feature.
Implementation commits: `a383d33`, `fd5da82`, `0714bb8`, `2d74ff4`.
Native evidence and exact command/log results are recorded in `docs/STATUS.md`.
The open native short-display item above is intentionally not marked complete.
Fresh worker sessions returned transport 404 errors, so existing workers were
reused for checkpoint recovery and Task 4; independent reviews were preserved.
Pipe alternatives in Swift filters were escaped for the existing Makefile shell
recipe. No release, push, merge, or native macOS 14 acceptance was performed.
