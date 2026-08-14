use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, SystemTime},
};

use async_trait::async_trait;
use chrono::{SecondsFormat, Utc};
use reqwest::header::{HeaderMap, HeaderValue, COOKIE};
use serde::{Deserialize, Serialize};
use thiserror::Error;

const CURSOR_HTTP_TIMEOUT: Duration = Duration::from_secs(15);
const CURSOR_CACHE_FRESHNESS: Duration = Duration::from_secs(5 * 60);
const USAGE_CSV_ENDPOINT: &str =
    "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens";
const SESSION_FILE_NAME: &str = "cursor-session.json";
const SYNC_ATTEMPT_MARKER: &str = "usage.last-sync-attempt";
static TEMP_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Error)]
pub enum SourceSyncError {
    #[error("Cursor session is unavailable")]
    MissingSession,
    #[error("Cursor session file is invalid")]
    InvalidSession,
    #[error("Cursor transport failed: {0}")]
    Transport(String),
    #[error("Cursor returned HTTP status {0}")]
    HttpStatus(u16),
    #[error("Cursor usage export was not CSV")]
    InvalidCsv,
    #[error("Cursor sync I/O failed: {0}")]
    Io(String),
    #[error("Cursor sync runtime is unavailable: {0}")]
    Runtime(String),
}

#[derive(Debug, Clone)]
pub struct CursorSyncOutcome {
    pub synced: bool,
    pub rows: usize,
    pub cache_path: PathBuf,
    pub error: Option<SourceSyncError>,
}

#[async_trait]
pub trait CursorUsageTransport: Send + Sync {
    async fn export_usage_csv(&self, session_token: &str) -> Result<String, SourceSyncError>;
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CursorSession {
    version: u8,
    session_token: String,
    created_at: String,
}

struct ReqwestCursorUsageTransport {
    client: reqwest::Client,
}

impl ReqwestCursorUsageTransport {
    fn new() -> Result<Self, SourceSyncError> {
        let client = reqwest::Client::builder()
            .timeout(CURSOR_HTTP_TIMEOUT)
            .build()
            .map_err(|error| SourceSyncError::Transport(error.to_string()))?;
        Ok(Self { client })
    }
}

#[async_trait]
impl CursorUsageTransport for ReqwestCursorUsageTransport {
    async fn export_usage_csv(&self, session_token: &str) -> Result<String, SourceSyncError> {
        let cookie = HeaderValue::from_str(&format!("WorkosCursorSessionToken={session_token}"))
            .map_err(|_| SourceSyncError::InvalidSession)?;
        let mut headers = HeaderMap::new();
        headers.insert(COOKIE, cookie);

        let response = self
            .client
            .get(USAGE_CSV_ENDPOINT)
            .headers(headers)
            .send()
            .await
            .map_err(|error| SourceSyncError::Transport(error.to_string()))?;
        if !response.status().is_success() {
            return Err(SourceSyncError::HttpStatus(response.status().as_u16()));
        }

        let csv = response
            .text()
            .await
            .map_err(|error| SourceSyncError::Transport(error.to_string()))?;
        if !csv.starts_with("Date,") {
            return Err(SourceSyncError::InvalidCsv);
        }
        Ok(csv)
    }
}

pub fn sync_cursor_cache(force: bool) -> Result<CursorSyncOutcome, SourceSyncError> {
    let home = home_dir()?;
    let transport = ReqwestCursorUsageTransport::new()?;
    sync_cursor_cache_with_transport_in_home(&home, force, &transport)
}

pub fn sync_cursor_cache_with_transport_in_home<T: CursorUsageTransport + ?Sized>(
    home: &Path,
    force: bool,
    transport: &T,
) -> Result<CursorSyncOutcome, SourceSyncError> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| SourceSyncError::Runtime(error.to_string()))?;
    runtime.block_on(sync_cursor_cache_with_transport_in_home_async(
        home, force, transport,
    ))
}

async fn sync_cursor_cache_with_transport_in_home_async<T: CursorUsageTransport + ?Sized>(
    home: &Path,
    force: bool,
    transport: &T,
) -> Result<CursorSyncOutcome, SourceSyncError> {
    let cache_path = cursor_cache_path(home);
    let cache_dir = cache_path
        .parent()
        .expect("Cursor cache path always has a parent");
    ensure_private_dir(cache_dir)?;

    if !force && sync_is_fresh(cache_dir, &cache_path) {
        return Ok(CursorSyncOutcome {
            synced: false,
            rows: 0,
            cache_path,
            error: None,
        });
    }

    let outcome = match load_cursor_session(home) {
        Ok(session) => match transport.export_usage_csv(&session.session_token).await {
            Ok(csv) => match atomic_write(&cache_path, csv.as_bytes()) {
                Ok(()) => CursorSyncOutcome {
                    synced: true,
                    rows: count_csv_rows(&csv),
                    cache_path: cache_path.clone(),
                    error: None,
                },
                Err(error) => failed_outcome(&cache_path, error),
            },
            Err(error) => failed_outcome(&cache_path, error),
        },
        Err(error) => failed_outcome(&cache_path, error),
    };

    if let Err(error) = touch_attempt_marker(cache_dir) {
        return Ok(failed_outcome(&cache_path, error));
    }
    Ok(outcome)
}

