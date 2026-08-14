use chrono::{SecondsFormat, Utc};
use serde::Serialize;

pub const SCHEMA_VERSION: &str = "needlbar.v1";

#[derive(Debug, Clone, Serialize)]
pub struct BridgeError {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
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
