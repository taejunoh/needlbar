use async_trait::async_trait;

use crate::{ProviderQuotaSnapshot, QuotaError};

pub mod claude;
pub mod codex;

#[async_trait]
pub trait QuotaProvider: Send + Sync {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError>;
}
