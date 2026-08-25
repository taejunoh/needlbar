//! Feature-gated test harness. This module and its symbols are absent from
//! normal production builds and release artifacts, the public C header, and
//! `make run`.

use std::{
    ffi::{c_char, CStr},
    path::PathBuf,
    sync::{Arc, LazyLock, Mutex, MutexGuard},
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

type AllQuotaProviders = (
    Arc<dyn QuotaProvider>,
    Arc<dyn QuotaProvider>,
    Arc<dyn QuotaProvider>,
);

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
    ProviderVerification(ProviderVerificationFixture),
    ProviderVerificationBlocking(BlockingClaudeFixture),
    ProviderVerificationPanic,
}

static FIXTURE_RUNTIME: LazyLock<Mutex<Option<FixtureRuntime>>> =
    LazyLock::new(|| Mutex::new(None));
static FIXTURE_SERIAL: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

/// Keeps feature-gated integration fixtures isolated despite Rust's parallel
/// test execution. Production bridge code never observes this lock.
pub fn serial_guard() -> MutexGuard<'static, ()> {
    FIXTURE_SERIAL
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

pub struct ProviderVerificationScope {
    _guard: MutexGuard<'static, ()>,
}

pub fn provider_verification_scope() -> ProviderVerificationScope {
    ProviderVerificationScope {
        _guard: serial_guard(),
    }
}

impl ProviderVerificationScope {
    pub fn install(
        &self,
        claude: Result<ProviderQuotaSnapshot, QuotaError>,
        codex: Result<ProviderQuotaSnapshot, QuotaError>,
    ) -> ProviderVerificationFixture {
        install_provider_verification_fixture(claude, codex)
    }
    pub fn clear(&self) {
        needlbar_test_clear_runtime();
    }
    pub fn install_blocking_claude_fixture(&self) -> BlockingClaudeFixture {
        let fixture = install_provider_verification_fixture(
            Ok(fixture_snapshot(ProviderId::Claude, "claude.session", 20.0)),
            Ok(fixture_snapshot(ProviderId::Codex, "codex.primary", 50.0)),
        );
        let blocking = BlockingClaudeFixture::new(fixture);
        install_runtime(FixtureRuntime {
            home: PathBuf::new(),
            mode: FixtureMode::ProviderVerificationBlocking(blocking.clone()),
        });
        blocking
    }
}

#[derive(Clone)]
pub struct BlockingClaudeFixture {
    fixture: ProviderVerificationFixture,
    state: Arc<(Mutex<(bool, bool)>, std::sync::Condvar)>,
}

impl BlockingClaudeFixture {
    fn new(fixture: ProviderVerificationFixture) -> Self {
        Self {
            fixture,
            state: Arc::new((Mutex::new((false, false)), std::sync::Condvar::new())),
        }
    }
    pub fn wait_until_fetch_started(&self) {
        let (lock, signal) = &*self.state;
        let mut state = lock.lock().expect("blocking fixture lock");
        while !state.0 {
            state = signal.wait(state).expect("blocking fixture wait");
        }
    }
    pub fn allow_fetch_to_finish(&self) {
        let (lock, signal) = &*self.state;
        lock.lock().expect("blocking fixture lock").1 = true;
        signal.notify_all();
    }
    fn wait_for_release(&self) {
        let (lock, signal) = &*self.state;
        let mut state = lock.lock().expect("blocking fixture lock");
        state.0 = true;
        signal.notify_all();
        while !state.1 {
            state = signal.wait(state).expect("blocking fixture wait");
        }
    }
}

#[derive(Clone)]
pub struct ProviderVerificationFixture {
    claude_result: Result<ProviderQuotaSnapshot, QuotaError>,
    codex_result: Result<ProviderQuotaSnapshot, QuotaError>,
    observations: Arc<Mutex<ProviderVerificationObservations>>,
}

#[derive(Default)]
struct ProviderVerificationObservations {
    claude_accesses: Vec<needlbar_quota::ClaudeCredentialAccess>,
    codex_fetches: usize,
    claude_creations: usize,
    codex_creations: usize,
    cursor_creations: usize,
}

