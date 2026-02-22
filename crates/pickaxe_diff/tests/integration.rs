//! Integration tests for pickaxe-diff — exercise the compiled binary end-to-end.
//!
//! pickaxe-diff is a Git external diff driver.  Git calls it with 7 positional
//! arguments:
//!
//!   pickaxe-diff path old_file old_hex old_mode new_file new_hex new_mode
//!
//! where `old_file` and `new_file` are real paths on disk.  The binary runs
//! `git diff -- old_file new_file` internally to obtain the raw diff and then
//! applies the `diffgrep` filter and ANSI colouring.
//!
//! The `GREPDIFF_REGEX` environment variable sets the filter pattern.  When
//! unset or empty, the effective pattern is `"."` (match everything).
//!
//! Tests that require `git` in PATH skip gracefully when git is unavailable.

use std::process::{Command, Stdio};

fn pickaxe_diff_bin() -> &'static str {
    env!("CARGO_BIN_EXE_pickaxe-diff")
}

fn has_git() -> bool {
    Command::new("git")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn temp_dir(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("siefe_pickaxe_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

// ── Argument-count guard ──────────────────────────────────────────────────────

#[test]
fn binary_wrong_arg_count_exits_1() {
    // With no args, should exit 1 and print usage.
    let status = Command::new(pickaxe_diff_bin())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap();
    assert!(!status.success());
    assert_eq!(status.code(), Some(1), "exit code 1 with no args");

    // With 3 args (need exactly 7), should also exit 1.
    let status2 = Command::new(pickaxe_diff_bin())
        .args(["path", "old", "hex"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap();
    assert!(!status2.success());
    assert_eq!(status2.code(), Some(1), "exit code 1 with wrong arg count");
}

// ── Tests with real git files (skipped if git unavailable) ───────────────────

#[test]
fn binary_matching_pattern_shows_hunks() {
    if !has_git() {
        eprintln!("SKIP binary_matching_pattern_shows_hunks: git not found");
        return;
    }

    let dir = temp_dir("match");
    let old_path = dir.join("old.rs");
    let new_path = dir.join("new.rs");

    std::fs::write(&old_path, b"fn original() {}\n").unwrap();
    std::fs::write(
        &new_path,
        b"fn original() {}\nfn needle_fn() {}\nfn unrelated() {}\n",
    )
    .unwrap();

    let out = Command::new(pickaxe_diff_bin())
        .args([
            "src/foo.rs",
            old_path.to_str().unwrap(),
            "abc1234",
            "100644",
            new_path.to_str().unwrap(),
            "def5678",
            "100644",
        ])
        .env("GREPDIFF_REGEX", "needle")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .expect("failed to run pickaxe-diff");

    let text = String::from_utf8_lossy(&out.stdout);
    assert!(out.status.success(), "pickaxe-diff should exit 0");
    // Meta-header is always emitted
    assert!(text.contains("diff --git"),  "meta header present");
    assert!(text.contains("src/foo.rs"),  "logical path in header");
    assert!(text.contains("---"),         "--- line present");
    assert!(text.contains("+++"),         "++ line present");
    // Hunk header must be present (needle_fn was added).
    // Note: pattern matches are highlighted with reverse-video, so "needle_fn"
    // may appear split as "\x1b[7mneedle\x1b[27m_fn" — check for "@@" and
    // the pattern text separately.
    assert!(text.contains("@@"),          "hunk header present");
    assert!(text.contains("needle"),      "needle pattern text in hunk");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn binary_no_pattern_match_shows_no_hunks() {
    if !has_git() {
        eprintln!("SKIP binary_no_pattern_match_shows_no_hunks: git not found");
        return;
    }

    let dir = temp_dir("nomatch");
    let old_path = dir.join("old.rs");
    let new_path = dir.join("new.rs");

    std::fs::write(&old_path, b"fn original() {}\n").unwrap();
    std::fs::write(&new_path, b"fn original() {}\nfn unrelated() {}\n").unwrap();

    let out = Command::new(pickaxe_diff_bin())
        .args([
            "src/foo.rs",
            old_path.to_str().unwrap(),
            "abc1234",
            "100644",
            new_path.to_str().unwrap(),
            "def5678",
            "100644",
        ])
        .env("GREPDIFF_REGEX", "NOTFOUND")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .expect("failed to run pickaxe-diff");

    let text = String::from_utf8_lossy(&out.stdout);
    // Meta-header is always emitted even when no hunk matches
    assert!(text.contains("diff --git"), "meta header always emitted");
    // No hunk headers should be present
    assert!(!text.contains("@@"), "no hunk when pattern does not match");
}

#[test]
fn binary_empty_regex_env_shows_all_hunks() {
    if !has_git() {
        eprintln!("SKIP binary_empty_regex_env_shows_all_hunks: git not found");
        return;
    }

    let dir = temp_dir("emptyregex");
    let old_path = dir.join("old.rs");
    let new_path = dir.join("new.rs");

    std::fs::write(&old_path, b"fn original() {}\n").unwrap();
    std::fs::write(&new_path, b"fn original() {}\nfn added() {}\n").unwrap();

    // Empty GREPDIFF_REGEX → effective pattern "." → all hunks shown
    let out = Command::new(pickaxe_diff_bin())
        .args([
            "src/foo.rs",
            old_path.to_str().unwrap(),
            "abc1234",
            "100644",
            new_path.to_str().unwrap(),
            "def5678",
            "100644",
        ])
        .env("GREPDIFF_REGEX", "")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .expect("failed to run pickaxe-diff");

    let text = String::from_utf8_lossy(&out.stdout);
    // Empty GREPDIFF_REGEX uses effective pattern "." which matches every
    // character.  highlight_matches wraps each char individually, so the
    // plain text "added" won't appear literally.  Just check the hunk header
    // is present — that confirms all-hunks-shown behaviour.
    assert!(text.contains("@@"), "hunk present when pattern matches everything");

    let _ = std::fs::remove_dir_all(&dir);
}
