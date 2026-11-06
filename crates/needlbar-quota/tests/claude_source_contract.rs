//! Source-level checks that the Claude path reads no Keychain item or credential
//! file and calls no private endpoint. This file is outside the scanned trees.

use std::{
    fs,
    path::{Path, PathBuf},
};

use needlbar_quota::USAGE_PROBE_ARGUMENTS;

fn rust_files(directory: &Path, files: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(directory).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            rust_files(&path, files);
        } else if path.extension().is_some_and(|extension| extension == "rs") {
            files.push(path);
        }
    }
}

fn scanned_sources() -> Vec<(PathBuf, String)> {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut files = Vec::new();
    rust_files(&manifest.join("src"), &mut files);
    rust_files(&manifest.join("../needlbar-bridge/src"), &mut files);
    assert!(files.len() > 10, "the source walk found the tree");
    files
        .into_iter()
        .map(|path| {
            let text = fs::read_to_string(&path).unwrap();
            (path, text)
        })
        .collect()
}

#[test]
fn the_claude_path_has_no_keychain_credential_file_or_endpoint_call() {
    for (path, text) in scanned_sources() {
        for forbidden in [
            "security_framework",
            "SecItem",
            "SecKeychain",
            "kSecClass",
            "Claude Code-credentials",
            ".credentials.json",
            "claudeAiOauth",
            "api.anthropic.com",
            "oauth/usage",
            "anthropic-beta",
            "/usr/bin/security",
            "ClaudeCredential",
            "ClaudeOAuthSecret",
        ] {
            assert!(
                !text.contains(forbidden),
                "{} still contains {forbidden}",
                path.display()
            );
        }
    }
}

#[test]
fn the_manifests_no_longer_depend_on_the_keychain_crates() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    for file in ["Cargo.toml", "../../Cargo.toml"] {
        let text = fs::read_to_string(manifest.join(file)).unwrap();
        for forbidden in ["security-framework", "core-foundation", "zeroize"] {
            assert!(!text.contains(forbidden), "{file} still lists {forbidden}");
        }
    }
}

#[test]
fn the_probe_uses_no_shell_or_path_search_and_never_a_login_command() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    for file in [
        "src/providers/claude_usage_probe.rs",
        "src/providers/claude_cli.rs",
    ] {
        let text = fs::read_to_string(manifest.join(file)).unwrap();
        for forbidden in [
            "/bin/sh",
            "/bin/zsh",
            "/bin/bash",
            "\"-c\"",
            "\"-lc\"",
            "var_os(\"PATH\")",
        ] {
            assert!(!text.contains(forbidden), "{file} contains {forbidden}");
        }
    }
    for argument in USAGE_PROBE_ARGUMENTS {
        assert!(!argument.contains("auth"), "{argument}");
        assert!(!argument.contains("login"), "{argument}");
    }
}

#[test]
fn logs_and_errors_have_no_path_to_raw_output() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    for file in [
        "src/providers/claude_usage_probe.rs",
        "src/providers/claude_usage_report.rs",
        "src/providers/claude_usage_provider.rs",
    ] {
        let text = fs::read_to_string(manifest.join(file)).unwrap();
        for forbidden in [
            "println!",
            "eprintln!",
            "dbg!",
            "from_utf8",
            "to_string_lossy",
            "tracing::",
            "log::",
        ] {
            assert!(!text.contains(forbidden), "{file} contains {forbidden}");
        }
    }
}
