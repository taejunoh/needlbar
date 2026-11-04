//! Finds the user's installed `claude`. No shell and no `PATH` search, so shell
//! functions and aliases never apply.

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};

pub struct ClaudeCliLocator {
    candidates: Vec<PathBuf>,
}

impl ClaudeCliLocator {
    pub fn for_home(home: &Path) -> Self {
        Self::with_candidates(vec![
            home.join(".local/bin/claude"),
            PathBuf::from("/opt/homebrew/bin/claude"),
            PathBuf::from("/usr/local/bin/claude"),
        ])
    }

    pub fn with_candidates(candidates: Vec<PathBuf>) -> Self {
        Self { candidates }
    }

    pub fn candidates(&self) -> &[PathBuf] {
        &self.candidates
    }

    /// The first candidate that resolves to an executable regular file.
    pub fn locate(&self) -> Option<PathBuf> {
        self.candidates
            .iter()
            .find_map(|candidate| executable_regular_file(candidate))
    }
}

fn executable_regular_file(path: &Path) -> Option<PathBuf> {
    let resolved = fs::canonicalize(path).ok()?;
    let metadata = fs::metadata(&resolved).ok()?;
    (metadata.is_file() && metadata.permissions().mode() & 0o111 != 0).then_some(resolved)
}
