use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
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
    #[error("Cursor sync refused an unsafe path: {0}")]
    UnsafePath(String),
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
        if validate_cursor_csv(&csv).is_err() {
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
    let cache_dir = ensure_cache_dir(home)?;
    let cache_path = cache_dir.join("usage.csv");

    if !force && sync_is_fresh(&cache_dir, &cache_path) {
        return Ok(CursorSyncOutcome {
            synced: false,
            rows: 0,
            cache_path,
            error: None,
        });
    }

    let outcome = match load_cursor_session(home) {
        Ok(session) => match transport.export_usage_csv(&session.session_token).await {
            Ok(csv) => match validate_cursor_csv(&csv) {
                Ok(rows) => match atomic_write(&cache_path, csv.as_bytes()) {
                    Ok(()) => CursorSyncOutcome {
                        synced: true,
                        rows,
                        cache_path: cache_path.clone(),
                        error: None,
                    },
                    Err(error) => failed_outcome(&cache_path, error),
                },
                Err(error) => failed_outcome(&cache_path, error),
            },
            Err(error) => failed_outcome(&cache_path, error),
        },
        Err(error) => failed_outcome(&cache_path, error),
    };

    if let Err(error) = touch_attempt_marker(&cache_dir) {
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
    let directory = ensure_session_dir(home)?;
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

fn load_cursor_session(home: &Path) -> Result<CursorSession, SourceSyncError> {
    let contents = match read_regular_file_no_follow(&session_dir(home).join(SESSION_FILE_NAME)) {
        Ok(contents) => contents,
        Err(SourceSyncError::Io(message)) if message == "not found" => {
            return Err(SourceSyncError::MissingSession)
        }
        Err(error) => return Err(error),
    };
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
    let Ok(metadata) = fs::symlink_metadata(path) else {
        return false;
    };
    if metadata.file_type().is_symlink() || !metadata.file_type().is_file() {
        return false;
    }
    let Ok(modified) = metadata.modified() else {
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

fn ensure_session_dir(home: &Path) -> Result<PathBuf, SourceSyncError> {
    ensure_private_dir_under(home, &["Library", "Application Support", "Needlbar"])
}

fn ensure_cache_dir(home: &Path) -> Result<PathBuf, SourceSyncError> {
    ensure_private_dir_under(home, &[".config", "tokscale", "cursor-cache"])
}

fn ensure_private_dir_under(home: &Path, components: &[&str]) -> Result<PathBuf, SourceSyncError> {
    ensure_directory(home)?;
    let mut current = home.to_path_buf();
    for component in components {
        current.push(component);
        match fs::symlink_metadata(&current) {
            Ok(metadata) => ensure_directory_metadata(&current, &metadata)?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                fs::create_dir(&current).map_err(io_error)?;
                let metadata = fs::symlink_metadata(&current).map_err(io_error)?;
                ensure_directory_metadata(&current, &metadata)?;
            }
            Err(error) => return Err(io_error(error)),
        }
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        open_directory_no_follow(&current)?
            .set_permissions(fs::Permissions::from_mode(0o700))
            .map_err(io_error)?;
    }
    Ok(current)
}

fn ensure_directory(path: &Path) -> Result<(), SourceSyncError> {
    let metadata = fs::symlink_metadata(path).map_err(io_error)?;
    ensure_directory_metadata(path, &metadata)
}

fn ensure_directory_metadata(path: &Path, metadata: &fs::Metadata) -> Result<(), SourceSyncError> {
    if metadata.file_type().is_symlink() || !metadata.file_type().is_dir() {
        return Err(SourceSyncError::UnsafePath(path.display().to_string()));
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
    ensure_directory(parent)?;
    ensure_regular_or_missing(path)?;
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
            options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
        }
        let mut file = options.open(&temp_path).map_err(io_error)?;
        file.write_all(contents).map_err(io_error)?;
        file.sync_all().map_err(io_error)?;
        ensure_regular_or_missing(path)?;
        fs::rename(&temp_path, path).map_err(io_error)?;
        sync_directory(parent)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    result
}

fn private_open(path: &Path, truncate: bool) -> Result<File, SourceSyncError> {
    ensure_regular_or_missing(path)?;
    let mut options = OpenOptions::new();
    options.write(true).create(true).truncate(truncate);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
    }
    let file = options.open(path).map_err(io_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(io_error)?;
    }
    Ok(file)
}

fn read_regular_file_no_follow(path: &Path) -> Result<Vec<u8>, SourceSyncError> {
    let metadata = fs::symlink_metadata(path).map_err(|error| {
        if error.kind() == std::io::ErrorKind::NotFound {
            SourceSyncError::Io("not found".to_owned())
        } else {
            io_error(error)
        }
    })?;
    ensure_regular_file_metadata(path, &metadata)?;
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_NOFOLLOW);
    }
    let mut file = options.open(path).map_err(io_error)?;
    ensure_regular_file_metadata(path, &file.metadata().map_err(io_error)?)?;
    let mut contents = Vec::new();
    file.read_to_end(&mut contents).map_err(io_error)?;
    Ok(contents)
}

