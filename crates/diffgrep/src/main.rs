//! diffgrep — filter a unified diff to hunks whose +/- lines match a pattern.
//!
//! Usage:
//!   git show <commit> | diffgrep [-G] <pattern>   (regex, -G mode, default)
//!   git show <commit> | diffgrep -S <pattern>     (literal string, -S mode)
//!   git diff HEAD~1   | diffgrep <pattern>         (bare pattern = -G)
//!
//! Modes mirror git's pickaxe flags:
//!   -G <regex>    hunk matches if any +/- line matches the regex  (default)
//!   -S <string>   hunk matches if the count of the literal string differs
//!                 between added (+) and removed (-) lines
//!
//! Output is a plain unified diff containing only the matching file/hunk pairs.
//! Exit code 0 if any matches were found, 1 if none, 2 on usage/regex error.

use std::io::{self, BufReader};
use std::process;

use diffgrep::{filter_diff, write_diff, Match, Regex};

const VERSION: &str = concat!(
    env!("CARGO_PKG_NAME"),
    " ",
    env!("CARGO_PKG_VERSION"),
    " (git:",
    env!("SIEFE_GIT_HASH", "unknown"),
    ")"
);

fn main() {
    let mut args = std::env::args().skip(1).peekable();

    // Handle --version / -V
    if args.peek().map(|a| a == "--version" || a == "-V").unwrap_or(false) {
        println!("{VERSION}");
        return;
    }

    // Parse optional -G / -S flag followed by the pattern.
    let (use_s, pattern) = match args.next().as_deref() {
        Some("-G") => {
            let p = args.next().unwrap_or_else(|| {
                eprintln!("usage: diffgrep [-G|-S] <pattern>");
                process::exit(2);
            });
            (false, p)
        }
        Some("-S") => {
            let p = args.next().unwrap_or_else(|| {
                eprintln!("usage: diffgrep [-G|-S] <pattern>");
                process::exit(2);
            });
            (true, p)
        }
        Some(p) => (false, p.to_owned()), // bare pattern → -G (regex)
        None => {
            eprintln!("usage: diffgrep [-G|-S] <pattern>");
            process::exit(2);
        }
    };

    let match_pattern: Match = if use_s {
        Match::Literal(pattern)
    } else {
        let regex = Regex::new(&pattern).unwrap_or_else(|e| {
            eprintln!("diffgrep: invalid pattern {:?}: {e}", pattern);
            process::exit(2);
        });
        Match::Regex(regex)
    };

    let stdin = io::stdin();
    let reader = BufReader::new(stdin.lock());

    let diffs = filter_diff(reader, &match_pattern).unwrap_or_else(|e| {
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
