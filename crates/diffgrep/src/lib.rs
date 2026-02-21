//! diffgrep — filter a unified diff, keeping only hunks whose added or
//! removed lines match a regular expression.
//!
//! # Why this exists
//!
//! `git -c diff.external=pickaxe-diff show -S<pattern>` uses Git's external
//! diff driver protocol to show which hunks actually contain a given pattern.
//! The driver needs to filter a raw unified diff down to only the relevant
//! hunks — that is exactly what this library does.
//!
//! # What counts as a match
//!
//! Only **added** (`+`) and **removed** (`-`) content lines within a hunk are
//! tested against the pattern.  Context lines (` `) and the `--- a/file` /
//! `+++ b/file` file-header lines are ignored for matching purposes (the
//! file-header lines start with `---`/`+++` and appear before the first `@@`
//! header, so the parser never treats them as hunk content).
//!
//! # Output
//!
//! For each file that has at least one matching hunk, the function emits:
//! 1. The file's header lines (`diff --git …`, `index …`, `--- …`, `+++ …`).
//! 2. Each matching hunk (its `@@ … @@` header followed by its content lines).
//!
//! Files with no matching hunks are silently dropped.

use std::io::{self, BufRead, Write};

pub use regex::Regex;

// ── Public types ─────────────────────────────────────────────────────────────

/// A single hunk from a unified diff (after filtering).
#[derive(Debug, PartialEq)]
pub struct Hunk {
    /// The `@@ -l,s +l,s @@ optional-context` header line.
    pub header: String,
    /// Content lines: each starts with `+`, `-`, ` `, or `\`.
    pub lines: Vec<String>,
}

/// All matching hunks for a single file.
#[derive(Debug, PartialEq)]
pub struct FileDiff {
    /// The file header: `diff --git`, `index`, `---`, `+++`, and any mode
    /// lines (`new file mode`, `deleted file mode`, `old mode`, `new mode`).
    pub header: Vec<String>,
    /// Only the hunks where at least one `+`/`-` line matched the pattern.
    pub hunks: Vec<Hunk>,
}

// ── Core logic ────────────────────────────────────────────────────────────────

/// Returns `true` if any added (`+`) or removed (`-`) content line in `lines`
/// has content (after stripping the leading `+`/`-`) matching `regex`.
fn hunk_matches(lines: &[String], regex: &Regex) -> bool {
    lines.iter().any(|line| {
        let b = line.as_bytes().first().copied();
        (b == Some(b'+') || b == Some(b'-')) && regex.is_match(&line[1..])
    })
}

/// Parse a unified diff from `reader` and return only the [`FileDiff`]s that
/// contain at least one hunk matching `regex`.
///
/// Input lines are read lazily; each hunk is buffered until the next `@@` or
/// `diff` marker, then tested.  Only one file's header is held in memory at
/// a time, so memory usage is proportional to the size of the largest single
/// hunk/file-header rather than the whole diff.
pub fn filter_diff<R: BufRead>(reader: R, regex: &Regex) -> io::Result<Vec<FileDiff>> {
    let mut result: Vec<FileDiff> = Vec::new();

    let mut file_header: Vec<String> = Vec::new();
    let mut hunk_header = String::new();
    let mut hunk_lines: Vec<String> = Vec::new();
    let mut matching_hunks: Vec<Hunk> = Vec::new();
    let mut in_file = false;
    let mut in_hunk = false;

    // Flush the in-progress hunk into `matching_hunks` if it matches.
    macro_rules! flush_hunk {
        () => {
            if in_hunk {
                if hunk_matches(&hunk_lines, regex) {
                    matching_hunks.push(Hunk {
                        header: std::mem::take(&mut hunk_header),
                        lines:  std::mem::take(&mut hunk_lines),
                    });
                } else {
                    hunk_header.clear();
                    hunk_lines.clear();
                }
                #[allow(unused_assignments)]
                { in_hunk = false; }
            }
        };
    }

    // Flush the in-progress file into `result` if it has any matching hunks.
    macro_rules! flush_file {
        () => {
            if in_file {
                if !matching_hunks.is_empty() {
                    result.push(FileDiff {
                        header: std::mem::take(&mut file_header),
                        hunks:  std::mem::take(&mut matching_hunks),
                    });
                } else {
                    file_header.clear();
                    matching_hunks.clear();
                }
                #[allow(unused_assignments)]
                { in_file = false; }
            }
        };
    }

    for raw_line in reader.lines() {
        let line = raw_line?;

        if line.starts_with("diff ") {
            flush_hunk!();
            flush_file!();
            in_file = true;
            file_header.push(line);
        } else if line.starts_with("@@ ") {
            flush_hunk!();
            in_hunk = true;
            hunk_header = line;
        } else if in_hunk {
            hunk_lines.push(line);
        } else if in_file {
            // File-header continuation: index, ---, +++, mode lines, etc.
            file_header.push(line);
        }
        // Lines before the first `diff` are silently ignored.
    }

    flush_hunk!();
    flush_file!();

    Ok(result)
}

