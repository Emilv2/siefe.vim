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

use diffgrep::{filter_diff, Match, Regex};

// ── Git colour helpers ────────────────────────────────────────────────────────

struct Colors {
    frag: String, // @@ header
    func: String, // context after @@ (function name)
    meta: String, // diff/index/---/+++ header lines
    new: String,  // added lines (+)
    old: String,  // removed lines (-)
    reset: String,
}

impl Colors {
    fn from_git() -> Self {
        Colors {
            frag: git_color("color.diff.frag", "cyan"),
            func: git_color("color.diff.func", ""),
            meta: git_color("color.diff.meta", "normal bold"),
            new: git_color("color.diff.new", "green"),
            old: git_color("color.diff.old", "red"),
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
        result.push_str("\x1b[7m"); // reverse video on
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
#[allow(clippy::too_many_arguments)]
fn emit_output(
    path: &str,
    old_file: &str,
    old_hex: &str,
    old_mode: &str,
    new_file: &str,
    new_hex: &str,
    new_mode: &str,
    match_pattern: &diffgrep::Match,
    highlight_regex: &Regex,
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
    let diffs = filter_diff(reader, match_pattern).map_err(io::Error::other)?;

    for fd in &diffs {
        // Skip the file header lines — we already emitted our own above
        for hunk in &fd.hunks {
            writeln!(out, "{}", format_hunk_header(&hunk.header, colors))?;
            for line in &hunk.lines {
                writeln!(
                    out,
                    "{}",
                    format_content_line(line, highlight_regex, colors)
                )?;
            }
        }
    }

    out.flush()
}

// ── Unit tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// A `Colors` value with all fields empty — makes assertions simple because
    /// no ANSI bytes appear in the expected strings.
    fn no_colors() -> Colors {
        Colors {
            frag: String::new(),
            func: String::new(),
            meta: String::new(),
            new: String::new(),
            old: String::new(),
            reset: String::new(),
        }
    }

    // ── format_hunk_header ────────────────────────────────────────────────────

    #[test]
    fn hunk_header_with_func_context() {
        // With empty colors the output equals the input unchanged.
        let r = format_hunk_header("@@ -1,3 +1,3 @@ fn main()", &no_colors());
        assert_eq!(r, "@@ -1,3 +1,3 @@ fn main()");
    }

    #[test]
    fn hunk_header_without_func_context() {
        let r = format_hunk_header("@@ -1,3 +1,3 @@", &no_colors());
        assert_eq!(r, "@@ -1,3 +1,3 @@");
    }

    #[test]
    fn hunk_header_applies_colors() {
        let c = Colors {
            frag: "\x1b[36m".to_owned(),
            func: "\x1b[90m".to_owned(),
            meta: String::new(),
            new: String::new(),
            old: String::new(),
            reset: "\x1b[m".to_owned(),
        };
        let r = format_hunk_header("@@ -1,1 +1,1 @@ fn foo()", &c);
        assert!(
            r.contains("\x1b[36m@@ -1,1 +1,1 @@\x1b[m"),
            "frag should be colored"
        );
        assert!(
            r.contains("\x1b[90m fn foo()\x1b[m"),
            "func should be colored"
        );
    }

    // ── highlight_matches ─────────────────────────────────────────────────────

    #[test]
    fn highlight_no_match_unchanged() {
        let re = Regex::new("needle").unwrap();
        assert_eq!(highlight_matches("no match here", &re), "no match here");
    }

    #[test]
    fn highlight_single_match() {
        let re = Regex::new("needle").unwrap();
        assert_eq!(
            highlight_matches("before needle after", &re),
            "before \x1b[7mneedle\x1b[27m after"
        );
    }

    #[test]
    fn highlight_multiple_matches() {
        let re = Regex::new("x").unwrap();
        assert_eq!(
            highlight_matches("axbxc", &re),
            "a\x1b[7mx\x1b[27mb\x1b[7mx\x1b[27mc"
        );
    }

    // ── format_content_line ───────────────────────────────────────────────────

    #[test]
    fn content_line_added_highlighted() {
        // With empty colors: result is "+" prefix + highlighted content
        let re = Regex::new("foo").unwrap();
        let r = format_content_line("+added foo line", &re, &no_colors());
        assert_eq!(r, "+added \x1b[7mfoo\x1b[27m line");
    }

    #[test]
    fn content_line_removed_highlighted() {
        let re = Regex::new("bar").unwrap();
        let r = format_content_line("-removed bar line", &re, &no_colors());
        assert_eq!(r, "-removed \x1b[7mbar\x1b[27m line");
    }

    #[test]
    fn content_line_context_unchanged() {
        // Context lines (space prefix) are not coloured or highlighted.
        let re = Regex::new("context").unwrap();
        let r = format_content_line(" context line", &re, &no_colors());
        assert_eq!(r, " context line");
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    // Handle --version / -V before checking argument count
    if args.iter().any(|a| a == "--version" || a == "-V") {
        const VERSION: &str = concat!(
            env!("CARGO_PKG_NAME"),
            " ",
            env!("CARGO_PKG_VERSION"),
            " (git:",
            env!("SIEFE_GIT_HASH", "unknown"),
            ")"
        );
        println!("{VERSION}");
        return;
    }

    if args.len() != 7 {
        eprintln!("usage: pickaxe-diff path old_file old_hex old_mode new_file new_hex new_mode");
        process::exit(1);
    }

    let (path, old_file, old_hex, old_mode, new_file, new_hex, new_mode) = (
        &args[0], &args[1], &args[2], &args[3], &args[4], &args[5], &args[6],
    );

    // Pattern comes from the environment (set by siefe.vim's git log preview).
    let pattern = std::env::var("GREPDIFF_REGEX").unwrap_or_default();
    // Empty pattern → match everything (show all hunks)
    let effective = if pattern.is_empty() { "." } else { &pattern };

    // Mode comes from GREPDIFF_MODE: "S" for pickaxe literal (-S), anything
    // else (including unset) uses regex (-G) semantics.
    let is_s_mode = std::env::var("GREPDIFF_MODE")
        .map(|m| m == "S")
        .unwrap_or(false);

    // Build the Match pattern.  For -S mode we use literal counting; for
    // highlighting in -S mode we escape the literal to a regex.
    let (match_pattern, highlight_regex) = if is_s_mode {
        let escaped = regex::escape(effective);
        let re = Regex::new(&escaped).unwrap_or_else(|_| {
            // Fallback: never-matching regex (should not happen after escape)
            Regex::new("$^").unwrap()
        });
        (Match::Literal(effective.to_owned()), re)
    } else {
        let re = Regex::new(effective).unwrap_or_else(|e| {
            eprintln!("pickaxe-diff: invalid GREPDIFF_REGEX {effective:?}: {e}");
            process::exit(1);
        });
        let re2 = re.clone();
        (Match::Regex(re), re2)
    };

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
        path,
        old_file,
        old_hex,
        old_mode,
        new_file,
        new_hex,
        new_mode,
        &match_pattern,
        &highlight_regex,
        &diff_text,
        &colors,
        &mut stdout.lock(),
    )
    .unwrap_or_else(|e| {
        eprintln!("pickaxe-diff: write error: {e}");
        process::exit(1);
    });
}