impl ProviderVerificationFixture {
    pub fn claude_accesses(&self) -> Vec<&'static str> {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .claude_accesses
            .iter()
            .map(|access| match access {
                needlbar_quota::ClaudeCredentialAccess::BackgroundNoUI => "backgroundNoUI",
                needlbar_quota::ClaudeCredentialAccess::UserInitiatedAllowUI => {
                    "userInitiatedAllowUI"
                }
            })
            .collect()
    }

    pub fn codex_fetches(&self) -> usize {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .codex_fetches
    }

    pub fn claude_creations(&self) -> usize {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .claude_creations
    }

    pub fn codex_creations(&self) -> usize {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .codex_creations
    }

    pub fn cursor_creations(&self) -> usize {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .cursor_creations
    }

    fn record_creation(&self, provider: ProviderId) {
        let mut observations = self
            .observations
            .lock()
            .expect("provider verification observations lock");
        match provider {
            ProviderId::Claude => observations.claude_creations += 1,
            ProviderId::Codex => observations.codex_creations += 1,
            ProviderId::Cursor => observations.cursor_creations += 1,
        }
    }

    fn record_claude_access(&self, access: needlbar_quota::ClaudeCredentialAccess) {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .claude_accesses
            .push(access);
    }

    fn record_codex_fetch(&self) {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .codex_fetches += 1;
    }
}

pub fn fixture_snapshot(
    provider: ProviderId,
    window_id: &str,
    used_percent: f64,
) -> ProviderQuotaSnapshot {
    ProviderQuotaSnapshot {
        provider,
        windows: vec![QuotaWindow::new(window_id, "Fixture", used_percent, None)
            .expect("valid fixture quota")],
    }
}

pub fn fixture_permission_denied(canary: &str) -> QuotaError {
    QuotaError {
        provider: Some(ProviderId::Claude),
        code: QuotaErrorCode::PermissionDenied,
        message: Box::leak(format!("credential {canary}").into_boxed_str()),
        retry_after: None,
        action: None,
    }
}

pub fn install_provider_verification_fixture(
    claude_result: Result<ProviderQuotaSnapshot, QuotaError>,
    codex_result: Result<ProviderQuotaSnapshot, QuotaError>,
) -> ProviderVerificationFixture {
    let fixture = ProviderVerificationFixture {
        claude_result,
        codex_result,
        observations: Arc::new(Mutex::new(ProviderVerificationObservations::default())),
    };
    install_runtime(FixtureRuntime {
        home: PathBuf::new(),
        mode: FixtureMode::ProviderVerification(fixture.clone()),
    });
    fixture
}

pub fn install_provider_verification_panic_fixture() {
    install_runtime(FixtureRuntime {
        home: PathBuf::new(),
        mode: FixtureMode::ProviderVerificationPanic,
    });
}

pub fn reset_ffi_allocation_counts() {
    crate::reset_ffi_allocation_counts();
}

pub fn ffi_allocation_counts() -> (usize, usize, usize) {
    crate::ffi_allocation_counts()
}

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
        FixtureMode::ProviderVerification(_)
        | FixtureMode::ProviderVerificationBlocking(_)
        | FixtureMode::ProviderVerificationPanic => {
            return None;
        }
    }
    Some(envelope)
}

pub fn quota_envelope() -> Option<Envelope<QuotaPayload>> {
    fixture_runtime()?;
    let collection = collect_fixture_quota(FixtureQuotaRequest::All);
    Some(quota::envelope_from_collection(collection))
}

pub fn claude_user_initiated_quota_envelope() -> Option<Envelope<QuotaPayload>> {
    fixture_runtime()?;
    let collection = collect_fixture_quota(FixtureQuotaRequest::ClaudeUserInitiated);
    Some(quota::envelope_from_collection(collection))
}

pub fn codex_quota_envelope() -> Option<Envelope<QuotaPayload>> {
    fixture_runtime()?;
    let collection = collect_fixture_quota(FixtureQuotaRequest::CodexOnly);
    Some(quota::envelope_from_collection(collection))
}

