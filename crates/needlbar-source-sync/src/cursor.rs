use std::{
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, SystemTime},
};

#[cfg(unix)]
use std::{
    ffi::CString,
    os::{
        fd::{AsRawFd, FromRawFd, RawFd},
        unix::{ffi::OsStrExt, fs::PermissionsExt},
    },
};

#[cfg(not(unix))]
use std::fs::OpenOptions;

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

struct PrivateDirectory {
    path: PathBuf,
    #[cfg(unix)]
    file: File,
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
    let cache_path = cache_dir.path.join("usage.csv");

    if !force && sync_is_fresh(&cache_dir, "usage.csv") {
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
                Ok(rows) => match atomic_write(&cache_dir, "usage.csv", csv.as_bytes()) {
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
    write_private_file(&directory, SESSION_FILE_NAME, &serialized)
}

fn home_dir() -> Result<PathBuf, SourceSyncError> {
    std::env::var_os("HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| {
            SourceSyncError::Io("could not determine the user home directory".to_owned())
        })
}

fn load_cursor_session(home: &Path) -> Result<CursorSession, SourceSyncError> {
    let directory = ensure_session_dir(home)?;
    let contents = match read_regular_file_no_follow(&directory, SESSION_FILE_NAME) {
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

fn sync_is_fresh(cache_dir: &PrivateDirectory, cache_name: &str) -> bool {
    is_fresh(cache_dir, cache_name) || is_fresh(cache_dir, SYNC_ATTEMPT_MARKER)
}

#[cfg(not(unix))]
fn is_fresh(directory: &PrivateDirectory, name: &str) -> bool {
    let path = directory.path.join(name);
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

fn ensure_session_dir(home: &Path) -> Result<PrivateDirectory, SourceSyncError> {
    ensure_private_dir_under(home, &["Library", "Application Support", "Needlbar"])
}

fn ensure_cache_dir(home: &Path) -> Result<PrivateDirectory, SourceSyncError> {
    ensure_private_dir_under(home, &[".config", "tokscale", "cursor-cache"])
}

#[cfg(not(unix))]
fn ensure_private_dir_under(
    home: &Path,
    components: &[&str],
) -> Result<PrivateDirectory, SourceSyncError> {
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
    Ok(PrivateDirectory { path: current })
}

#[cfg(unix)]
fn ensure_private_dir_under(
    home: &Path,
    components: &[&str],
) -> Result<PrivateDirectory, SourceSyncError> {
    let mut directory = open_directory_path_no_follow(home)?;
    for component in components {
        directory = open_or_create_directory_at(&directory, component)?;
    }
    directory
        .file
        .set_permissions(fs::Permissions::from_mode(0o700))
        .map_err(io_error)?;
    Ok(directory)
}

#[cfg(not(unix))]
fn ensure_directory(path: &Path) -> Result<(), SourceSyncError> {
    let metadata = fs::symlink_metadata(path).map_err(io_error)?;
    ensure_directory_metadata(path, &metadata)
}

#[cfg(not(unix))]
fn ensure_directory_metadata(path: &Path, metadata: &fs::Metadata) -> Result<(), SourceSyncError> {
    if metadata.file_type().is_symlink() || !metadata.file_type().is_dir() {
        return Err(SourceSyncError::UnsafePath(path.display().to_string()));
    }
    Ok(())
}

fn write_private_file(
    directory: &PrivateDirectory,
    name: &str,
    contents: &[u8],
) -> Result<(), SourceSyncError> {
    let mut file = private_open(directory, name, true)?;
    file.write_all(contents).map_err(io_error)?;
    file.sync_all().map_err(io_error)
}

fn touch_attempt_marker(cache_dir: &PrivateDirectory) -> Result<(), SourceSyncError> {
    write_private_file(cache_dir, SYNC_ATTEMPT_MARKER, b"")
}

#[cfg(not(unix))]
fn atomic_write(
    directory: &PrivateDirectory,
    name: &str,
    contents: &[u8],
) -> Result<(), SourceSyncError> {
    let path = directory.path.join(name);
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

#[cfg(not(unix))]
fn private_open(
    directory: &PrivateDirectory,
    name: &str,
    truncate: bool,
) -> Result<File, SourceSyncError> {
    let path = directory.path.join(name);
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

#[cfg(not(unix))]
fn read_regular_file_no_follow(
    directory: &PrivateDirectory,
    name: &str,
) -> Result<Vec<u8>, SourceSyncError> {
    let path = directory.path.join(name);
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

#[cfg(not(unix))]
fn ensure_regular_or_missing(path: &Path) -> Result<(), SourceSyncError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => ensure_regular_file_metadata(path, &metadata),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(io_error(error)),
    }
}

#[cfg(not(unix))]
fn ensure_regular_file_metadata(
    path: &Path,
    metadata: &fs::Metadata,
) -> Result<(), SourceSyncError> {
    if metadata.file_type().is_symlink() || !metadata.file_type().is_file() {
        return Err(SourceSyncError::UnsafePath(path.display().to_string()));
    }
    Ok(())
}

#[cfg(not(unix))]
fn sync_directory(path: &Path) -> Result<(), SourceSyncError> {
    open_directory_no_follow(path)?.sync_all().map_err(io_error)
}

#[cfg(not(unix))]
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

#[cfg(unix)]
fn open_directory_path_no_follow(path: &Path) -> Result<PrivateDirectory, SourceSyncError> {
    let path_name = cstring_path(path)?;
    let fd = unsafe {
        libc::open(
            path_name.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if fd < 0 {
        return Err(path_open_error(path, std::io::Error::last_os_error()));
    }
    Ok(PrivateDirectory {
        path: path.to_path_buf(),
        // SAFETY: `open` returned an owned, non-negative descriptor.
        file: unsafe { File::from_raw_fd(fd) },
    })
}

#[cfg(unix)]
fn open_or_create_directory_at(
    parent: &PrivateDirectory,
    name: &str,
) -> Result<PrivateDirectory, SourceSyncError> {
    let child_path = parent.path.join(name);
    let name = cstring_name(name)?;
    let fd = match open_directory_at(parent.file.as_raw_fd(), &name) {
        Ok(fd) => fd,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            let result = unsafe { libc::mkdirat(parent.file.as_raw_fd(), name.as_ptr(), 0o700) };
            if result != 0 {
                let error = std::io::Error::last_os_error();
                if error.kind() != std::io::ErrorKind::AlreadyExists {
                    return Err(path_open_error(&child_path, error));
                }
            }
            open_directory_at(parent.file.as_raw_fd(), &name)
                .map_err(|error| path_open_error(&child_path, error))?
        }
        Err(error) => return Err(path_open_error(&child_path, error)),
    };
    Ok(PrivateDirectory {
        path: child_path,
        // SAFETY: `openat` returned an owned, non-negative descriptor.
        file: unsafe { File::from_raw_fd(fd) },
    })
}

#[cfg(unix)]
fn open_directory_at(parent: RawFd, name: &CString) -> std::io::Result<RawFd> {
    let fd = unsafe {
        libc::openat(
            parent,
            name.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if fd < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(fd)
    }
}

#[cfg(unix)]
fn read_regular_file_at(
    directory: &PrivateDirectory,
    name: &str,
) -> Result<Vec<u8>, SourceSyncError> {
    ensure_regular_or_missing_at(directory, name)?
        .ok_or_else(|| SourceSyncError::Io("not found".to_owned()))?;
    let name_c = cstring_name(name)?;
    let mut file = open_regular_at(directory, &name_c, libc::O_RDONLY, 0)?;
    let mut contents = Vec::new();
    file.read_to_end(&mut contents).map_err(io_error)?;
    Ok(contents)
}

#[cfg(unix)]
fn is_fresh(directory: &PrivateDirectory, name: &str) -> bool {
    let Ok(Some(())) = ensure_regular_or_missing_at(directory, name) else {
        return false;
    };
    let Ok(name) = cstring_name(name) else {
        return false;
    };
    let Ok(file) = open_regular_at(directory, &name, libc::O_RDONLY, 0) else {
        return false;
    };
    let Ok(modified) = file.metadata().and_then(|metadata| metadata.modified()) else {
        return false;
    };
    match SystemTime::now().duration_since(modified) {
        Ok(age) => age < CURSOR_CACHE_FRESHNESS,
        Err(_) => true,
    }
}

#[cfg(unix)]
fn atomic_write(
    directory: &PrivateDirectory,
    name: &str,
    contents: &[u8],
) -> Result<(), SourceSyncError> {
    ensure_regular_or_missing_at(directory, name)?;
    let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let temp_name = format!(".needlbar-usage-{}-{sequence}.tmp", std::process::id());
    let temp_name_c = cstring_name(&temp_name)?;
    let target_name_c = cstring_name(name)?;
    let result = (|| {
        let mut file = open_regular_at(
            directory,
            &temp_name_c,
            libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL,
            0o600,
        )?;
        file.write_all(contents).map_err(io_error)?;
        file.sync_all().map_err(io_error)?;
        ensure_regular_or_missing_at(directory, name)?;
        let renamed = unsafe {
            libc::renameat(
                directory.file.as_raw_fd(),
                temp_name_c.as_ptr(),
                directory.file.as_raw_fd(),
                target_name_c.as_ptr(),
            )
        };
        if renamed != 0 {
            return Err(path_open_error(
                &directory.path.join(name),
                std::io::Error::last_os_error(),
            ));
        }
        directory.file.sync_all().map_err(io_error)
    })();
    if result.is_err() {
        unsafe {
            libc::unlinkat(directory.file.as_raw_fd(), temp_name_c.as_ptr(), 0);
        }
    }
    result
}

#[cfg(unix)]
fn private_open(
    directory: &PrivateDirectory,
    name: &str,
    _truncate: bool,
) -> Result<File, SourceSyncError> {
    let name = cstring_name(name)?;
    ensure_regular_or_missing_at(directory, name.to_str().expect("literal file name"))?;
    let file = open_regular_at(
        directory,
        &name,
        libc::O_WRONLY | libc::O_CREAT | libc::O_TRUNC,
        0o600,
    )?;
    file.set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(io_error)?;
    Ok(file)
}

#[cfg(unix)]
fn read_regular_file_no_follow(
    directory: &PrivateDirectory,
    name: &str,
) -> Result<Vec<u8>, SourceSyncError> {
    read_regular_file_at(directory, name)
}

#[cfg(unix)]
fn ensure_regular_or_missing_at(
    directory: &PrivateDirectory,
    name: &str,
) -> Result<Option<()>, SourceSyncError> {
    let name = cstring_name(name)?;
    let mut stat = std::mem::MaybeUninit::<libc::stat>::uninit();
    let result = unsafe {
        libc::fstatat(
            directory.file.as_raw_fd(),
            name.as_ptr(),
            stat.as_mut_ptr(),
            libc::AT_SYMLINK_NOFOLLOW,
        )
    };
    if result != 0 {
        let error = std::io::Error::last_os_error();
        return if error.kind() == std::io::ErrorKind::NotFound {
            Ok(None)
        } else {
            Err(path_open_error(
                &directory.path.join(name.to_string_lossy().as_ref()),
                error,
            ))
        };
    }
    let stat = unsafe { stat.assume_init() };
    if (stat.st_mode & libc::S_IFMT) != libc::S_IFREG {
        return Err(SourceSyncError::UnsafePath(
            directory
                .path
                .join(name.to_string_lossy().as_ref())
                .display()
                .to_string(),
        ));
    }
    Ok(Some(()))
}

#[cfg(unix)]
fn open_regular_at(
    directory: &PrivateDirectory,
    name: &CString,
    flags: libc::c_int,
    mode: libc::mode_t,
) -> Result<File, SourceSyncError> {
    let fd = unsafe {
        libc::openat(
            directory.file.as_raw_fd(),
            name.as_ptr(),
            flags | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK,
            mode as libc::c_uint,
        )
    };
    if fd < 0 {
        return Err(path_open_error(
            &directory.path.join(name.to_string_lossy().as_ref()),
            std::io::Error::last_os_error(),
        ));
    }
    let file = unsafe { File::from_raw_fd(fd) };
    if !file.metadata().map_err(io_error)?.file_type().is_file() {
        return Err(SourceSyncError::UnsafePath(
            directory
                .path
                .join(name.to_string_lossy().as_ref())
                .display()
                .to_string(),
        ));
    }
    Ok(file)
}

#[cfg(unix)]
fn cstring_path(path: &Path) -> Result<CString, SourceSyncError> {
    CString::new(path.as_os_str().as_bytes())
        .map_err(|_| SourceSyncError::UnsafePath(path.display().to_string()))
}

#[cfg(unix)]
fn cstring_name(name: &str) -> Result<CString, SourceSyncError> {
    CString::new(name).map_err(|_| SourceSyncError::UnsafePath(name.to_owned()))
}

#[cfg(unix)]
fn path_open_error(path: &Path, error: std::io::Error) -> SourceSyncError {
    match error.raw_os_error() {
        Some(libc::ELOOP | libc::ENOTDIR) => {
            SourceSyncError::UnsafePath(path.display().to_string())
        }
        _ => io_error(error),
    }
}

fn validate_cursor_csv(csv: &str) -> Result<usize, SourceSyncError> {
    let mut lines = csv.lines();
    let header = lines.next().ok_or(SourceSyncError::InvalidCsv)?;
    let header_fields = parse_csv_line(header).ok_or(SourceSyncError::InvalidCsv)?;
    let layout = cursor_csv_layout(&header_fields).ok_or(SourceSyncError::InvalidCsv)?;
    let rows = lines
        .filter(|line| !line.trim().is_empty())
        .filter_map(parse_csv_line)
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
    } else if header.len() >= 8
        && field(0) == Some("Date")
        && field(1) == Some("Model")
        && field(2) == Some("Input (w/ Cache Write)")
        && field(3) == Some("Input (w/o Cache Write)")
        && field(4) == Some("Cache Read")
        && field(5) == Some("Output Tokens")
        && field(6) == Some("Total Tokens")
        && field(7) == Some("Cost")
    {
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
