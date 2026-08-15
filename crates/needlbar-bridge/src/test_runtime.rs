//! Feature-gated test harness. This module and its symbols are absent from
//! normal production builds and release artifacts, the public C header, and
//! `make run`.

use std::{
    ffi::{c_char, CStr},
    path::PathBuf,
    sync::{Arc, LazyLock, Mutex},
    thread,
};

use async_trait::async_trait;
use needlbar_quota::{
    ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaProvider, QuotaWindow,
};

use crate::{
    envelope::{BridgeError, Envelope},
    quota::{self, QuotaCollection, QuotaPayload},
    usage::{self, UsagePayload},
};

#[derive(Clone)]
struct FixtureRuntime {
    home: PathBuf,
    mode: FixtureMode,
}

#[derive(Clone)]
enum FixtureMode {
    Integration,
    Redaction {
        claude_failure: String,
        codex_failure: String,
        cursor_failure: String,
    },
}

static FIXTURE_RUNTIME: LazyLock<Mutex<Option<FixtureRuntime>>> =
    LazyLock::new(|| Mutex::new(None));

/// Test-only fixture setup. This symbol is intentionally not declared in the
/// public C header and exists only with the `bridge-test-runtime` Cargo feature.
#[no_mangle]
pub unsafe extern "C" fn needlbar_test_install_fixture_runtime(home: *const c_char) -> bool {
    if home.is_null() {
        return false;
    }
    let home = match unsafe { CStr::from_ptr(home) }.to_str() {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => return false,
    };
    if !home.is_dir() {
        return false;
    }
    install_runtime(FixtureRuntime {
        home,
        mode: FixtureMode::Integration,
    });
    true
}

/// Installs a Rust-only fixture runtime that carries deliberately unsafe fake
/// upstream details. It is available only when this Cargo feature is enabled,
/// and lets the redaction contract test prove the normal ABI never emits them.
pub fn install_redaction_fixture(
    home: PathBuf,
    claude_failure: String,
    codex_failure: String,
    cursor_failure: String,
) -> bool {
    if !home.is_dir() {
        return false;
    }
    install_runtime(FixtureRuntime {
        home,
        mode: FixtureMode::Redaction {
            claude_failure,
            codex_failure,
            cursor_failure,
        },
    });
    true
}

fn install_runtime(runtime: FixtureRuntime) {
    *FIXTURE_RUNTIME
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(runtime);
}

/// Clears the feature-gated fixture runtime after a Swift integration test.
#[no_mangle]
pub extern "C" fn needlbar_test_clear_runtime() {
    *FIXTURE_RUNTIME
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
}

pub fn usage_envelope() -> Option<Envelope<UsagePayload>> {
    let runtime = fixture_runtime()?;
    let providers = match usage::collect_usage_from_home(&runtime.home) {
        Ok(providers) => providers,
        Err(_) => {
            return Some(Envelope::failure(BridgeError {
                provider: None,
                code: "usageReportUnavailable".to_owned(),
                message: "Usage data could not be collected.".to_owned(),
                action: None,
            }));
        }
    };
    let mut envelope = super::usage_envelope_from_providers(providers);
    match runtime.mode {
        FixtureMode::Integration => envelope.errors.push(BridgeError {
            provider: Some("codex".to_owned()),
            code: "providerUnavailable".to_owned(),
            message: "Usage data is unavailable.".to_owned(),
            action: None,
        }),
        FixtureMode::Redaction {
            claude_failure,
            codex_failure,
            cursor_failure,
        } => {
            envelope.errors.extend([
                usage::boundary_error(Some("claude"), "providerUnavailable", claude_failure),
                usage::boundary_error(Some("codex"), "providerUnavailable", codex_failure),
                usage::boundary_error(Some("cursor"), "providerUnavailable", cursor_failure),
            ]);
        }
    }
    Some(envelope)
}

pub fn quota_envelope() -> Option<Envelope<QuotaPayload>> {
    fixture_runtime()?;
    let collection = collect_fixture_quota();
    Some(quota::envelope_from_collection(collection))
}

fn fixture_runtime() -> Option<FixtureRuntime> {
    FIXTURE_RUNTIME
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
}

fn collect_fixture_quota() -> QuotaCollection {
    let mode = fixture_runtime()
        .expect("fixture quota only runs while a fixture runtime is installed")
        .mode;
    let worker = thread::Builder::new()
        .name("needlbar-test-fixture-quota".to_owned())
        .spawn(|| {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("test quota runtime");
            runtime.block_on(match mode {
                FixtureMode::Integration => quota::collect_quota_with_providers(
                    Arc::new(FixtureQuotaProvider::success(
                        ProviderId::Claude,
                        "claude.session",
                        20.0,
                    )),
                    Arc::new(FixtureQuotaProvider::success(
                        ProviderId::Codex,
                        "codex.primary",
                        50.0,
                    )),
                    Arc::new(FixtureQuotaProvider::success(
                        ProviderId::Cursor,
                        "cursor.plan",
                        90.0,
                    )),
                ),
                FixtureMode::Redaction {
                    claude_failure,
                    codex_failure,
                    cursor_failure,
                } => quota::collect_quota_with_providers(
                    Arc::new(FixtureQuotaProvider::failure(
                        ProviderId::Claude,
                        QuotaErrorCode::RequiresAuthentication,
                        None,
                        claude_failure,
                    )),
                    Arc::new(FixtureQuotaProvider::failure(
                        ProviderId::Codex,
                        QuotaErrorCode::NetworkUnavailable,
                        None,
                        codex_failure,
                    )),
                    Arc::new(FixtureQuotaProvider::failure(
                        ProviderId::Cursor,
                        QuotaErrorCode::RequiresAuthentication,
                        Some(needlbar_quota::QuotaAction::ConnectCursor),
                        cursor_failure,
                    )),
                ),
            })
        })
        .expect("test quota worker starts");
    worker.join().expect("test quota worker joins")
}

struct FixtureQuotaProvider {
    result: Result<ProviderQuotaSnapshot, QuotaError>,
}

impl FixtureQuotaProvider {
    fn success(provider: ProviderId, window_id: &str, used_percent: f64) -> Self {
        Self {
            result: Ok(ProviderQuotaSnapshot {
                provider,
                windows: vec![QuotaWindow::new(window_id, "Fixture", used_percent, None)
                    .expect("valid fixture quota")],
            }),
        }
    }

    fn failure(
        provider: ProviderId,
        code: QuotaErrorCode,
        action: Option<needlbar_quota::QuotaAction>,
        source_detail: String,
    ) -> Self {
        Self {
            result: Err(QuotaError {
                provider: Some(provider),
                code,
                // QuotaError deliberately models static messages in production.
                // This feature-only fake emulates an unsafe upstream transport.
                message: Box::leak(source_detail.into_boxed_str()),
                retry_after: None,
                action,
            }),
        }
    }
}

#[async_trait]
impl QuotaProvider for FixtureQuotaProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        self.result.clone()
    }
}

/// Serializes an actual envelope around a usage-boundary failure. It is
/// Rust-only and feature-gated so the contract test can cover BridgeError
/// serialization without a production ABI surface.
pub fn error_envelope_json(source_detail: String) -> String {
    serde_json::to_string(&Envelope::<serde_json::Value>::failure(
        usage::boundary_error(Some("claude"), "providerUnavailable", source_detail),
    ))
    .expect("test error envelope serializes")
}