/// Factory-level fixture injection. The exported ABI still runs its normal
/// envelope and dedicated worker; only external provider construction changes.
pub fn all_quota_providers() -> Option<AllQuotaProviders> {
    let runtime = fixture_runtime()?;
    Some(match runtime.mode {
        FixtureMode::Integration => (
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
        } => (
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
        FixtureMode::ProviderVerification(fixture) => {
            fixture.record_creation(ProviderId::Claude);
            fixture.record_creation(ProviderId::Codex);
            fixture.record_creation(ProviderId::Cursor);
            (
                Arc::new(ProviderVerificationQuotaProvider::new(
                    ProviderId::Claude,
                    fixture.claude_result.clone(),
                    fixture.clone(),
                )),
                Arc::new(ProviderVerificationQuotaProvider::new(
                    ProviderId::Codex,
                    fixture.codex_result.clone(),
                    fixture.clone(),
                )),
                Arc::new(ProviderVerificationQuotaProvider::new(
                    ProviderId::Cursor,
                    Err(QuotaError {
                        provider: Some(ProviderId::Cursor),
                        code: QuotaErrorCode::RequiresAuthentication,
                        message: "Cursor authentication was not available.",
                        retry_after: None,
                        action: None,
                    }),
                    fixture,
                )),
            )
        }
        FixtureMode::ProviderVerificationBlocking(blocking) => (
            Arc::new(ProviderVerificationQuotaProvider::new(
                ProviderId::Claude,
                blocking.fixture.claude_result.clone(),
                blocking.fixture.clone(),
            )),
            Arc::new(ProviderVerificationQuotaProvider::new(
                ProviderId::Codex,
                blocking.fixture.codex_result.clone(),
                blocking.fixture.clone(),
            )),
            Arc::new(ProviderVerificationQuotaProvider::new(
                ProviderId::Cursor,
                Err(QuotaError {
                    provider: Some(ProviderId::Cursor),
                    code: QuotaErrorCode::RequiresAuthentication,
                    message: "Cursor authentication was not available.",
                    retry_after: None,
                    action: None,
                }),
                blocking.fixture,
            )),
        ),
        FixtureMode::ProviderVerificationPanic => (
            Arc::new(PanicProvider),
            Arc::new(PanicProvider),
            Arc::new(PanicProvider),
        ),
    })
}

pub fn claude_user_initiated_source() -> Option<Arc<dyn quota::ClaudeUserInitiatedQuotaSource>> {
    let runtime = fixture_runtime()?;
    Some(match runtime.mode {
        FixtureMode::Integration => Arc::new(FixtureClaudeUserInitiatedSource::success(
            "claude.session",
            20.0,
        )),
        FixtureMode::Redaction { claude_failure, .. } => {
            Arc::new(FixtureClaudeUserInitiatedSource::failure(
                QuotaErrorCode::RequiresAuthentication,
                claude_failure,
            ))
        }
        FixtureMode::ProviderVerification(fixture) => {
            fixture.record_creation(ProviderId::Claude);
            Arc::new(ProviderVerificationClaudeSource::new(fixture))
        }
        FixtureMode::ProviderVerificationBlocking(blocking) => {
            Arc::new(BlockingClaudeSource { blocking })
        }
        FixtureMode::ProviderVerificationPanic => Arc::new(PanicClaudeSource),
    })
}

pub fn codex_quota_provider() -> Option<Arc<dyn QuotaProvider>> {
    let runtime = fixture_runtime()?;
    Some(match runtime.mode {
        FixtureMode::Integration => Arc::new(FixtureQuotaProvider::success(
            ProviderId::Codex,
            "codex.primary",
            50.0,
        )),
        FixtureMode::Redaction { codex_failure, .. } => Arc::new(FixtureQuotaProvider::failure(
            ProviderId::Codex,
            QuotaErrorCode::NetworkUnavailable,
            None,
            codex_failure,
        )),
        FixtureMode::ProviderVerification(fixture) => {
            fixture.record_creation(ProviderId::Codex);
            Arc::new(ProviderVerificationQuotaProvider::new(
                ProviderId::Codex,
                fixture.codex_result.clone(),
                fixture,
            ))
        }
        FixtureMode::ProviderVerificationBlocking(blocking) => {
            Arc::new(ProviderVerificationQuotaProvider::new(
                ProviderId::Codex,
                blocking.fixture.codex_result.clone(),
                blocking.fixture,
            ))
        }
        FixtureMode::ProviderVerificationPanic => Arc::new(PanicProvider),
    })
}

fn fixture_runtime() -> Option<FixtureRuntime> {
    FIXTURE_RUNTIME
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
}

#[derive(Clone, Copy)]
enum FixtureQuotaRequest {
    All,
    ClaudeUserInitiated,
    CodexOnly,
}

fn collect_fixture_quota(request: FixtureQuotaRequest) -> QuotaCollection {
    let mode = fixture_runtime()
        .expect("fixture quota only runs while a fixture runtime is installed")
        .mode;
    let worker = thread::Builder::new()
        .name("needlbar-test-fixture-quota".to_owned())
        .spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("test quota runtime");
            runtime.block_on(async move {
                match (mode, request) {
                    (FixtureMode::Integration, FixtureQuotaRequest::All) => {
                        quota::collect_quota_with_providers(
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
                        )
                        .await
                    }
                    (FixtureMode::Integration, FixtureQuotaRequest::ClaudeUserInitiated) => {
                        quota::collect_claude_user_initiated_with_source(Arc::new(
                            FixtureClaudeUserInitiatedSource::success("claude.session", 20.0),
                        ))
                        .await
                    }
                    (FixtureMode::Integration, FixtureQuotaRequest::CodexOnly) => {
                        quota::collect_codex_with_provider(Arc::new(FixtureQuotaProvider::success(
                            ProviderId::Codex,
                            "codex.primary",
                            50.0,
                        )))
                        .await
                    }
                    (
                        FixtureMode::Redaction {
                            claude_failure,
                            codex_failure,
                            cursor_failure,
                        },
                        FixtureQuotaRequest::All,
                    ) => {
                        quota::collect_quota_with_providers(
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
                        )
                        .await
                    }
                    (
                        FixtureMode::Redaction { claude_failure, .. },
                        FixtureQuotaRequest::ClaudeUserInitiated,
                    ) => {
                        quota::collect_claude_user_initiated_with_source(Arc::new(
                            FixtureClaudeUserInitiatedSource::failure(
                                QuotaErrorCode::RequiresAuthentication,
                                claude_failure,
                            ),
                        ))
                        .await
                    }
                    (
                        FixtureMode::Redaction { codex_failure, .. },
                        FixtureQuotaRequest::CodexOnly,
                    ) => {
                        quota::collect_codex_with_provider(Arc::new(FixtureQuotaProvider::failure(
                            ProviderId::Codex,
                            QuotaErrorCode::NetworkUnavailable,
                            None,
                            codex_failure,
                        )))
                        .await
                    }
                    (FixtureMode::ProviderVerification(fixture), FixtureQuotaRequest::All) => {
                        fixture.record_creation(ProviderId::Claude);
                        fixture.record_creation(ProviderId::Codex);
                        fixture.record_creation(ProviderId::Cursor);
                        quota::collect_quota_with_providers(
                            Arc::new(ProviderVerificationQuotaProvider::new(
                                ProviderId::Claude,
                                fixture.claude_result.clone(),
                                fixture.clone(),
                            )),
                            Arc::new(ProviderVerificationQuotaProvider::new(
                                ProviderId::Codex,
                                fixture.codex_result.clone(),
                                fixture.clone(),
                            )),
                            Arc::new(ProviderVerificationQuotaProvider::new(
                                ProviderId::Cursor,
                                Err(QuotaError {
                                    provider: Some(ProviderId::Cursor),
                                    code: QuotaErrorCode::RequiresAuthentication,
                                    message: "Cursor authentication was not available.",
                                    retry_after: None,
                                    action: None,
                                }),
                                fixture,
                            )),
                        )
                        .await
                    }
                    (
                        FixtureMode::ProviderVerification(fixture),
                        FixtureQuotaRequest::ClaudeUserInitiated,
                    ) => {
                        fixture.record_creation(ProviderId::Claude);
                        quota::collect_claude_user_initiated_with_source(Arc::new(
                            ProviderVerificationClaudeSource::new(fixture),
                        ))
                        .await
                    }
                    (
                        FixtureMode::ProviderVerification(fixture),
                        FixtureQuotaRequest::CodexOnly,
                    ) => {
                        fixture.record_creation(ProviderId::Codex);
                        quota::collect_codex_with_provider(Arc::new(
                            ProviderVerificationQuotaProvider::new(
                                ProviderId::Codex,
                                fixture.codex_result.clone(),
                                fixture,
                            ),
                        ))
                        .await
                    }
                    (FixtureMode::ProviderVerificationPanic, _) => {
                        panic!("provider verification fixture panic")
                    }
                    (FixtureMode::ProviderVerificationBlocking(_), _) => {
                        panic!("blocking fixture uses factory injection")
                    }
                }
            })
        })
        .expect("test quota worker starts");
    worker.join().expect("test quota worker joins")
}

