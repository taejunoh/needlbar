use async_trait::async_trait;

use crate::{ProviderQuotaSnapshot, QuotaError};

pub mod claude_cli;
pub mod claude_usage_probe;
pub mod claude_usage_provider;
pub mod claude_usage_report;
pub mod codex;
pub mod cursor;

#[async_trait]
pub trait QuotaProvider: Send + Sync {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError>;
}
