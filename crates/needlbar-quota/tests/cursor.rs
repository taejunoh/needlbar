use needlbar_quota::{CursorQuotaProvider, ProviderId, QuotaErrorCode, QuotaProvider};

#[tokio::test]
async fn cursor_quota_is_unavailable_without_authentication_or_io() {
    let error = CursorQuotaProvider::new()
        .fetch()
        .await
        .expect_err("Cursor personal quota has no supported integration");
    assert_eq!(error.provider, Some(ProviderId::Cursor));
    assert_eq!(error.code, QuotaErrorCode::ProviderUnavailable);
    assert!(error.action.is_none());
}

#[tokio::test]
async fn cursor_session_verification_is_unavailable_without_authentication_or_io() {
    let error = CursorQuotaProvider::new()
        .verify_session_token("ignored-session-token")
        .await
        .expect_err("Cursor personal quota has no supported integration");
    assert_eq!(error.provider, Some(ProviderId::Cursor));
    assert_eq!(error.code, QuotaErrorCode::ProviderUnavailable);
    assert!(error.action.is_none());
}
