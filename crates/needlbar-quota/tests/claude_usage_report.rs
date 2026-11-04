use chrono::{TimeZone, Utc};
use needlbar_quota::{
    parse_usage_report_stream, ClaudeUsageReportOutcome, ClaudeUsageRowKind, ClaudeUsageRowSummary,
    QuotaWindow,
};

const ALL_ROWS: &str = include_str!("../../../Fixtures/quota/claude/usage-report-all-rows.jsonl");
const WEEKLY_ONLY: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-weekly-only.jsonl");

fn stream(rate_limits: &str) -> Vec<u8> {
    format!(
        "{{\"type\":\"assistant\",\"message\":{{\"content\":[]}},\"usage_report\":{{\"session\":{{\"total_cost_usd\":1}},\"rate_limits\":{rate_limits}}}}}\n"
    )
    .into_bytes()
}

fn rows(rows: &str) -> Vec<u8> {
    stream(&format!("{{\"limits\":[{rows}]}}"))
}

const WEEKLY_ROW: &str =
    r#"{"kind":"weekly_all","group":"weekly","percent":74,"resets_at":"2030-02-09T01:00:00Z"}"#;

fn windows(outcome: ClaudeUsageReportOutcome) -> (Vec<QuotaWindow>, ClaudeUsageRowSummary) {
    match outcome {
        ClaudeUsageReportOutcome::Windows { windows, rows } => (windows, rows),
        other => panic!("expected windows, got {other:?}"),
    }
}

#[test]
fn all_rows_map_to_the_existing_window_ids_in_order() {
    let (windows, rows) = windows(parse_usage_report_stream(ALL_ROWS.as_bytes()));
    let ids: Vec<_> = windows.iter().map(QuotaWindow::id).collect();
    assert_eq!(
        ids,
        ["claude.session", "claude.weekly", "claude.fable.weekly"]
    );
    let titles: Vec<_> = windows.iter().map(QuotaWindow::title).collect();
    assert_eq!(titles, ["Session", "Weekly", "Fable weekly"]);
    assert_eq!(windows[0].used_percent(), 42.5);
    assert_eq!(windows[1].used_percent(), 74.0);
    assert_eq!(windows[2].used_percent(), 25.0);
    assert_eq!(
        windows[0].resets_at(),
        Some(Utc.with_ymd_and_hms(2030, 2, 2, 5, 0, 0).unwrap())
    );
    assert_eq!(
        rows.row_kinds,
        [
            ClaudeUsageRowKind::Session,
            ClaudeUsageRowKind::WeeklyAll,
            ClaudeUsageRowKind::WeeklyScoped
        ]
    );
}

#[test]
fn a_missing_session_row_hides_only_that_field() {
    let (windows, _) = windows(parse_usage_report_stream(WEEKLY_ONLY.as_bytes()));
    let ids: Vec<_> = windows.iter().map(QuotaWindow::id).collect();
    assert_eq!(ids, ["claude.weekly", "claude.fable.weekly"]);
    assert_eq!(windows[1].used_percent(), 0.0);
    assert_eq!(windows[1].resets_at(), None);
}

#[test]
fn the_report_level_session_totals_are_not_the_session_row() {
    let (windows, _) = windows(parse_usage_report_stream(&rows(WEEKLY_ROW)));
    assert!(windows.iter().all(|window| window.id() != "claude.session"));
}

#[test]
fn only_fable_present_is_a_valid_reading() {
    let only_fable =
        r#"{"kind":"weekly_scoped","percent":3,"scope":{"model":{"display_name":"FABLE"}}}"#;
    let (windows, _) = windows(parse_usage_report_stream(&rows(only_fable)));
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].id(), "claude.fable.weekly");
}

#[test]
fn percent_is_clamped_and_non_numbers_are_skipped() {
    let input = rows(
        r#"{"kind":"session","percent":140},{"kind":"weekly_all","percent":-5},{"kind":"weekly_scoped","percent":"NaN","scope":{"model":{"display_name":"Fable"}}}"#,
    );
    let (windows, rows) = windows(parse_usage_report_stream(&input));
    assert_eq!(windows.len(), 2);
    assert_eq!(windows[0].used_percent(), 100.0);
    assert_eq!(windows[1].used_percent(), 0.0);
    assert_eq!(rows.skipped_row_count, 1);
}

