//! Pure parser for `claude -p /usage --output-format stream-json`. It knows
//! nothing about processes. Everything except `usage_report`, and the closed
//! `error` value used when no report arrived, is discarded here: serde skips
//! other fields without building them, and no text is kept or logged.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::QuotaWindow;

const SESSION_ID: &str = "claude.session";
const WEEKLY_ID: &str = "claude.weekly";
const FABLE_ID: &str = "claude.fable.weekly";

/// A closed label for diagnostics, so a server-sent `kind` never reaches a log.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ClaudeUsageRowKind {
    Session,
    WeeklyAll,
    WeeklyScoped,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeUsageRowSummary {
    pub row_kinds: Vec<ClaudeUsageRowKind>,
    pub unknown_row_count: u32,
    pub skipped_row_count: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ClaudeUsageReportOutcome {
    Windows {
        windows: Vec<QuotaWindow>,
        rows: ClaudeUsageRowSummary,
    },
    NoUsageAvailable {
        rows: ClaudeUsageRowSummary,
    },
    RateLimited,
    FormatChanged {
        rows: ClaudeUsageRowSummary,
    },
}

#[derive(Deserialize)]
struct StreamLine {
    #[serde(default, rename = "type")]
    line_type: Option<Value>,
    #[serde(default)]
    usage_report: Option<Value>,
    #[serde(default)]
    error: Option<Value>,
}

pub fn parse_usage_report_stream(bytes: &[u8]) -> ClaudeUsageReportOutcome {
    let mut report = None;
    let mut rate_limited = false;
    for line in bytes.split(|byte| *byte == b'\n') {
        let Ok(parsed) = serde_json::from_slice::<StreamLine>(line) else {
            continue;
        };
        if parsed.line_type.as_ref().and_then(Value::as_str) != Some("assistant") {
            continue;
        }
        rate_limited |= parsed.error.as_ref().and_then(Value::as_str) == Some("rate_limit");
        if let Some(candidate) = parsed.usage_report.filter(|value| !value.is_null()) {
            report = Some(candidate);
        }
    }
    match report {
        Some(report) => classify_report(&report),
        None if rate_limited => ClaudeUsageReportOutcome::RateLimited,
        None => ClaudeUsageReportOutcome::FormatChanged {
            rows: ClaudeUsageRowSummary::default(),
        },
    }
}

fn format_changed() -> ClaudeUsageReportOutcome {
    ClaudeUsageReportOutcome::FormatChanged {
        rows: ClaudeUsageRowSummary::default(),
    }
}

fn no_usage() -> ClaudeUsageReportOutcome {
    ClaudeUsageReportOutcome::NoUsageAvailable {
        rows: ClaudeUsageRowSummary::default(),
    }
}

fn classify_report(report: &Value) -> ClaudeUsageReportOutcome {
    let Some(rate_limits) = report
        .as_object()
        .and_then(|object| object.get("rate_limits"))
    else {
        return format_changed();
    };
    if rate_limits.is_null() {
        return no_usage();
    }
    let Some(limits) = rate_limits
        .as_object()
        .and_then(|object| object.get("limits"))
    else {
        return format_changed();
    };
    if limits.is_null() {
        return no_usage();
    }
    let Some(rows) = limits.as_array() else {
        return format_changed();
    };
    if rows.is_empty() {
        return no_usage();
    }
    classify_rows(rows)
}

#[derive(Default)]
struct Field {
    readings: Vec<(f64, Option<DateTime<Utc>>)>,
}

impl Field {
    fn window(
        self,
        id: &str,
        title: &str,
        summary: &mut ClaudeUsageRowSummary,
    ) -> Option<QuotaWindow> {
        match self.readings.as_slice() {
            [] => None,
            [(percent, resets_at)] => QuotaWindow::new(id, title, *percent, *resets_at).ok(),
            // Two rows for one field cannot be told apart, so show neither.
            several => {
                summary.skipped_row_count += several.len() as u32;
                None
            }
        }
    }
}

fn classify_rows(rows: &[Value]) -> ClaudeUsageReportOutcome {
    let mut summary = ClaudeUsageRowSummary::default();
    let (mut session, mut weekly, mut fable) =
        (Field::default(), Field::default(), Field::default());
    for row in rows {
        let Some(kind) = row.get("kind").and_then(Value::as_str) else {
            summary.skipped_row_count += 1;
            continue;
        };
        let (row_kind, field) = match kind {
            "session" => (ClaudeUsageRowKind::Session, Some(&mut session)),
            "weekly_all" => (ClaudeUsageRowKind::WeeklyAll, Some(&mut weekly)),
            "weekly_scoped" => (
                ClaudeUsageRowKind::WeeklyScoped,
                is_fable(row).then_some(&mut fable),
            ),
            _ => {
                summary.unknown_row_count += 1;
                continue;
            }
        };
        if !summary.row_kinds.contains(&row_kind) {
            summary.row_kinds.push(row_kind);
        }
        let Some(field) = field else { continue };
        match parse_reading(row) {
            Some(reading) => field.readings.push(reading),
            None => summary.skipped_row_count += 1,
        }
    }
    let windows: Vec<QuotaWindow> = [
        session.window(SESSION_ID, "Session", &mut summary),
        weekly.window(WEEKLY_ID, "Weekly", &mut summary),
        fable.window(FABLE_ID, "Fable weekly", &mut summary),
    ]
    .into_iter()
    .flatten()
    .collect();
    if windows.is_empty() {
        return ClaudeUsageReportOutcome::FormatChanged { rows: summary };
    }
    ClaudeUsageReportOutcome::Windows {
        windows,
        rows: summary,
    }
}

/// No documented identifier exists for a model scope, so this label is a known
/// weak point (spec §7).
fn is_fable(row: &Value) -> bool {
    row.pointer("/scope/model/display_name")
        .and_then(Value::as_str)
        .is_some_and(|name| name.eq_ignore_ascii_case("Fable"))
}

fn parse_reading(row: &Value) -> Option<(f64, Option<DateTime<Utc>>)> {
    let percent = row
        .get("percent")?
        .as_f64()
        .filter(|value| value.is_finite())?;
    let resets_at = match row.get("resets_at") {
        None | Some(Value::Null) => None,
        Some(Value::String(text)) => {
            Some(DateTime::parse_from_rfc3339(text).ok()?.with_timezone(&Utc))
        }
        Some(_) => return None,
    };
    Some((percent.clamp(0.0, 100.0), resets_at))
}