struct FixtureClaudeUserInitiatedSource {
    result: Result<ProviderQuotaSnapshot, QuotaError>,
}

impl FixtureClaudeUserInitiatedSource {
    fn success(window_id: &str, used_percent: f64) -> Self {
        Self {
            result: Ok(fixture_snapshot(
                ProviderId::Claude,
                window_id,
                used_percent,
            )),
        }
    }

    fn failure(code: QuotaErrorCode, source_detail: String) -> Self {
        Self {
            result: Err(QuotaError {
                provider: Some(ProviderId::Claude),
                code,
                message: Box::leak(source_detail.into_boxed_str()),
                retry_after: None,
                action: None,
            }),
        }
    }
}

impl quota::ClaudeUserInitiatedQuotaSource for FixtureClaudeUserInitiatedSource {
    fn fetch_with_credential_access<'a>(
        &'a self,
        _access: needlbar_quota::ClaudeCredentialAccess,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = Result<ProviderQuotaSnapshot, QuotaError>> + Send + 'a,
        >,
    > {
        Box::pin(async move { self.result.clone() })
    }
}

struct ProviderVerificationClaudeSource {
    fixture: ProviderVerificationFixture,
}

struct BlockingClaudeSource {
    blocking: BlockingClaudeFixture,
}

impl quota::ClaudeUserInitiatedQuotaSource for BlockingClaudeSource {
    fn fetch_with_credential_access<'a>(
        &'a self,
        access: needlbar_quota::ClaudeCredentialAccess,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = Result<ProviderQuotaSnapshot, QuotaError>> + Send + 'a,
        >,
    > {
        self.blocking.fixture.record_claude_access(access);
        Box::pin(async move {
            self.blocking.wait_for_release();
            self.blocking.fixture.claude_result.clone()
        })
    }
}

