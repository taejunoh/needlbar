use std::time::Duration;

use reqwest::{header, Client, Response, Url};

use crate::{QuotaError, QuotaErrorCode};

const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
const ANTHROPIC_USAGE_HOST: &str = "api.anthropic.com";

/// A small HTTP boundary which validates an endpoint before an authorization
/// header can be constructed. It intentionally neither retains nor logs a
/// bearer token or response body.
#[derive(Clone)]
pub struct RedactingHttpClient {
    client: Client,
}

impl RedactingHttpClient {
    pub fn new() -> Self {
        let client = Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .build()
            .expect("static reqwest client configuration is valid");
        Self { client }
    }

    pub fn get_bearer(
        &self,
        endpoint: &str,
        bearer_token: &str,
        headers: &[(&str, &str)],
    ) -> Result<reqwest::RequestBuilder, QuotaError> {
        let url = Url::parse(endpoint).map_err(|_| unsafe_endpoint_error())?;
        if url.scheme() != "https" || url.host_str() != Some(ANTHROPIC_USAGE_HOST) {
            return Err(unsafe_endpoint_error());
        }

        let mut request = self.client.get(url).bearer_auth(bearer_token);
        for (name, value) in headers {
            request = request.header(*name, *value);
        }
        Ok(request)
    }

    pub async fn send(&self, request: reqwest::RequestBuilder) -> Result<Response, QuotaError> {
        let response = request.send().await.map_err(|_| {
            QuotaError::new(
                None,
                QuotaErrorCode::NetworkUnavailable,
                "The quota service could not be reached.",
            )
        })?;

        if response.status().is_success() {
            return Ok(response);
        }

        Err(status_error(response.status(), response.headers()))
    }
}

impl Default for RedactingHttpClient {
    fn default() -> Self {
        Self::new()
    }
}

fn unsafe_endpoint_error() -> QuotaError {
    QuotaError::new(
        None,
        QuotaErrorCode::NetworkUnavailable,
        "The quota service could not be reached.",
    )
}

fn status_error(status: reqwest::StatusCode, headers: &header::HeaderMap) -> QuotaError {
    let retry_after = headers
        .get(header::RETRY_AFTER)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u64>().ok())
        .map(Duration::from_secs);

    match status.as_u16() {
        401 | 403 => QuotaError::new(
            None,
            QuotaErrorCode::AuthenticationExpired,
            "Claude authentication has expired.",
        ),
        429 => QuotaError::new(
            None,
            QuotaErrorCode::RateLimited,
            "The quota service asked us to retry later.",
        )
        .with_retry_after(retry_after),
        500..=599 => QuotaError::new(
            None,
            QuotaErrorCode::ServiceUnavailable,
            "The quota service is temporarily unavailable.",
        )
        .with_retry_after(retry_after),
        _ => QuotaError::new(
            None,
            QuotaErrorCode::NetworkUnavailable,
            "The quota service returned an unexpected response.",
        ),
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use reqwest::{header, StatusCode};

    use super::status_error;
    use crate::QuotaErrorCode;

    #[test]
    fn maps_retry_after_to_a_safe_rate_limit_error() {
        let mut headers = header::HeaderMap::new();
        headers.insert(header::RETRY_AFTER, header::HeaderValue::from_static("30"));

        let error = status_error(StatusCode::TOO_MANY_REQUESTS, &headers);

        assert_eq!(error.code, QuotaErrorCode::RateLimited);
        assert_eq!(error.retry_after, Some(Duration::from_secs(30)));
        assert!(!format!("{error:?}").contains("Retry-After: 30"));
    }
}
