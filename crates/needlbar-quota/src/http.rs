use std::time::Duration;

use reqwest::{header, Client, Response, Url};

use crate::{QuotaError, QuotaErrorCode};

const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
const ANTHROPIC_USAGE_HOST: &str = "api.anthropic.com";
const CODEX_USAGE_HOST: &str = "chatgpt.com";
const CURSOR_USAGE_HOST: &str = "cursor.com";
/// Quota retry waits longer than one hour are ignored so provider input cannot
/// suppress Needlbar's normal refresh schedule for an unbounded interval.
const MAX_RETRY_AFTER: Duration = Duration::from_secs(60 * 60);
/// Claude's small quota document does not need unbounded buffering. This also
/// caps a compromised or changed endpoint before JSON parsing.
const MAX_RESPONSE_BODY_BYTES: usize = 64 * 1024;

/// A small HTTP boundary which validates an endpoint before an authorization
/// header can be constructed. It intentionally neither retains nor logs a
/// bearer token or response body.
#[derive(Clone)]
pub struct RedactingHttpClient {
    client: Client,
    allowed_host: String,
    require_https: bool,
}

impl RedactingHttpClient {
    pub fn new() -> Self {
        Self::for_host(ANTHROPIC_USAGE_HOST)
    }

    /// Codex quota is served from a different fixed provider host. This keeps
    /// both the host allowlist and redirect policy inside the shared HTTP
    /// boundary rather than allowing individual adapters to construct clients.
    pub(crate) fn for_codex_usage() -> Self {
        Self::for_host(CODEX_USAGE_HOST)
    }

    pub(crate) fn for_cursor_usage() -> Self {
        Self::for_host(CURSOR_USAGE_HOST)
    }

    fn for_host(allowed_host: &str) -> Self {
        let client = Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("static reqwest client configuration is valid");
        Self {
            client,
            allowed_host: allowed_host.to_owned(),
            require_https: true,
        }
    }

    pub fn get_bearer(
        &self,
        endpoint: &str,
        bearer_token: &str,
        headers: &[(&str, &str)],
    ) -> Result<reqwest::RequestBuilder, QuotaError> {
        let url = Url::parse(endpoint).map_err(|_| unsafe_endpoint_error())?;
        if (self.require_https && url.scheme() != "https")
            || url.host_str() != Some(self.allowed_host.as_str())
        {
            return Err(unsafe_endpoint_error());
        }

        let mut request = self.client.get(url).bearer_auth(bearer_token);
        for (name, value) in headers {
            request = request.header(*name, *value);
        }
        Ok(request)
    }

    pub fn get_cookie(
        &self,
        endpoint: &str,
        cookie_name: &str,
        cookie_value: &str,
        headers: &[(&str, &str)],
    ) -> Result<reqwest::RequestBuilder, QuotaError> {
        let url = Url::parse(endpoint).map_err(|_| unsafe_endpoint_error())?;
        if (self.require_https && url.scheme() != "https")
            || url.host_str() != Some(self.allowed_host.as_str())
        {
            return Err(unsafe_endpoint_error());
        }
        let cookie = header::HeaderValue::from_str(&format!("{cookie_name}={cookie_value}"))
            .map_err(|_| unsafe_endpoint_error())?;
        let mut request = self.client.get(url).header(header::COOKIE, cookie);
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

    pub(crate) async fn read_limited_body(
        &self,
        mut response: Response,
    ) -> Result<Vec<u8>, QuotaError> {
        if response
            .content_length()
            .is_some_and(|length| length > MAX_RESPONSE_BODY_BYTES as u64)
        {
            return Err(response_too_large_error());
        }

        let mut body = Vec::with_capacity(
            response
                .content_length()
                .unwrap_or_default()
                .min(MAX_RESPONSE_BODY_BYTES as u64) as usize,
        );
        while let Some(chunk) = response.chunk().await.map_err(|_| {
            QuotaError::new(
                None,
                QuotaErrorCode::NetworkUnavailable,
                "The quota service could not be read.",
            )
        })? {
            if body.len().saturating_add(chunk.len()) > MAX_RESPONSE_BODY_BYTES {
                return Err(response_too_large_error());
            }
            body.extend_from_slice(&chunk);
        }
        Ok(body)
    }

    #[cfg(test)]
    fn for_test(allowed_host: String) -> Self {
        let client = Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("static reqwest client configuration is valid");
        Self {
            client,
            allowed_host,
            require_https: false,
        }
    }
}

fn response_too_large_error() -> QuotaError {
    QuotaError::new(
        None,
        QuotaErrorCode::SchemaChanged,
        "The quota response exceeded the expected size.",
    )
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
        .map(Duration::from_secs)
        .filter(|duration| *duration <= MAX_RETRY_AFTER);

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
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
        time::Duration,
    };

