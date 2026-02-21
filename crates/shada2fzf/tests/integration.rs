//! Integration tests for shada2fzf — exercise the compiled binary against
//! crafted shada byte sequences written to temporary files.
//!
//! The shada binary format is documented in `src/main.rs`.  The test fixtures
//! are hand-crafted from the msgpack encoding spec and match the identical
//! byte sequences tested by the unit tests inside `src/main.rs`, giving full
//! end-to-end coverage through the binary's argument-parsing and file I/O
//! in addition to the core msgpack decoder.

use std::process::Command;

fn shada2fzf_bin() -> &'static str {
    env!("CARGO_BIN_EXE_shada2fzf")
}

/// Write `data` to a unique temp file and run the shada2fzf binary on it.
/// Returns `(stdout_text, exit_success)`.
fn run(data: &[u8], suffix: &str) -> (String, bool) {
    let path = std::env::temp_dir().join(format!("siefe_shada2fzf_{suffix}.shada"));
    std::fs::write(&path, data).expect("could not write temp shada file");

    let out = Command::new(shada2fzf_bin())
        .arg(&path)
        .output()
        .expect("failed to run shada2fzf");

    (
        String::from_utf8_lossy(&out.stdout).into_owned(),
        out.status.success(),
    )
}

// ── Shared fixture bytes ──────────────────────────────────────────────────────
//
// Record A: type=11, ts=100, data = fixmap4{f:"a.lua", n:34, l:10, c:2}
//
//   0x0b          type 11 (kSDItemLocalMark)
//   0x64          timestamp 100 (fixint)
//   0x12          data length 18 (fixint)
//   0x84          fixmap with 4 key-value pairs
//   0xa1 0x66     key "f"  (fixstr len 1, byte 'f')
//   0xa5 ...      value "a.lua" (fixstr len 5)
//   0xa1 0x6e     key "n"  (fixstr len 1, byte 'n')
//   0x22          value 34 = '"' (fixint)
//   0xa1 0x6c     key "l"  (fixstr len 1, byte 'l')
//   0x0a          value 10 (fixint)
//   0xa1 0x63     key "c"  (fixstr len 1, byte 'c')
//   0x02          value 2  (fixint)

const A_RECORD: &[u8] = &[
    0x0b, 0x64, 0x12,
    0x84,
    0xa1, 0x66, 0xa5, 0x61, 0x2e, 0x6c, 0x75, 0x61,  // "f" → "a.lua"
    0xa1, 0x6e, 0x22,                                  // "n" → 34
    0xa1, 0x6c, 0x0a,                                  // "l" → 10
    0xa1, 0x63, 0x02,                                  // "c" → 2
];

// Record B: type=11, ts=200, data = fixmap4{f:"b.lua", n:34, l:5, c:1}
// ts=200 requires uint8 encoding: 0xcc 0xc8
const B_RECORD: &[u8] = &[
    0x0b, 0xcc, 0xc8, 0x12,
    0x84,
    0xa1, 0x66, 0xa5, 0x62, 0x2e, 0x6c, 0x75, 0x61,  // "f" → "b.lua"
    0xa1, 0x6e, 0x22,                                  // "n" → 34
    0xa1, 0x6c, 0x05,                                  // "l" → 5
    0xa1, 0x63, 0x01,                                  // "c" → 1
];

// ── Tests ─────────────────────────────────────────────────────────────────────

#[test]
fn binary_single_record() {
    let (out, ok) = run(A_RECORD, "single");
    assert!(ok, "exit 0 for valid shada");
    assert_eq!(out, "10//2//a.lua\n");
}

#[test]
fn binary_empty_shada() {
    let (out, ok) = run(&[], "empty");
    assert!(ok, "exit 0 for empty shada");
    assert!(out.is_empty(), "empty shada → empty output");
}

#[test]
fn binary_mru_ordering() {
    // A_RECORD ts=100, B_RECORD ts=200 → b.lua must appear first (most recent)
    let mut data = A_RECORD.to_vec();
    data.extend_from_slice(B_RECORD);

    let (out, ok) = run(&data, "mru");
    assert!(ok, "exit 0");

    let lines: Vec<&str> = out.lines().collect();
    assert_eq!(lines.len(), 2, "two entries");
    assert!(lines[0].ends_with("b.lua"), "b.lua (ts=200) first; got {:?}", lines[0]);
    assert!(lines[1].ends_with("a.lua"), "a.lua (ts=100) second; got {:?}", lines[1]);
}

#[test]
fn binary_no_args_exits_nonzero() {
    let status = Command::new(shada2fzf_bin())
        .status()
        .expect("failed to run shada2fzf");
    assert!(!status.success(), "exit non-zero when no arguments given");
}