pub fn write_cursor_session_in_home(
    home: &Path,
    session_token: &str,
) -> Result<(), SourceSyncError> {
    if session_token.is_empty() {
        return Err(SourceSyncError::InvalidSession);
    }
    let directory = session_dir(home);
    ensure_private_dir(&directory)?;
    let serialized = serde_json::to_vec_pretty(&CursorSession {
        version: 1,
        session_token: session_token.to_owned(),
        created_at: Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true),
    })
    .map_err(|_| SourceSyncError::InvalidSession)?;
    write_private_file(&directory.join(SESSION_FILE_NAME), &serialized)
}

fn home_dir() -> Result<PathBuf, SourceSyncError> {
    std::env::var_os("HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| {
            SourceSyncError::Io("could not determine the user home directory".to_owned())
        })
}

fn session_dir(home: &Path) -> PathBuf {
    home.join("Library/Application Support/Needlbar")
}

fn cursor_cache_path(home: &Path) -> PathBuf {
    home.join(".config/tokscale/cursor-cache/usage.csv")
}

fn load_cursor_session(home: &Path) -> Result<CursorSession, SourceSyncError> {
    let contents = fs::read(session_dir(home).join(SESSION_FILE_NAME)).map_err(|error| {
        if error.kind() == std::io::ErrorKind::NotFound {
            SourceSyncError::MissingSession
        } else {
            SourceSyncError::Io(error.to_string())
        }
    })?;
    let session: CursorSession =
        serde_json::from_slice(&contents).map_err(|_| SourceSyncError::InvalidSession)?;
    if session.version != 1 || session.session_token.is_empty() || session.created_at.is_empty() {
        return Err(SourceSyncError::InvalidSession);
    }
    Ok(session)
}

fn sync_is_fresh(cache_dir: &Path, cache_path: &Path) -> bool {
    is_fresh(cache_path) || is_fresh(&cache_dir.join(SYNC_ATTEMPT_MARKER))
}

fn is_fresh(path: &Path) -> bool {
    let Ok(modified) = path.metadata().and_then(|metadata| metadata.modified()) else {
        return false;
    };
    match SystemTime::now().duration_since(modified) {
        Ok(age) => age < CURSOR_CACHE_FRESHNESS,
        Err(_) => true,
    }
}

fn failed_outcome(cache_path: &Path, error: SourceSyncError) -> CursorSyncOutcome {
    CursorSyncOutcome {
        synced: false,
        rows: 0,
        cache_path: cache_path.to_owned(),
        error: Some(error),
    }
}

fn count_csv_rows(csv: &str) -> usize {
    csv.lines()
        .skip(1)
        .filter(|line| !line.trim().is_empty())
        .count()
}

fn ensure_private_dir(path: &Path) -> Result<(), SourceSyncError> {
    fs::create_dir_all(path).map_err(io_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(io_error)?;
    }
    Ok(())
}

fn write_private_file(path: &Path, contents: &[u8]) -> Result<(), SourceSyncError> {
    let mut file = private_open(path, true)?;
    file.write_all(contents).map_err(io_error)?;
    file.sync_all().map_err(io_error)
}

fn touch_attempt_marker(cache_dir: &Path) -> Result<(), SourceSyncError> {
    write_private_file(&cache_dir.join(SYNC_ATTEMPT_MARKER), b"")
}

fn atomic_write(path: &Path, contents: &[u8]) -> Result<(), SourceSyncError> {
    let parent = path
        .parent()
        .ok_or_else(|| SourceSyncError::Io("invalid Cursor cache path".to_owned()))?;
    let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let temp_path = parent.join(format!(
        ".needlbar-usage-{}-{}.tmp",
        std::process::id(),
        sequence
    ));
    let result = (|| {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&temp_path).map_err(io_error)?;
        file.write_all(contents).map_err(io_error)?;
        file.sync_all().map_err(io_error)?;
        fs::rename(&temp_path, path).map_err(io_error)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    result
}

fn private_open(path: &Path, truncate: bool) -> Result<File, SourceSyncError> {
    let mut options = OpenOptions::new();
    options.write(true).create(true).truncate(truncate);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let file = options.open(path).map_err(io_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(io_error)?;
    }
    Ok(file)
}

fn io_error(error: std::io::Error) -> SourceSyncError {
    SourceSyncError::Io(error.to_string())
}