    use reqwest::{header, StatusCode};

    use super::{status_error, RedactingHttpClient, MAX_RESPONSE_BODY_BYTES};
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

    #[test]
    fn omits_excessive_retry_after_values() {
        let mut headers = header::HeaderMap::new();
        headers.insert(
            header::RETRY_AFTER,
            header::HeaderValue::from_static("86401"),
        );

        let error = status_error(StatusCode::TOO_MANY_REQUESTS, &headers);

        assert_eq!(error.code, QuotaErrorCode::RateLimited);
        assert_eq!(error.retry_after, None);
    }

    #[tokio::test]
    async fn does_not_follow_redirects() {
        let (endpoint, server) = local_server(
            b"HTTP/1.1 302 Found\r\nLocation: /redirected\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                .to_vec(),
        );
        let client = test_client_for(&endpoint);
        let request = client.get_bearer(&endpoint, "test-token", &[]).unwrap();

        let response = client
            .client
            .execute(request.build().unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::FOUND);
        server.join().unwrap();
    }

    #[tokio::test]
    async fn rejects_response_bodies_larger_than_the_named_limit() {
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            MAX_RESPONSE_BODY_BYTES + 1
        )
        .into_bytes();
        let (endpoint, server) = local_server(response);
        let client = test_client_for(&endpoint);
        let request = client.get_bearer(&endpoint, "test-token", &[]).unwrap();
        let response = client
            .client
            .execute(request.build().unwrap())
            .await
            .unwrap();

        let error = client.read_limited_body(response).await.unwrap_err();

        assert_eq!(error.code, QuotaErrorCode::SchemaChanged);
        server.join().unwrap();
    }

    #[tokio::test]
    async fn rejects_chunked_response_bodies_larger_than_the_named_limit() {
        let chunk = vec![b'x'; MAX_RESPONSE_BODY_BYTES + 1];
        let mut response = format!(
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n{:X}\r\n",
            chunk.len()
        )
        .into_bytes();
        response.extend_from_slice(&chunk);
        response.extend_from_slice(b"\r\n0\r\n\r\n");
        let (endpoint, server) = local_server(response);
        let client = test_client_for(&endpoint);
        let request = client.get_bearer(&endpoint, "test-token", &[]).unwrap();
        let response = client
            .client
            .execute(request.build().unwrap())
            .await
            .unwrap();

        let error = client.read_limited_body(response).await.unwrap_err();

        assert_eq!(error.code, QuotaErrorCode::SchemaChanged);
        server.join().unwrap();
    }

    fn test_client_for(endpoint: &str) -> RedactingHttpClient {
        let host = reqwest::Url::parse(endpoint)
            .unwrap()
            .host_str()
            .unwrap()
            .to_owned();
        RedactingHttpClient::for_test(host)
    }

    fn local_server(response: Vec<u8>) -> (String, thread::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let endpoint = format!("http://{}/usage", listener.local_addr().unwrap());
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0_u8; 1024];
            let _ = stream.read(&mut request);
            stream.write_all(&response).unwrap();
            stream.flush().unwrap();
        });
        (endpoint, server)
    }
}
