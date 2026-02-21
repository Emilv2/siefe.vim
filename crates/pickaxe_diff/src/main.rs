//! pickaxe-diff — Git external diff driver for pickaxe (`-S`/`-G`) searches.
//!
//! Git calls this binary with 7 positional arguments whenever it would
//! normally run its internal diff, but `diff.external` is set to this path:
//!
//!   pickaxe-diff path old_file old_hex old_mode new_file new_hex new_mode
//!
//! The search pattern is read from the environment variable `GREPDIFF_REGEX`,
//! which must be set by the caller (typically the siefe.vim git log preview
//! command).  If the variable is absent or empty, all hunks are shown.
//!
//! # What it does
//! 1. Runs `git diff --no-color --no-ext-diff -p --src-prefix=a/ --dst-prefix=b/
//!    -- old_file new_file` to obtain the raw unified diff.
//! 2. Feeds the diff through the `diffgrep` library to keep only hunks where
//!    at least one added/removed line matches `GREPDIFF_REGEX`.
//! 3. Applies ANSI colours (from `git config --get-color`) and highlights
//!    pattern matches within content lines with reverse-video.
//! 4. Emits the formatted diff to stdout, prefixed by the standard
//!    `diff --git … / index … / --- … / +++ …` meta-header.

use std::io::{self, BufReader, Cursor, Write};
use std::process::{self, Command, Stdio};

use diffgrep::{filter_diff, Regex};

// ── Git colour helpers ────────────────────────────────────────────────────────

struct Colors {
    frag:  String, // @@ header
    func:  String, // context after @@ (function name)
    meta:  String, // diff/index/---/+++ header lines
    new:   String, // added lines (+)
    old:   String, // removed lines (-)
    reset: String,
}

impl Colors {
    fn from_git() -> Self {
        Colors {
            frag:  git_color("color.diff.frag",  "cyan"),
            func:  git_color("color.diff.func",  ""),
            meta:  git_color("color.diff.meta",  "normal bold"),
            new:   git_color("color.diff.new",   "green"),
            old:   git_color("color.diff.old",   "red"),
            reset: "\x1b[m".to_owned(),
        }
    }
}

/// Call `git config --get-color <name> <default>` and return the raw ANSI
/// escape bytes.  Falls back to an empty string if git is unavailable.
fn git_color(name: &str, default: &str) -> String {
    Command::new("git")
        .args(["config", "--get-color", name, default])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .unwrap_or_default()
}

// ── Output formatting ─────────────────────────────────────────────────────────

/// Emit a meta-header line (bold).
fn emit_meta(line: &str, colors: &Colors, out: &mut impl Write) -> io::Result<()> {
    writeln!(out, "{}{}{}", colors.meta, line, colors.reset)
}

/// Colour and highlight one hunk-header line (`@@ … @@ context`).
fn format_hunk_header(line: &str, colors: &Colors) -> String {
    // The line is:  @@ -l,s +l,s @@ optional-context
    //               ^^ opening    ^^ closing
    // We slice off the opening "@@" (2 chars) and search the rest for the
    // closing "@@".  The exclusive end in the original string is:
    //   rel (position within line[2..]) + 2 (slice offset) + 2 (closing @@)
    //   = rel + 4
    if let Some(rel) = line[2..].find("@@") {
        let end = rel + 2 + 2; // == rel + 4; see comment above
        let frag = &line[..end];
        let func = &line[end..];
        format!(
            "{}{}{}{}{}{}",
            colors.frag, frag, colors.reset, colors.func, func, colors.reset
        )
    } else {
        format!("{}{}{}", colors.frag, line, colors.reset)
    }
}

/// Highlight all occurrences of `regex` within `text` using reverse-video.
fn highlight_matches(text: &str, regex: &Regex) -> String {
    let mut result = String::with_capacity(text.len() + 32);
    let mut last = 0;
    for m in regex.find_iter(text) {
        result.push_str(&text[last..m.start()]);
        result.push_str("\x1b[7m");  // reverse video on
        result.push_str(m.as_str());
        result.push_str("\x1b[27m"); // reverse video off
        last = m.end();
    }
    result.push_str(&text[last..]);
    result
}

/// Colour one content line (`+`, `-`, or context) and highlight matches in
/// the `+`/`-` content.
fn format_content_line(line: &str, regex: &Regex, colors: &Colors) -> String {
    let first = line.as_bytes().first().copied();
    match first {
        Some(b'+') => {
            let highlighted = highlight_matches(&line[1..], regex);
            format!("{}+{}{}", colors.new, highlighted, colors.reset)
        }
        Some(b'-') => {
            let highlighted = highlight_matches(&line[1..], regex);
            format!("{}-{}{}", colors.old, highlighted, colors.reset)
        }
        _ => line.to_owned(),
    }
}

