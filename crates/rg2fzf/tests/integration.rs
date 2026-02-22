//! Integration tests for rg2fzf — exercise the compiled binary end-to-end.
//!
//! These tests pipe bytes directly to the rg2fzf binary (simulating what
//! `rg --null` would produce) and verify that the binary's stdout matches
//! the expected NUL-terminated SOH-separated records.  No `rg` installation
//! is needed; the input is crafted to match rg's wire format exactly.
//! A separate test exercises the full `rg | rg2fzf` pipeline when `rg` is
//! available, and skips gracefully when it is not.

use std::io::Write;
use std::process::{Command, Stdio};

fn rg2fzf_bin() -> &'static str {
    env!("CARGO_BIN_EXE_rg2fzf")
}

/// Run the rg2fzf binary with `input` on stdin; return stdout bytes.
fn run(input: &[u8]) -> Vec<u8> {
    let mut child = Command::new(rg2fzf_bin())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("failed to spawn rg2fzf");
    child.stdin.take().unwrap().write_all(input).unwrap();
    child.wait_with_output().unwrap().stdout
}

fn has_rg() -> bool {
    Command::new("rg")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn temp_dir(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("siefe_rg2fzf_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

// ── Binary end-to-end tests ───────────────────────────────────────────────────

#[test]
fn binary_basic_record() {
    assert_eq!(
        run(b"file.lua\x001:5:hello world\n"),
        b"file.lua\x011:5:hello world\0"
    );
}

#[test]
fn binary_empty_input() {
    assert!(run(b"").is_empty());
}

#[test]
fn binary_multiple_records() {
    assert_eq!(
        run(b"a.lua\x001:1:foo\nb.lua\x002:3:bar\n"),
        b"a.lua\x011:1:foo\0b.lua\x012:3:bar\0"
    );
}

#[test]
fn binary_no_nul_passthrough() {
    // Lines without NUL (e.g. logger wrapper output) pass through unchanged
    // except for the terminator change (\n → \0).
    assert_eq!(run(b"log line without nul\n"), b"log line without nul\0");
}

#[test]
fn binary_colon_in_filename_and_text() {
    // SOH separates filename from rest regardless of colons in either part.
    assert_eq!(
        run(b"server:8080/api.go\x001:1:http://host:9090/\n"),
        b"server:8080/api.go\x011:1:http://host:9090/\0"
    );
}

#[test]
fn binary_ansi_in_filename() {
    // ANSI escape codes produced by rg --color=always wrap the filename.
    // The NUL separator is still at a fixed position (after any ANSI reset),
    // and the translation must preserve the ANSI bytes unchanged.
    let input = b"\x1b[32mfile.lua\x1b[0m\x001:1:text\n";
    let out = run(input);
    assert_eq!(
        out, b"\x1b[32mfile.lua\x1b[0m\x011:1:text\0",
        "ANSI codes round-trip; SOH replaces NUL"
    );
}

// ── Pipeline test with real rg (skipped if rg is unavailable) ────────────────

#[test]
fn pipeline_with_real_rg() {
    if !has_rg() {
        eprintln!("SKIP pipeline_with_real_rg: rg not found");
        return;
    }

    let dir = temp_dir("pipeline");
    let file = dir.join("test.rs");
    std::fs::write(&file, b"fn needle() {}\nfn other() {}\n").unwrap();

    // Run rg --null on the temp file
    let rg_out = Command::new("rg")
        .args([
            "--null",
            "--column",
            "--line-number",
            "--no-heading",
            "--with-filename",
            "--",
            "needle",
            file.to_str().unwrap(),
        ])
        .output()
        .expect("rg failed");

    assert!(!rg_out.stdout.is_empty(), "rg should find needle");

    // Pipe rg output through rg2fzf
    let out = run(&rg_out.stdout);
    let s = String::from_utf8_lossy(&out);

    // Every record should have exactly one SOH (filename/rest boundary)
    assert!(s.contains('\x01'), "output should contain SOH separator");
    assert!(s.contains("needle"), "output should contain match text");
    // Every record ends with NUL
    assert!(out.ends_with(b"\0"), "stream should end with NUL");

    let _ = std::fs::remove_dir_all(&dir);
}
