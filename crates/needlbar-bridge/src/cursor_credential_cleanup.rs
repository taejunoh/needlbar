use std::{
    ffi::CString,
    fs::File,
    io,
    os::unix::{
        ffi::OsStrExt,
        io::{AsRawFd, FromRawFd},
    },
    path::Path,
    sync::Once,
};

static CLEANUP_ONCE: Once = Once::new();

const LEGACY_DIRECTORY_COMPONENTS: [&str; 3] = ["Library", "Application Support", "Needlbar"];
const LEGACY_SESSION_FILE: &str = "cursor-session.json";

/// Schedules an asynchronous, best-effort migration of the obsolete Cursor
/// session file. The cleanup is deliberately not observable through the ABI.
pub fn schedule_obsolete_cursor_session_cleanup() {
    CLEANUP_ONCE.call_once(|| {
        let _ = std::thread::Builder::new()
            .name("needlbar-cursor-credential-cleanup".to_owned())
            .spawn(|| {
                if let Some(home) = std::env::var_os("HOME") {
                    let _ = cleanup_obsolete_cursor_session_in_home(Path::new(&home));
                }
            });
    });
}

/// Deletes only a regular legacy Cursor session file below an existing home
/// directory. It never opens the session file for reading or follows legacy
/// directory or file symlinks.
pub fn cleanup_obsolete_cursor_session_in_home(home: &Path) -> io::Result<()> {
    let mut directory = open_home_directory(home)?;
    for component in LEGACY_DIRECTORY_COMPONENTS {
        let Some(child) = open_existing_directory_at(directory.as_raw_fd(), component)? else {
            return Ok(());
        };
        directory = child;
    }

    let file_name = c_name(LEGACY_SESSION_FILE)?;
    let mut metadata = std::mem::MaybeUninit::<libc::stat>::uninit();
    // SAFETY: `directory` is an open directory descriptor and `file_name` is
    // NUL-terminated for the duration of this call. fstatat does not read the
    // referenced file with AT_SYMLINK_NOFOLLOW.
    let status = unsafe {
        libc::fstatat(
            directory.as_raw_fd(),
            file_name.as_ptr(),
            metadata.as_mut_ptr(),
            libc::AT_SYMLINK_NOFOLLOW,
        )
    };
    if status == -1 {
        let error = io::Error::last_os_error();
        return if error.raw_os_error() == Some(libc::ENOENT) {
            Ok(())
        } else {
            Err(error)
        };
    }
    // SAFETY: fstatat returned success and initialized `metadata`.
    let metadata = unsafe { metadata.assume_init() };
    if metadata.st_mode & libc::S_IFMT != libc::S_IFREG {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "legacy Cursor session is not a regular file",
        ));
    }

    // SAFETY: the descriptor and NUL-terminated relative name remain valid;
    // unlinkat removes the directory entry without dereferencing a symlink.
    let status = unsafe { libc::unlinkat(directory.as_raw_fd(), file_name.as_ptr(), 0) };
    if status == -1 {
        let error = io::Error::last_os_error();
        return if error.raw_os_error() == Some(libc::ENOENT) {
            Ok(())
        } else {
            Err(error)
        };
    }
    Ok(())
}

fn open_home_directory(home: &Path) -> io::Result<File> {
    let home = CString::new(home.as_os_str().as_bytes())?;
    // SAFETY: `home` is a NUL-terminated path. O_NOFOLLOW rejects a symlink
    // at the home leaf, while O_DIRECTORY requires an existing directory.
    let descriptor = unsafe {
        libc::open(
            home.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if descriptor == -1 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: open returned a new owned file descriptor.
    Ok(unsafe { File::from_raw_fd(descriptor) })
}

fn open_existing_directory_at(parent: i32, name: &str) -> io::Result<Option<File>> {
    let name = c_name(name)?;
    // SAFETY: `parent` is an open directory descriptor and `name` is a
    // NUL-terminated single relative path component.
    let descriptor = unsafe {
        libc::openat(
            parent,
            name.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if descriptor == -1 {
        let error = io::Error::last_os_error();
        return if error.raw_os_error() == Some(libc::ENOENT) {
            Ok(None)
        } else {
            Err(error)
        };
    }
    // SAFETY: openat returned a new owned directory descriptor.
    Ok(Some(unsafe { File::from_raw_fd(descriptor) }))
}

fn c_name(name: &str) -> io::Result<CString> {
    CString::new(name).map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid path"))
}
