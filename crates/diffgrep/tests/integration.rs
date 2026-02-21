//! Integration tests for diffgrep — exercise the compiled binary and the
//! `filter_diff` library against real `git diff` output.
//!
//! The binary tests pipe crafted unified-diff text directly; no git
//! installation is required for those.  The `with_real_git` test creates a
//! temporary repository, commits a change, and pipes the resulting `git diff`
//! through the diffgrep binary — it requires git in PATH and is skipped if
//! git is unavailable.

use std::io::Write;
use std::process::{Command, Stdio};

fn diffgrep_bin() -> &'static str {
    env!("CARGO_BIN_EXE_diffgrep")
}

/// Run the diffgrep binary with `input` on stdin and `pattern` as the sole
/// argument.  Returns `(stdout_text, exit_success)`.
fn run(input: &[u8], pattern: &str) -> (String, bool) {
    let mut child = Command::new(diffgrep_bin())
        .arg(pattern)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("failed to spawn diffgrep");
    child.stdin.take().unwrap().write_all(input).unwrap();
    let out = child.wait_with_output().unwrap();
    (
        String::from_utf8_lossy(&out.stdout).into_owned(),
        out.status.success(),
    )
}

fn has_git() -> bool {
    Command::new("git")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn temp_dir(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("siefe_diffgrep_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

// ── Binary end-to-end tests (no external tools) ───────────────────────────────

#[test]
fn binary_matching_hunk_included() {
    // Two hunks: one with "needle", one without.  Only the matching hunk
    // should appear in the output; exit code should be 0.
    let diff = b"\
diff --git a/foo.rs b/foo.rs\n\
index abc..def 100644\n\
--- a/foo.rs\n\
+++ b/foo.rs\n\
@@ -1,2 +1,3 @@ first\n\
 context\n\
+added needle line\n\
+other added line\n\
@@ -10,1 +11,1 @@ second\n\
+unrelated addition\n";

    let (out, found) = run(diff, "needle");
    assert!(found, "exit 0 when match found");
    assert!(out.contains("+added needle line"), "matching hunk in output");
    assert!(!out.contains("+unrelated addition"), "non-matching hunk excluded");
}

#[test]
fn binary_no_match_exits_nonzero() {
    let diff = b"\
diff --git a/foo.rs b/foo.rs\n\
index abc..def 100644\n\
--- a/foo.rs\n\
+++ b/foo.rs\n\
@@ -1,1 +1,1 @@\n\
+unrelated\n";

    let (out, found) = run(diff, "NOTFOUND");
    assert!(!found, "exit non-zero when no match");
    assert!(out.is_empty(), "no output when no match");
}

#[test]
fn binary_no_args_exits_with_code_2() {
    let status = Command::new(diffgrep_bin())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap();
    assert!(!status.success());
    assert_eq!(status.code(), Some(2));
}

#[test]
fn binary_context_line_does_not_match() {
    // "needle" appears only in a context line — must not be counted as a match.
    let diff = b"\
diff --git a/foo.rs b/foo.rs\n\
index abc..def 100644\n\
--- a/foo.rs\n\
+++ b/foo.rs\n\
@@ -1,2 +1,2 @@\n\
 needle in context\n\
+unrelated\n";

    let (_, found) = run(diff, "needle");
    assert!(!found, "context-only match should not count");
}

// ── Integration test with a real git repository ───────────────────────────────

#[test]
fn with_real_git() {
    if !has_git() {
        eprintln!("SKIP with_real_git: git not found");
        return;
    }

    let dir = temp_dir("git");

    // Initialise repo
    Command::new("git")
        .args(["init", "-q"])
        .current_dir(&dir)
        .output()
        .unwrap();

    // First commit (empty, to establish HEAD)
    Command::new("git")
        .args([
            "-c", "user.email=test@test.com",
            "-c", "user.name=Test",
            "commit", "--allow-empty", "-m", "init",
        ])
        .current_dir(&dir)
        .output()
        .unwrap();

    // Commit a source file
    std::fs::write(dir.join("foo.rs"), b"fn original() {}\n").unwrap();
    Command::new("git")
        .args(["add", "."])
        .current_dir(&dir)
        .output()
        .unwrap();
    Command::new("git")
        .args([
            "-c", "user.email=test@test.com",
            "-c", "user.name=Test",
            "commit", "-m", "add foo",
        ])
        .current_dir(&dir)
        .output()
        .unwrap();

    // Modify the file: add a "needle" line and an "unrelated" line
    std::fs::write(
        dir.join("foo.rs"),
        b"fn original() {}\nfn needle_fn() {}\nfn unrelated() {}\n",
    )
    .unwrap();

    // Get the unstaged diff
    let diff_out = Command::new("git")
        .args(["diff"])
        .current_dir(&dir)
        .output()
        .unwrap()
        .stdout;

    assert!(!diff_out.is_empty(), "git diff should produce output");

    // Filter through diffgrep
    let (out, found) = run(&diff_out, "needle_fn");
    assert!(found, "should find needle_fn in diff");
    assert!(out.contains("+fn needle_fn()"), "output should contain the added needle line");
    // The unrelated function is in the same hunk, so it will also appear —
    // but the file header must be present
    assert!(out.contains("diff --git"), "file header must be present");

    let _ = std::fs::remove_dir_all(&dir);
}
