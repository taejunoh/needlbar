use async_trait::async_trait;

use crate::{ProviderQuotaSnapshot, QuotaError};

pub mod claude;
pub mod claude_credentials;
pub mod codex;
pub mod cursor;

#[async_trait]
pub trait QuotaProvider: Send + Sync {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError>;
}
