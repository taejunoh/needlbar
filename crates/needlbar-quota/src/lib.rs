//! Provider quota retrieval. This crate deliberately keeps credentials and
//! provider responses on the Rust side of the bridge.

mod domain;
mod http;
pub mod providers;

pub use domain::{
    normalize_percent, ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaWindow,
};
pub use http::RedactingHttpClient;
pub use providers::claude::ClaudeQuotaProvider;
pub use providers::codex::{CodexQuotaProvider, CodexQuotaSource};
pub use providers::cursor::{CursorQuotaProvider, CursorQuotaSource};
pub use providers::QuotaProvider;