impl ProviderVerificationClaudeSource {
    fn new(fixture: ProviderVerificationFixture) -> Self {
        Self { fixture }
    }
}

impl quota::ClaudeUserInitiatedQuotaSource for ProviderVerificationClaudeSource {
    fn fetch_with_credential_access<'a>(
        &'a self,
        access: needlbar_quota::ClaudeCredentialAccess,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = Result<ProviderQuotaSnapshot, QuotaError>> + Send + 'a,
        >,
    > {
        self.fixture.record_claude_access(access);
        Box::pin(async move { self.fixture.claude_result.clone() })
    }
}

struct ProviderVerificationQuotaProvider {
    provider: ProviderId,
    result: Result<ProviderQuotaSnapshot, QuotaError>,
    fixture: ProviderVerificationFixture,
}

impl ProviderVerificationQuotaProvider {
    fn new(
        provider: ProviderId,
        result: Result<ProviderQuotaSnapshot, QuotaError>,
        fixture: ProviderVerificationFixture,
    ) -> Self {
        Self {
            provider,
            result,
            fixture,
        }
    }
}

#[async_trait]
impl QuotaProvider for ProviderVerificationQuotaProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        match self.provider {
            ProviderId::Claude => self
                .fixture
                .record_claude_access(needlbar_quota::ClaudeCredentialAccess::BackgroundNoUI),
            ProviderId::Codex => self.fixture.record_codex_fetch(),
            ProviderId::Cursor => {}
        }
        self.result.clone()
    }
}

struct PanicProvider;

#[async_trait]
impl QuotaProvider for PanicProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        panic!("provider verification fixture panic")
    }
}

struct PanicClaudeSource;

impl quota::ClaudeUserInitiatedQuotaSource for PanicClaudeSource {
    fn fetch_with_credential_access<'a>(
        &'a self,
        _access: needlbar_quota::ClaudeCredentialAccess,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = Result<ProviderQuotaSnapshot, QuotaError>> + Send + 'a,
        >,
    > {
        Box::pin(async { panic!("provider verification fixture panic") })
    }
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
