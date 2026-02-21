//! diffgrep — filter a unified diff to hunks whose +/- lines match a pattern.
//!
//! Usage:
//!   git show <commit> | diffgrep <pattern>
//!   git diff HEAD~1   | diffgrep <pattern>
//!
//! The pattern is a regular expression (Rust `regex` crate syntax).
//! Only added (+) and removed (-) content lines are tested; context lines and
//! file-header lines (--- / +++) are ignored for matching purposes.
//!
//! Output is a plain unified diff containing only the matching file/hunk pairs.
//! Exit code 0 if any matches were found, 1 if none.

use std::io::{self, BufReader};
use std::process;

use diffgrep::{filter_diff, write_diff, Regex};

fn main() {
    let mut args = std::env::args().skip(1);
    let pattern = args.next().unwrap_or_else(|| {
        eprintln!("usage: diffgrep <pattern>");
        process::exit(2);
    });

    let regex = Regex::new(&pattern).unwrap_or_else(|e| {
        eprintln!("diffgrep: invalid pattern {:?}: {e}", pattern);
        process::exit(2);
    });

    let stdin = io::stdin();
    let reader = BufReader::new(stdin.lock());

    let diffs = filter_diff(reader, &regex).unwrap_or_else(|e| {
        eprintln!("diffgrep: read error: {e}");
        process::exit(1);
    });

    let found = !diffs.is_empty();

    let stdout = io::stdout();
    write_diff(&diffs, &mut stdout.lock()).unwrap_or_else(|e| {
        eprintln!("diffgrep: write error: {e}");
        process::exit(1);
    });

    process::exit(if found { 0 } else { 1 });
}