fn ensure_regular_or_missing(path: &Path) -> Result<(), SourceSyncError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => ensure_regular_file_metadata(path, &metadata),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(io_error(error)),
    }
}

fn ensure_regular_file_metadata(
    path: &Path,
    metadata: &fs::Metadata,
) -> Result<(), SourceSyncError> {
    if metadata.file_type().is_symlink() || !metadata.file_type().is_file() {
        return Err(SourceSyncError::UnsafePath(path.display().to_string()));
    }
    Ok(())
}

fn sync_directory(path: &Path) -> Result<(), SourceSyncError> {
    open_directory_no_follow(path)?.sync_all().map_err(io_error)
}

fn open_directory_no_follow(path: &Path) -> Result<File, SourceSyncError> {
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW);
    }
    options.open(path).map_err(io_error)
}

fn validate_cursor_csv(csv: &str) -> Result<usize, SourceSyncError> {
    let mut lines = csv.lines();
    let header = lines.next().ok_or(SourceSyncError::InvalidCsv)?;
    let header_fields = parse_csv_line(header).ok_or(SourceSyncError::InvalidCsv)?;
    let layout = cursor_csv_layout(&header_fields).ok_or(SourceSyncError::InvalidCsv)?;
    let rows = lines
        .filter(|line| !line.trim().is_empty())
        .filter_map(|line| parse_csv_line(line))
        .filter(|fields| fields.len() >= layout.minimum_fields)
        .filter(|fields| {
            let date = fields[0].trim().trim_matches('"');
            let model = fields[layout.model_index].trim().trim_matches('"');
            valid_cursor_date(date) && !model.is_empty()
        })
        .count();
    (rows > 0)
        .then_some(rows)
        .ok_or(SourceSyncError::InvalidCsv)
}

struct CursorCsvLayout {
    model_index: usize,
    minimum_fields: usize,
}

fn cursor_csv_layout(header: &[&str]) -> Option<CursorCsvLayout> {
    let field = |index: usize| header_field(header, index);
    let common = |model_index| {
        field(0) == Some("Date")
            && field(model_index) == Some("Model")
            && field(model_index + 2) == Some("Input (w/ Cache Write)")
            && field(model_index + 3) == Some("Input (w/o Cache Write)")
            && field(model_index + 4) == Some("Cache Read")
            && field(model_index + 5) == Some("Output Tokens")
            && field(model_index + 6) == Some("Total Tokens")
            && field(model_index + 7) == Some("Cost")
    };
    if header.len() >= 12 && field(3) == Some("Kind") && field(5) == Some("Max Mode") && common(4) {
        Some(CursorCsvLayout {
            model_index: 4,
            minimum_fields: 12,
        })
    } else if header.len() >= 10
        && field(1) == Some("Kind")
        && field(3) == Some("Max Mode")
        && common(2)
    {
        Some(CursorCsvLayout {
            model_index: 2,
            minimum_fields: 10,
        })
    } else if header.len() >= 8 && common(1) {
        Some(CursorCsvLayout {
            model_index: 1,
            minimum_fields: 8,
        })
    } else {
        None
    }
}

fn header_field<'a>(header: &'a [&'a str], index: usize) -> Option<&'a str> {
    header
        .get(index)
        .map(|value| value.trim().trim_matches('"'))
}

fn parse_csv_line(line: &str) -> Option<Vec<&str>> {
    let mut fields = Vec::new();
    let mut start = 0;
    let mut in_quotes = false;
    for (index, byte) in line.as_bytes().iter().copied().enumerate() {
        match byte {
            b'"' => in_quotes = !in_quotes,
            b',' if !in_quotes => {
                fields.push(&line[start..index]);
                start = index + 1;
            }
            _ => {}
        }
    }
    (!in_quotes).then(|| {
        fields.push(&line[start..]);
        fields
    })
}

fn valid_cursor_date(value: &str) -> bool {
    use chrono::NaiveDateTime;

    [
        "%Y-%m-%dT%H:%M:%S%.3fZ",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%dT%H:%M:%S%.3f",
        "%Y-%m-%dT%H:%M:%S",
    ]
    .iter()
    .any(|format| NaiveDateTime::parse_from_str(value, format).is_ok())
        || chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d").is_ok()
}

fn io_error(error: std::io::Error) -> SourceSyncError {
    SourceSyncError::Io(error.to_string())
}
