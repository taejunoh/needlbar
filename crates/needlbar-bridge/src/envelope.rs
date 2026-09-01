use chrono::{SecondsFormat, Utc};
use serde::Serialize;

pub const SCHEMA_VERSION: &str = "needlbar.v1";
pub const ANALYTICS_SCHEMA_VERSION: &str = "needlbar.analytics.v1";

#[derive(Debug, Clone, Serialize)]
pub struct BridgeError {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    pub code: String,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct Envelope<T: Serialize> {
    #[serde(rename = "schemaVersion")]
    pub schema_version: &'static str,
    pub ok: bool,
    #[serde(rename = "generatedAt")]
    pub generated_at: String,
    pub data: Option<T>,
    pub errors: Vec<BridgeError>,
}

/// The analytics ABI is intentionally versioned independently of the usage
/// and quota envelope.  Keep this type separate so changes to the existing
/// bridge contract cannot accidentally alter analytics decoding (or vice
/// versa).
#[derive(Debug, Serialize)]
pub struct AnalyticsEnvelope<T: Serialize> {
    #[serde(rename = "schemaVersion")]
    pub schema_version: &'static str,
    pub ok: bool,
    #[serde(rename = "generatedAt")]
    pub generated_at: String,
    pub data: Option<T>,
    pub errors: Vec<AnalyticsBridgeError>,
}

#[derive(Debug, Clone, Eq, PartialEq, Ord, PartialOrd, Serialize)]
pub struct AnalyticsBridgeError {
    pub scope: String,
    pub code: String,
}

impl<T: Serialize> AnalyticsEnvelope<T> {
    pub fn success(data: T, generated_at: String) -> Self {
        Self {
            schema_version: ANALYTICS_SCHEMA_VERSION,
            ok: true,
            generated_at,
            data: Some(data),
            errors: Vec::new(),
        }
    }
}

impl<T: Serialize> Envelope<T> {
    pub fn success(data: T) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            ok: true,
            generated_at: timestamp(),
            data: Some(data),
            errors: vec![],
        }
    }

    pub fn failure(error: BridgeError) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            ok: false,
            generated_at: timestamp(),
            data: None,
            errors: vec![error],
        }
    }
}

fn timestamp() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true)
}

pub fn analytics_timestamp(now: chrono::DateTime<Utc>) -> String {
    now.to_rfc3339_opts(SecondsFormat::Millis, true)
}