/// Write the filtered diff (result of [`filter_diff`]) as plain text to `writer`.
pub fn write_diff<W: Write>(diffs: &[FileDiff], writer: &mut W) -> io::Result<()> {
    for fd in diffs {
        for h in &fd.header {
            writeln!(writer, "{h}")?;
        }
        for hunk in &fd.hunks {
            writeln!(writer, "{}", hunk.header)?;
            for l in &hunk.lines {
                writeln!(writer, "{l}")?;
            }
        }
    }
    writer.flush()
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn run(input: &str, pattern: &str) -> Vec<FileDiff> {
        let regex = Regex::new(pattern).unwrap();
        filter_diff(Cursor::new(input), &regex).unwrap()
    }

    fn joined_output(input: &str, pattern: &str) -> String {
        let diffs = run(input, pattern);
        let mut out = Vec::new();
        write_diff(&diffs, &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    // ── Minimal diff fixture ───────────────────────────────────────────────

    fn single_file_diff(hunk_body: &str) -> String {
        format!(
            "diff --git a/foo.rs b/foo.rs\nindex abc..def 100644\n--- a/foo.rs\n+++ b/foo.rs\n@@ -1,3 +1,3 @@\n{hunk_body}"
        )
    }

    // ── Basic match / no-match ─────────────────────────────────────────────

    #[test]
    fn empty_input() {
        assert!(run("", "foo").is_empty());
    }

    #[test]
    fn added_line_matches() {
        let diff = single_file_diff(" ctx\n+needle\n-old\n");
        let out = joined_output(&diff, "needle");
        assert!(out.contains("+needle"), "expected +needle in output");
        assert!(out.contains("diff --git"), "expected file header");
        assert!(out.contains("@@ -1,3 +1,3 @@"), "expected hunk header");
    }

    #[test]
    fn removed_line_matches() {
        let diff = single_file_diff(" ctx\n+new\n-needle\n");
        let out = joined_output(&diff, "needle");
        assert!(out.contains("-needle"));
    }

    #[test]
    fn no_matching_lines_yields_empty_output() {
        let diff = single_file_diff(" ctx\n+added\n-removed\n");
        assert!(run(&diff, "needle").is_empty());
    }

    #[test]
    fn context_line_match_does_not_count() {
        // Pattern is present only in a context line, not in +/-
        let diff = single_file_diff(" needle_in_context\n+unrelated\n-unrelated\n");
        assert!(run(&diff, "needle").is_empty());
    }

    #[test]
    fn file_header_lines_not_matched() {
        // "needle" appears in the --- / +++ file header, NOT in hunk content
        let diff = format!(
            "diff --git a/needle.rs b/needle.rs\n\
             index abc..def 100644\n\
             --- a/needle.rs\n\
             +++ b/needle.rs\n\
             @@ -1,1 +1,1 @@\n\
             +unrelated\n\
             -unrelated\n"
        );
        assert!(run(&diff, "needle").is_empty(),
            "file header lines must not trigger a match");
    }

    // ── Multi-hunk filtering ───────────────────────────────────────────────

    #[test]
    fn only_matching_hunks_emitted() {
        let diff = format!(
            "diff --git a/foo.rs b/foo.rs\n\
             index abc..def 100644\n\
             --- a/foo.rs\n\
             +++ b/foo.rs\n\
             @@ -1,2 +1,2 @@ first\n\
             +needle here\n\
             -old\n\
             @@ -10,2 +10,2 @@ second\n\
             +unrelated\n\
             -unrelated\n\
             @@ -20,2 +20,2 @@ third\n\
             +another needle\n\
             -old\n"
        );
        let diffs = run(&diff, "needle");
        assert_eq!(diffs.len(), 1, "one file");
        assert_eq!(diffs[0].hunks.len(), 2, "two matching hunks");
        assert_eq!(diffs[0].hunks[0].header, "@@ -1,2 +1,2 @@ first");
        assert_eq!(diffs[0].hunks[1].header, "@@ -20,2 +20,2 @@ third");
    }

    #[test]
    fn file_with_no_matching_hunks_omitted() {
        let diff = format!(
            "diff --git a/match.rs b/match.rs\n\
             index 000..111 100644\n\
             --- a/match.rs\n\
             +++ b/match.rs\n\
             @@ -1,1 +1,1 @@\n\
             +needle\n\
             diff --git a/nomatch.rs b/nomatch.rs\n\
             index 222..333 100644\n\
             --- a/nomatch.rs\n\
             +++ b/nomatch.rs\n\
             @@ -1,1 +1,1 @@\n\
             +unrelated\n"
        );
        let diffs = run(&diff, "needle");
        assert_eq!(diffs.len(), 1, "only the matching file");
        assert!(diffs[0].header[0].contains("match.rs"));
    }

    #[test]
    fn multiple_files_all_match() {
        let diff = format!(
            "diff --git a/a.rs b/a.rs\nindex 0..1 100644\n--- a/a.rs\n+++ b/a.rs\n\
             @@ -1,1 +1,1 @@\n+needle\n\
             diff --git a/b.rs b/b.rs\nindex 2..3 100644\n--- a/b.rs\n+++ b/b.rs\n\
             @@ -1,1 +1,1 @@\n+needle too\n"
        );
        let diffs = run(&diff, "needle");
        assert_eq!(diffs.len(), 2);
    }

    // ── File-header content in output ──────────────────────────────────────

    #[test]
    fn file_header_included_in_output() {
        let diff = single_file_diff("+needle\n");
        let out = joined_output(&diff, "needle");
        assert!(out.contains("diff --git a/foo.rs b/foo.rs"));
        assert!(out.contains("index abc..def 100644"));
        assert!(out.contains("--- a/foo.rs"));
        assert!(out.contains("+++ b/foo.rs"));
    }

    #[test]
    fn file_header_not_emitted_without_match() {
        let diff = single_file_diff(" ctx\n+added\n");
        let out = joined_output(&diff, "needle");
        assert!(!out.contains("diff --git"), "header must not appear");
    }

    // ── Regex features ─────────────────────────────────────────────────────

    #[test]
    fn regex_is_not_literal() {
        // Make sure we use full regex matching, not a substring literal
        let diff = single_file_diff("+fn foo_bar()\n");
        assert!(!run(&diff, "foo.bar").is_empty(), "regex dot should match underscore");
        assert!(!run(&diff, "foo_bar").is_empty(), "literal also matches");
    }

    #[test]
    fn regex_anchored_to_content() {
        // Pattern anchored at start of content (after the + prefix)
        let diff = single_file_diff("+hello world\n");
        assert!(!run(&diff, "^hello").is_empty(), "anchored match");
        assert!(run(&diff, "^world").is_empty(), "wrong anchor should not match");
    }
}
