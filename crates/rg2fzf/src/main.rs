//! rg2fzf — translate `rg --null` search output to NUL-terminated records
//!
//! `rg --null` in search mode emits records as:
//!
//!     filename\0line:col:matched_text\n
//!
//! The NUL byte falls *inside* each newline-terminated record as a field
//! separator between the filename and the rest of the match info.  fzf's
//! `--read0` flag splits the input stream on every NUL byte, which means it
//! would produce two entries per match ("filename" and "line:col:text")
//! rather than one.
//!
//! This binary reads those newline-terminated records from stdin and re-emits
//! them as NUL-terminated records:
//!
//!     filename:line:col:matched_text\0
//!
//! The transformation is:
//!   1. Find the first `\0` byte in each `\n`-terminated line (always the
//!      filename/rest separator in `rg --null` output).
//!   2. Replace it with `:`.
//!   3. Replace the trailing `\n` (record terminator) with `\0`.
//!
//! The result is the standard `file:line:col:text` format consumed by fzf-lua's
//! `path.entry_to_file()` parser, with each record NUL-terminated so fzf
//! `--read0` can safely split the stream.
//!
//! ## Colon ambiguity
//!
//! Filenames may contain `:` (e.g. `server:8080/handler.go`) and match text
//! may also contain `:` (e.g. `http://redirect.to:9090/api`).  The output
//! format `file:line:col:text` therefore does not uniquely identify field
//! boundaries by the `:` character alone.
//!
//! fzf-lua's `path.entry_to_file()` resolves this by splitting the entry on
//! `:` and then iterating, calling `uv.fs_stat()` on progressively longer
//! colon-joined candidates until one is confirmed to exist on disk.  Since rg
//! only matches files that exist, this always finds the correct boundary —
//! regardless of how many colons appear in the filename or the match text.
//! Using `:` as the output field separator is therefore correct.
//!
//! Lines that contain no `\0` (e.g. output from the `logger` wrapper, or rg
//! used without `--null`) are passed through with only the terminator changed
//! (`\n` → `\0`).
//!
//! Limitation: rg's multiline mode (`-U`) can produce match text that
//! contains literal `\n` bytes.  This binary splits on `\n` to find record
//! boundaries, so a match whose text spans multiple lines will be split into
//! separate output records — the first record will have the correct
//! `file:line:col:first_line\0` form, but subsequent lines of the same match
//! will appear as standalone (no-NUL passthrough) records and will be ignored
//! by fzf-lua's entry parser.  To avoid this, do not combine rg2fzf with
//! rg's `-U` flag.  Without rg2fzf the fallback (`\n`-terminated, no
//! `--read0`) is used, which has the same limitation.

use std::io::{self, BufRead, Write};

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = stdout.lock();
    translate(stdin.lock(), &mut out)
}

/// Core translation: reads `\n`-terminated rg `--null` records and writes
/// NUL-terminated `file:line:col:text` records.  Factored out so that the
/// unit tests can call it directly without spawning a process.
fn translate(reader: impl BufRead, out: &mut impl Write) -> io::Result<()> {
    for record in reader.split(b'\n') {
        let record = record?;
        if record.is_empty() {
            continue;
        }
        // Find the NUL byte that `rg --null` inserts after the filename.
        if let Some(nul) = record.iter().position(|&b| b == 0) {
            // Write: filename `:` line:col:text `\0`
            out.write_all(&record[..nul])?;
            out.write_all(b":")?;
            out.write_all(&record[nul + 1..])?;
        } else {
            // No NUL: rg wasn't called with --null, or this is a wrapper
            // header line.  Pass through with only the terminator changed.
            out.write_all(&record)?;
        }
        out.write_all(b"\0")?;
    }
    out.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(input: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        translate(io::Cursor::new(input), &mut out).unwrap();
        out
    }

    #[test]
    fn basic_record() {
        assert_eq!(run(b"file.lua\x001:5:hello world\n"), b"file.lua:1:5:hello world\0");
    }

    #[test]
    fn colon_in_filename_and_text() {
        // Both filename and match text contain colons simultaneously.
        // entry_to_file() disambiguates via uv.fs_stat(); rg2fzf's job is only
        // to preserve the NUL-to-colon substitution faithfully.
        assert_eq!(
            run(b"server:8080/handler.go\x001:1:http://redirect.to:9090/api\n"),
            b"server:8080/handler.go:1:1:http://redirect.to:9090/api\0"
        );
    }

    #[test]
    fn colon_in_filename() {
        assert_eq!(
            run(b"/path/to/file:with:colons.rs\x001:1:fn main\n"),
            b"/path/to/file:with:colons.rs:1:1:fn main\0"
        );
    }

    #[test]
    fn colon_in_match_text() {
        assert_eq!(
            run(b"file.lua\x001:1:foo:bar:baz\n"),
            b"file.lua:1:1:foo:bar:baz\0"
        );
    }

    #[test]
    fn multiple_records() {
        assert_eq!(
            run(b"a.lua\x001:1:foo\nb.lua\x002:3:bar\n"),
            b"a.lua:1:1:foo\0b.lua:2:3:bar\0"
        );
    }

    #[test]
    fn empty_lines_skipped() {
        assert_eq!(
            run(b"a.lua\x001:1:foo\n\nb.lua\x002:3:bar\n"),
            b"a.lua:1:1:foo\0b.lua:2:3:bar\0"
        );
    }

    #[test]
    fn no_nul_passthrough() {
        // Line without NUL (logger output, or rg without --null): pass through.
        assert_eq!(run(b"some log message\n"), b"some log message\0");
    }

    #[test]
    fn ansi_colors_in_output() {
        // ANSI escape sequences (from rg --color=always) must not affect NUL detection.
        let input = b"\x1b[32mfile.lua\x1b[0m\x001:1:text\n";
        let expected = b"\x1b[32mfile.lua\x1b[0m:1:1:text\0";
        assert_eq!(run(input), expected);
    }

    #[test]
    fn trailing_newline_only() {
        // A lone newline at end of stream produces no output.
        assert_eq!(run(b"\n"), b"");
    }

    #[test]
    fn empty_input() {
        assert_eq!(run(b""), b"");
    }
}