/// Write the filtered and coloured diff to `out`, preceded by the standard
/// `diff --git … / index … / --- / +++` meta-header constructed from the
/// git diff-driver arguments.
fn emit_output(
    path: &str,
    old_file: &str,
    old_hex: &str,
    old_mode: &str,
    new_file: &str,
    new_hex: &str,
    new_mode: &str,
    regex: &Regex,
    diff_text: &str,
    colors: &Colors,
    out: &mut impl Write,
) -> io::Result<()> {
    const NULL: &str = "/dev/null";
    const ZERO_OID: &str = "0000000";

    let mut old_path = format!("a/{path}");
    let mut new_path = format!("b/{path}");
    let mut old_hex_out = old_hex;
    let mut new_hex_out = new_hex;
    let same_mode;

    emit_meta(&format!("diff --git {old_path} {new_path}"), colors, out)?;

    if old_file == NULL {
        old_path = NULL.to_owned();
        old_hex_out = ZERO_OID;
        emit_meta(&format!("new file mode {new_mode}"), colors, out)?;
        same_mode = "";
    } else if new_file == NULL {
        new_path = NULL.to_owned();
        new_hex_out = ZERO_OID;
        emit_meta(&format!("deleted file mode {old_mode}"), colors, out)?;
        same_mode = "";
    } else if old_mode != new_mode {
        emit_meta(&format!("old mode {old_mode}"), colors, out)?;
        emit_meta(&format!("new mode {new_mode}"), colors, out)?;
        same_mode = "";
    } else {
        same_mode = old_mode;
    }

    let mode_suffix = if same_mode.is_empty() {
        String::new()
    } else {
        format!(" {same_mode}")
    };
    emit_meta(
        &format!("index {old_hex_out}..{new_hex_out}{mode_suffix}"),
        colors,
        out,
    )?;
    emit_meta(&format!("--- {old_path}"), colors, out)?;
    emit_meta(&format!("+++ {new_path}"), colors, out)?;

    // Parse and filter the raw diff
    let reader = BufReader::new(Cursor::new(diff_text.as_bytes()));
    let diffs = filter_diff(reader, regex).map_err(io::Error::other)?;

    for fd in &diffs {
        // Skip the file header lines — we already emitted our own above
        for hunk in &fd.hunks {
            writeln!(out, "{}", format_hunk_header(&hunk.header, colors))?;
            for line in &hunk.lines {
                writeln!(out, "{}", format_content_line(line, regex, colors))?;
            }
        }
    }

    out.flush()
}

// ── Entry point ───────────────────────────────────────────────────────────────

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() != 7 {
        eprintln!(
            "usage: pickaxe-diff path old_file old_hex old_mode new_file new_hex new_mode"
        );
        process::exit(1);
    }

    let (path, old_file, old_hex, old_mode, new_file, new_hex, new_mode) = (
        &args[0], &args[1], &args[2], &args[3], &args[4], &args[5], &args[6],
    );

    // Pattern comes from the environment (set by siefe.vim's git log preview).
    let pattern = std::env::var("GREPDIFF_REGEX").unwrap_or_default();
    // Empty pattern → match everything (show all hunks)
    let effective = if pattern.is_empty() { "." } else { &pattern };
    let regex = Regex::new(effective).unwrap_or_else(|e| {
        eprintln!("pickaxe-diff: invalid GREPDIFF_REGEX {effective:?}: {e}");
        process::exit(1);
    });

    // Run git diff to get the raw unified diff between the two file versions
    let output = Command::new("git")
        .args([
            "diff",
            "--no-color",
            "--no-ext-diff",
            "-p",
            "--src-prefix=a/",
            "--dst-prefix=b/",
            "--",
            old_file,
            new_file,
        ])
        .stderr(Stdio::inherit())
        .output()
        .unwrap_or_else(|e| {
            eprintln!("pickaxe-diff: failed to run git diff: {e}");
            process::exit(1);
        });

    let diff_text = String::from_utf8_lossy(&output.stdout);
    let colors = Colors::from_git();

    let stdout = io::stdout();
    emit_output(
        path, old_file, old_hex, old_mode, new_file, new_hex, new_mode,
        &regex, &diff_text, &colors, &mut stdout.lock(),
    )
    .unwrap_or_else(|e| {
        eprintln!("pickaxe-diff: write error: {e}");
        process::exit(1);
    });
}
