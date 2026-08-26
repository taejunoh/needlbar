use async_trait::async_trait;

use crate::{ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaProvider};

pub struct CursorQuotaProvider;

impl CursorQuotaProvider {
    pub fn new() -> Self {
        Self
    }

    /// Compatibility seam for the pre-amendment bridge session-import path.
    /// Cursor quota no longer verifies credentials or performs any I/O.
    pub async fn verify_session_token(&self, _session_token: &str) -> Result<(), QuotaError> {
        Err(cursor_unavailable_error())
    }
}

impl Default for CursorQuotaProvider {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl QuotaProvider for CursorQuotaProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        Err(cursor_unavailable_error())
    }
}

fn cursor_unavailable_error() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Cursor),
        QuotaErrorCode::ProviderUnavailable,
        "Cursor personal quota is available in Cursor Spending.",
    )
}
