use std::{collections::BTreeMap, path::Path};

use chrono::{Days, Local, NaiveDate};
use needlbar_source_sync::sync_cursor_cache;
use serde::Serialize;
use tokscale_core::{DailyContribution, ReportOptions};

use crate::envelope::BridgeError;

const PROVIDERS: [&str; 3] = ["claude", "codex", "cursor"];

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsagePeriod {
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_read_tokens: u64,
    pub cache_write_tokens: u64,
    pub total_tokens: u64,
    pub estimated_cost_usd: f64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageProviderSnapshot {
    pub provider: String,
    #[serde(flatten)]
    pub all_time_split: UsagePeriod,
    pub today: UsagePeriod,
    pub last_7_days: UsagePeriod,
    pub last_7_days_daily: Vec<DailyUsagePoint>,
    pub last_30_days: UsagePeriod,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DailyUsagePoint {
    pub date: String,
    pub total_tokens: u64,
}

#[derive(Debug, Serialize)]
pub struct UsagePayload {
    pub providers: Vec<UsageProviderSnapshot>,
}

pub struct UsageCollection {
    pub providers: Vec<UsageProviderSnapshot>,
    pub warnings: Vec<BridgeError>,
}

#[derive(Default)]
struct ProviderPeriods {
    seen: bool,
    all_time: UsagePeriod,
    today: UsagePeriod,
    last_7_days: UsagePeriod,
    last_7_days_daily: BTreeMap<NaiveDate, u64>,
    last_30_days: UsagePeriod,
}

pub fn collect_usage() -> Result<Vec<UsageProviderSnapshot>, BridgeError> {
    collect_usage_for_home(None, true)
}

pub fn collect_usage_with_cursor_sync() -> Result<UsageCollection, BridgeError> {
    collect_usage_with_cursor_sync_force(false)
}

pub fn collect_usage_with_cursor_sync_force(force: bool) -> Result<UsageCollection, BridgeError> {
    let warnings = (!cursor_sync_succeeds(force, |force| {
        sync_cursor_cache(force).is_ok_and(|outcome| outcome.error.is_none())
    }))
    .then(cursor_sync_warning)
    .into_iter()
    .collect();
    let providers = collect_usage()?;
    Ok(UsageCollection {
        providers,
        warnings,
    })
}

fn cursor_sync_succeeds(force: bool, sync: impl FnOnce(bool) -> bool) -> bool {
    sync(force)
}

pub fn collect_usage_from_home(home: &Path) -> Result<Vec<UsageProviderSnapshot>, BridgeError> {
    collect_usage_for_home(Some(home), false)
}

fn collect_usage_for_home(
    home: Option<&Path>,
    use_env_roots: bool,
) -> Result<Vec<UsageProviderSnapshot>, BridgeError> {
    let options = ReportOptions {
        home_dir: home.map(|path| path.to_string_lossy().into_owned()),
        use_env_roots,
        clients: Some(PROVIDERS.iter().map(ToString::to_string).collect()),
        ..Default::default()
    };
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| bridge_error(None, "usageRuntimeUnavailable", error.to_string()))?;
    let report = runtime
        .block_on(tokscale_core::generate_local_graph_report(options))
        .map_err(|error| bridge_error(None, "usageReportUnavailable", error))?;

    aggregate_report(&report.contributions, Local::now().date_naive())
}

fn aggregate_report(
    contributions: &[DailyContribution],
    today: NaiveDate,
) -> Result<Vec<UsageProviderSnapshot>, BridgeError> {
    let last_7_dates = seven_day_dates(today)?;
    let last_7_days_start = *last_7_dates
        .first()
        .expect("seven-day date helper always returns seven dates");
    let last_30_days_start = today
        .checked_sub_days(Days::new(29))
        .ok_or_else(|| bridge_error(None, "invalidUsageDate", "cannot calculate 30-day window"))?;
    let mut periods: BTreeMap<&str, ProviderPeriods> = PROVIDERS
        .into_iter()
        .map(|provider| (provider, ProviderPeriods::default()))
        .collect();

    for contribution in contributions {
        for client in contribution
            .clients
            .iter()
            .filter(|client| PROVIDERS.contains(&client.client.as_str()))
        {
            let provider = client.client.as_str();
            let date =
                NaiveDate::parse_from_str(&contribution.date, "%Y-%m-%d").map_err(|error| {
                    bridge_error(
                        Some(provider),
                        "invalidUsageDate",
                        format!("invalid graph contribution date: {error}"),
                    )
                })?;
            let usage = normalize_client_contribution(client, provider)?;
            let provider_periods = periods
                .get_mut(provider)
                .expect("known provider initialized from PROVIDERS");
            provider_periods.seen = true;
            provider_periods.all_time.add(&usage, provider)?;
            if date == today {
                provider_periods.today.add(&usage, provider)?;
            }
            if (last_7_days_start..=today).contains(&date) {
                provider_periods.last_7_days.add(&usage, provider)?;
                let daily_total = provider_periods.last_7_days_daily.entry(date).or_default();
                *daily_total = checked_add(*daily_total, usage.total_tokens, provider)?;
            }
            if (last_30_days_start..=today).contains(&date) {
                provider_periods.last_30_days.add(&usage, provider)?;
            }
        }
    }

    Ok(PROVIDERS
        .iter()
        .filter_map(|provider| {
            let periods = periods
                .remove(provider)
                .expect("known provider initialized from PROVIDERS");
            periods.seen.then(|| UsageProviderSnapshot {
                provider: (*provider).to_owned(),
                all_time_split: periods.all_time,
                today: periods.today,
                last_7_days: periods.last_7_days,
                last_7_days_daily: last_7_dates
                    .iter()
                    .map(|date| DailyUsagePoint {
                        date: date.to_string(),
                        total_tokens: periods
                            .last_7_days_daily
                            .get(date)
                            .copied()
                            .unwrap_or_default(),
                    })
                    .collect(),
                last_30_days: periods.last_30_days,
            })
        })
        .collect())
}

fn seven_day_dates(today: NaiveDate) -> Result<Vec<NaiveDate>, BridgeError> {
    let start = today
        .checked_sub_days(Days::new(6))
        .ok_or_else(|| bridge_error(None, "invalidUsageDate", "cannot calculate 7-day window"))?;
    (0..7)
        .map(|offset| {
            start.checked_add_days(Days::new(offset)).ok_or_else(|| {
                bridge_error(None, "invalidUsageDate", "cannot calculate 7-day window")
            })
        })
        .collect()
}

fn normalize_client_contribution(
    contribution: &tokscale_core::ClientContribution,
    provider: &str,
) -> Result<UsagePeriod, BridgeError> {
    let input_tokens = normalize_counter(contribution.tokens.input, provider)?;
    let output_tokens = normalize_counter(contribution.tokens.output, provider)?;
    let cache_read_tokens = normalize_counter(contribution.tokens.cache_read, provider)?;
    let cache_write_tokens = normalize_counter(contribution.tokens.cache_write, provider)?;
    let reasoning_tokens = normalize_counter(contribution.tokens.reasoning, provider)?;
    let total_tokens = [
        input_tokens,
        output_tokens,
        cache_read_tokens,
        cache_write_tokens,
        reasoning_tokens,
    ]
    .into_iter()
    .try_fold(0_u64, |total, value| {
        total.checked_add(value).ok_or_else(|| {
            bridge_error(
                Some(provider),
                "invalidUsageData",
                "token total exceeds supported range",
            )
        })
    })?;
    if !contribution.cost.is_finite() || contribution.cost < 0.0 {
        return Err(bridge_error(
            Some(provider),
            "invalidUsageData",
            "usage cost is negative or non-finite",
        ));
    }

    Ok(UsagePeriod {
        input_tokens,
        output_tokens,
        cache_read_tokens,
        cache_write_tokens,
        total_tokens,
        estimated_cost_usd: contribution.cost,
    })
}

impl UsagePeriod {
    fn add(&mut self, incoming: &Self, provider: &str) -> Result<(), BridgeError> {
        self.input_tokens = checked_add(self.input_tokens, incoming.input_tokens, provider)?;
        self.output_tokens = checked_add(self.output_tokens, incoming.output_tokens, provider)?;
        self.cache_read_tokens =
            checked_add(self.cache_read_tokens, incoming.cache_read_tokens, provider)?;
        self.cache_write_tokens = checked_add(
            self.cache_write_tokens,
            incoming.cache_write_tokens,
            provider,
        )?;
        self.total_tokens = checked_add(self.total_tokens, incoming.total_tokens, provider)?;
        self.estimated_cost_usd += incoming.estimated_cost_usd;
        if !self.estimated_cost_usd.is_finite() {
            return Err(bridge_error(
                Some(provider),
                "invalidUsageData",
                "usage cost exceeds supported range",
            ));
        }
        Ok(())
    }
}

fn normalize_counter(value: i64, provider: &str) -> Result<u64, BridgeError> {
    u64::try_from(value).map_err(|_| {
        bridge_error(
            Some(provider),
            "invalidUsageData",
            "usage counter is negative",
        )
    })
}

fn checked_add(current: u64, incoming: u64, provider: &str) -> Result<u64, BridgeError> {
    current.checked_add(incoming).ok_or_else(|| {
        bridge_error(
            Some(provider),
            "invalidUsageData",
            "usage counter exceeds supported range",
        )
    })
}

fn bridge_error(
    provider: Option<&str>,
    code: impl Into<String>,
    message: impl Into<String>,
) -> BridgeError {
    BridgeError {
        provider: provider.map(ToOwned::to_owned),
        code: code.into(),
        message: message.into(),
        action: None,
    }
}

#[cfg(test)]
mod daily_series_tests {
    use chrono::NaiveDate;

    use super::*;

    #[test]
    fn seven_day_dates_are_chronological_and_include_today() {
        let today = NaiveDate::from_ymd_opt(2026, 8, 14).unwrap();

        let dates = seven_day_dates(today).unwrap();

        assert_eq!(dates.len(), 7);
        assert_eq!(dates.first().unwrap().to_string(), "2026-08-08");
        assert_eq!(dates.last().unwrap().to_string(), "2026-08-14");
    }

    #[test]
    fn daily_series_uses_checked_token_addition() {
        let error = checked_add(u64::MAX, 1, "claude").unwrap_err();

        assert_eq!(error.code, "invalidUsageData");
    }
}

fn cursor_sync_warning() -> BridgeError {
    bridge_error(
        Some("cursor"),
        "cursorSyncFailed",
        "Cursor usage synchronization failed; cached usage may still be available",
    )
}

#[cfg(test)]
mod tests {
    use super::cursor_sync_succeeds;

    #[test]
    fn forced_cursor_sync_passes_true_to_the_source_sync_seam() {
        let mut observed = None;
        let succeeded = cursor_sync_succeeds(true, |force| {
            observed = Some(force);
            true
        });
        assert!(succeeded);
        assert_eq!(observed, Some(true));
    }
}