#[test]
fn a_malformed_row_is_skipped_and_the_others_still_count() {
    let input = rows(&format!(
        r#"{{"percent":10}},{{"kind":"session","resets_at":"2030-02-02T05:00:00Z"}},{{"kind":"session","percent":10,"resets_at":"not-a-date"}},17,{WEEKLY_ROW}"#
    ));
    let (windows, rows) = windows(parse_usage_report_stream(&input));
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].id(), "claude.weekly");
    assert_eq!(rows.skipped_row_count, 4);
}

#[test]
fn unknown_kinds_and_other_models_are_ignored() {
    let input = rows(&format!(
        r#"{{"kind":"daily_future","percent":10}},{{"kind":"weekly_scoped","percent":9,"scope":{{"model":{{"display_name":"Other"}}}}}},{WEEKLY_ROW}"#
    ));
    let (windows, rows) = windows(parse_usage_report_stream(&input));
    assert_eq!(windows.len(), 1);
    assert_eq!(rows.unknown_row_count, 1);
    assert!(rows.row_kinds.contains(&ClaudeUsageRowKind::WeeklyScoped));
}

#[test]
fn missing_or_null_reset_shows_no_reset_time() {
    let input = rows(
        r#"{"kind":"session","percent":1},{"kind":"weekly_all","percent":2,"resets_at":null}"#,
    );
    let (windows, _) = windows(parse_usage_report_stream(&input));
    assert!(windows.iter().all(|window| window.resets_at().is_none()));
}

#[test]
fn two_rows_for_one_field_hide_only_that_field() {
    let input = rows(&format!(
        r#"{{"kind":"session","percent":1}},{{"kind":"session","percent":2}},{WEEKLY_ROW}"#
    ));
    let (windows, rows) = windows(parse_usage_report_stream(&input));
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].id(), "claude.weekly");
    assert_eq!(rows.skipped_row_count, 2);
}

#[test]
fn null_rate_limits_and_null_or_empty_limits_are_no_usage() {
    for input in [
        stream("null"),
        stream(r#"{"limits":null}"#),
        stream(r#"{"limits":[]}"#),
    ] {
        assert!(matches!(
            parse_usage_report_stream(&input),
            ClaudeUsageReportOutcome::NoUsageAvailable { .. }
        ));
    }
}

#[test]
fn no_report_and_changed_shapes_are_format_changed() {
    for input in [
        b"".to_vec(),
        b"not json\n".to_vec(),
        br#"{"type":"assistant","message":{"content":[]}}"#.to_vec(),
        br#"{"type":"assistant","usage_report":null}"#.to_vec(),
        br#"{"type":"result","usage_report":{"rate_limits":null}}"#.to_vec(),
        br#"{"type":"assistant","usage_report":{}}"#.to_vec(),
        stream("7"),
        stream(r#"{"limits":"none"}"#),
        stream(r#"{}"#),
        rows(r#"{"kind":"daily_future","percent":10}"#),
    ] {
        assert!(
            matches!(
                parse_usage_report_stream(&input),
                ClaudeUsageReportOutcome::FormatChanged { .. }
            ),
            "{}",
            String::from_utf8_lossy(&input)
        );
    }
}

#[test]
fn a_rate_limit_error_is_used_only_when_there_is_no_report() {
    let limited = br#"{"type":"assistant","error":"rate_limit","message":{"content":[]}}"#;
    assert_eq!(
        parse_usage_report_stream(limited),
        ClaudeUsageReportOutcome::RateLimited
    );
    let mut with_report = limited.to_vec();
    with_report.push(b'\n');
    with_report.extend_from_slice(&rows(WEEKLY_ROW));
    assert!(matches!(
        parse_usage_report_stream(&with_report),
        ClaudeUsageReportOutcome::Windows { .. }
    ));
}

#[test]
fn nothing_but_closed_values_survives_parsing() {
    let outcome = parse_usage_report_stream(ALL_ROWS.as_bytes());
    let debug = format!("{outcome:?}");
    for canary in [
        "SESSION-CANARY",
        "PATH-CANARY",
        "TEXT-CANARY",
        "RESULT-CANARY",
        "alice@example.com",
    ] {
        assert!(!debug.contains(canary), "{canary}");
    }
}
