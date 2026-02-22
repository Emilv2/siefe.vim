//! shada2fzf — parse Neovim shada and emit recent-file positions for fzf
//!
//! ## Usage
//!
//!     shada2fzf /path/to/shada/main.shada
//!
//! Reads the Neovim shada file and emits one line per recently-visited file:
//!
//!     line//col//filename\n
//!
//! The output is ready to feed directly to fzf (or `fzf_exec` in siefe.vim)
//! with `--delimiter=//`, `--with-nth=3..` (show only filename) and
//! `--preview-window=+{1}-/2` (scroll preview to line).  When fzf selects
//! an entry the Lua side parses `{1}`=line, `{2}`=col, `{3}`=filename and
//! opens the file with the cursor at the exact saved position.
//!
//! ## Shada binary format
//!
//! Each record consists of (all fields msgpack-encoded):
//!   1. Type — 1-byte fixint (value 1–12)
//!   2. Timestamp — msgpack uint (variable width)
//!   3. Length — msgpack uint; number of bytes in the following data
//!   4. Data — `length` raw bytes, a msgpack map
//!
//! We decode only **type 11** (`kSDItemLocalMark`) entries where the mark
//! name (`"n"`) is 34 (ASCII `"`) — the "last cursor position when leaving
//! a file" mark that Neovim writes for every visited file.
//!
//! ## MRU ordering and deduplication
//!
//! A shada file accumulates entries over time; compaction only happens on
//! `wshada!`.  The same file can therefore appear more than once with
//! different timestamps.  We collect all qualifying entries into a hash map
//! (filename → entry), keeping the one with the highest timestamp, then
//! sort descending by timestamp so the most-recently-visited files appear
//! first — matching the order users expect from `v:oldfiles`.

use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self, Write};

// ── Minimal msgpack reader ────────────────────────────────────────────────────

/// Cursor over a byte slice for sequential msgpack decoding.
struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(buf: &'a [u8]) -> Self {
        Reader { buf, pos: 0 }
    }

    fn is_empty(&self) -> bool {
        self.pos >= self.buf.len()
    }

    fn peek(&self) -> Option<u8> {
        self.buf.get(self.pos).copied()
    }

    fn next_byte(&mut self) -> Option<u8> {
        let b = *self.buf.get(self.pos)?;
        self.pos += 1;
        Some(b)
    }

    fn read_bytes_exact(&mut self, n: usize) -> Option<&'a [u8]> {
        let end = self.pos.checked_add(n)?;
        if end > self.buf.len() {
            return None;
        }
        let s = &self.buf[self.pos..end];
        self.pos = end;
        Some(s)
    }

    /// Read a msgpack unsigned integer (fixint / uint8 / uint16 / uint32 / uint64).
    fn read_uint(&mut self) -> Option<u64> {
        let b = self.next_byte()?;
        match b {
            0x00..=0x7f => Some(b as u64),
            0xcc => Some(self.next_byte()? as u64),
            0xcd => {
                let bs = self.read_bytes_exact(2)?;
                Some(u16::from_be_bytes([bs[0], bs[1]]) as u64)
            }
            0xce => {
                let bs = self.read_bytes_exact(4)?;
                Some(u32::from_be_bytes([bs[0], bs[1], bs[2], bs[3]]) as u64)
            }
            0xcf => {
                let bs = self.read_bytes_exact(8)?;
                Some(u64::from_be_bytes([
                    bs[0], bs[1], bs[2], bs[3], bs[4], bs[5], bs[6], bs[7],
                ]))
            }
            _ => None,
        }
    }

    /// Read a msgpack integer, accepting both signed and unsigned encodings.
    fn read_int(&mut self) -> Option<i64> {
        let tag = self.peek()?;
        match tag {
            // negative fixint
            0xe0..=0xff => {
                self.pos += 1;
                Some(tag as i8 as i64)
            }
            0xd0 => {
                self.pos += 1;
                Some(self.next_byte()? as i8 as i64)
            }
            0xd1 => {
                self.pos += 1;
                let bs = self.read_bytes_exact(2)?;
                Some(i16::from_be_bytes([bs[0], bs[1]]) as i64)
            }
            0xd2 => {
                self.pos += 1;
                let bs = self.read_bytes_exact(4)?;
                Some(i32::from_be_bytes([bs[0], bs[1], bs[2], bs[3]]) as i64)
            }
            0xd3 => {
                self.pos += 1;
                let bs = self.read_bytes_exact(8)?;
                Some(i64::from_be_bytes([
                    bs[0], bs[1], bs[2], bs[3], bs[4], bs[5], bs[6], bs[7],
                ]))
            }
            // Fall through to unsigned
            _ => self.read_uint().map(|v| v as i64),
        }
    }

    /// Read a msgpack string and return the raw UTF-8 bytes.
    fn read_str_bytes(&mut self) -> Option<&'a [u8]> {
        let b = self.next_byte()?;
        let len: usize = match b {
            0xa0..=0xbf => (b & 0x1f) as usize,
            0xd9 => self.next_byte()? as usize,
            0xda => {
                let bs = self.read_bytes_exact(2)?;
                u16::from_be_bytes([bs[0], bs[1]]) as usize
            }
            0xdb => {
                let bs = self.read_bytes_exact(4)?;
                u32::from_be_bytes([bs[0], bs[1], bs[2], bs[3]]) as usize
            }
            _ => return None,
        };
        self.read_bytes_exact(len)
    }

    /// Skip over one complete msgpack value (any type).
    fn skip_value(&mut self) -> Option<()> {
        let b = self.next_byte()?;
        match b {
            // nil, false, true, never-used
            0xc0 | 0xc2 | 0xc3 => {}
            // positive fixint, negative fixint (already consumed)
            0x00..=0x7f | 0xe0..=0xff => {}
            // fixed-width scalars
            0xcc | 0xd0 => {
                self.pos += 1;
            }
            0xcd | 0xd1 => {
                self.pos += 2;
            }
            0xce | 0xd2 | 0xca => {
                self.pos += 4;
            }
            0xcf | 0xd3 | 0xcb => {
                self.pos += 8;
            }
            // fixstr
            0xa0..=0xbf => {
                self.pos += (b & 0x1f) as usize;
            }
            // str8
            0xd9 => {
                let n = self.next_byte()? as usize;
                self.pos += n;
            }
            // str16
            0xda => {
                let bs = self.read_bytes_exact(2)?;
                self.pos += u16::from_be_bytes([bs[0], bs[1]]) as usize;
            }
            // str32 / bin32
            0xdb | 0xc6 => {
                let bs = self.read_bytes_exact(4)?;
                self.pos += u32::from_be_bytes([bs[0], bs[1], bs[2], bs[3]]) as usize;
            }
            // bin8
            0xc4 => {
                let n = self.next_byte()? as usize;
                self.pos += n;
            }
            // bin16
            0xc5 => {
                let bs = self.read_bytes_exact(2)?;
                self.pos += u16::from_be_bytes([bs[0], bs[1]]) as usize;
            }
            // fixarray
            0x90..=0x9f => {
                for _ in 0..(b & 0x0f) {
                    self.skip_value()?;
                }
            }
            // array16
            0xdc => {
                let bs = self.read_bytes_exact(2)?;
                let n = u16::from_be_bytes([bs[0], bs[1]]) as usize;
                for _ in 0..n {
                    self.skip_value()?;
                }
            }
            // array32
            0xdd => {
                let bs = self.read_bytes_exact(4)?;
                let n = u32::from_be_bytes([bs[0], bs[1], bs[2], bs[3]]) as usize;
                for _ in 0..n {
                    self.skip_value()?;
                }
            }
            // fixmap
            0x80..=0x8f => {
                for _ in 0..((b & 0x0f) as usize * 2) {
                    self.skip_value()?;
                }
            }
            // map16
            0xde => {
                let bs = self.read_bytes_exact(2)?;
                let n = u16::from_be_bytes([bs[0], bs[1]]) as usize;
                for _ in 0..(n * 2) {
                    self.skip_value()?;
                }
            }
            // map32
            0xdf => {
                let bs = self.read_bytes_exact(4)?;
                let n = u32::from_be_bytes([bs[0], bs[1], bs[2], bs[3]]) as usize;
                for _ in 0..(n * 2) {
                    self.skip_value()?;
                }
            }
            // ext types: fixext1-16, ext8, ext16, ext32
            0xd4 => {
                self.pos += 2;
            }
            0xd5 => {
                self.pos += 3;
            }
            0xd6 => {
                self.pos += 5;
            }
            0xd7 => {
                self.pos += 9;
            }
            0xd8 => {
                self.pos += 17;
            }
            0xc7 => {
                let n = self.next_byte()? as usize;
                self.pos += n + 1;
            }
            0xc8 => {
                let bs = self.read_bytes_exact(2)?;
                self.pos += u16::from_be_bytes([bs[0], bs[1]]) as usize + 1;
            }
            0xc9 => {
                let bs = self.read_bytes_exact(4)?;
                self.pos += u32::from_be_bytes([bs[0], bs[1], bs[2], bs[3]]) as usize + 1;
            }
            _ => return None,
        }
        Some(())
    }
}

// ── Shada record types ────────────────────────────────────────────────────────

const SHADA_LOCAL_MARK: u64 = 11; // kSDItemLocalMark
const MARK_DOUBLE_QUOTE: i64 = 34; // '"' — last cursor position per file

/// One decoded position entry from shada.
#[derive(Debug)]
struct PosEntry {
    filename: String,
    line: i64,
    col: i64,
    timestamp: u64,
}

// ── Shada parsing ─────────────────────────────────────────────────────────────

/// Parse the entire shada file contents, returning one `PosEntry` per file
/// (deduplicated, keeping the entry with the highest timestamp).
fn parse_shada(data: &[u8]) -> Vec<PosEntry> {
    // filename → best (highest-timestamp) PosEntry seen so far
    let mut best: HashMap<String, PosEntry> = HashMap::new();

    let mut r = Reader::new(data);

    while !r.is_empty() {
        // 1. Record type (fixint, 1 byte for types 1–12)
        let entry_type = match r.read_uint() {
            Some(t) => t,
            None => break,
        };
        // 2. Timestamp
        let timestamp = match r.read_uint() {
            Some(t) => t,
            None => break,
        };
        // 3. Length of the following msgpack data
        let length = match r.read_uint() {
            Some(l) => l as usize,
            None => break,
        };
        // 4. Data blob (exactly `length` bytes)
        let data_slice = match r.read_bytes_exact(length) {
            Some(s) => s,
            None => break,
        };

        if entry_type == SHADA_LOCAL_MARK {
            if let Some(entry) = decode_local_mark(data_slice, timestamp) {
                let cur = best.get(&entry.filename);
                if cur.is_none_or(|c| entry.timestamp > c.timestamp) {
                    best.insert(entry.filename.clone(), entry);
                }
            }
        }
    }

    let mut entries: Vec<PosEntry> = best.into_values().collect();
    // Sort most-recently-visited first (matches v:oldfiles MRU order)
    entries.sort_unstable_by(|a, b| b.timestamp.cmp(&a.timestamp));
    entries
}

/// Decode a single type-11 (LocalMark) data blob.
/// Returns `Some(PosEntry)` only for the `"` (double-quote) mark.
fn decode_local_mark(data: &[u8], timestamp: u64) -> Option<PosEntry> {
    let mut r = Reader::new(data);

    // The data is a msgpack map; read the count prefix.
    let b = r.next_byte()?;
    let num_pairs: usize = match b {
        0x80..=0x8f => (b & 0x0f) as usize,
        0xde => {
            let bs = r.read_bytes_exact(2)?;
            u16::from_be_bytes([bs[0], bs[1]]) as usize
        }
        0xdf => {
            let bs = r.read_bytes_exact(4)?;
            u32::from_be_bytes([bs[0], bs[1], bs[2], bs[3]]) as usize
        }
        _ => return None,
    };

    let mut filename = None::<String>;
    let mut line: i64 = 0;
    let mut col: i64 = 0;
    let mut mark_name: Option<i64> = None;

    for _ in 0..num_pairs {
        let key = r.read_str_bytes()?;
        match key {
            b"f" => {
                let s = r.read_str_bytes()?;
                filename = Some(String::from_utf8_lossy(s).into_owned());
            }
            b"n" => {
                mark_name = r.read_int();
            }
            b"l" => {
                line = r.read_int().unwrap_or(0);
            }
            b"c" => {
                col = r.read_int().unwrap_or(0);
            }
            _ => {
                // Unknown key — skip its value
                r.skip_value()?;
            }
        }
    }

    // Only emit the `"` mark (last-cursor-position-per-file)
    if mark_name != Some(MARK_DOUBLE_QUOTE) {
        return None;
    }

    Some(PosEntry {
        filename: filename?,
        line,
        col,
        timestamp,
    })
}

// ── Entry point ───────────────────────────────────────────────────────────────

fn main() -> io::Result<()> {
    let path = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: shada2fzf <shada-file>");
        std::process::exit(1);
    });

    let data = fs::read(&path).unwrap_or_else(|e| {
        eprintln!("shada2fzf: cannot read {path}: {e}");
        std::process::exit(1);
    });

    let entries = parse_shada(&data);

    let stdout = io::stdout();
    let mut out = stdout.lock();
    for e in &entries {
        // Separator is "//".  POSIX filenames cannot end with "/" so a literal
        // "//" never appears at the end of a component, but could theoretically
        // appear within a path (multiple consecutive slashes are equivalent to
        // one on Linux but are legal).  The Lua consumer uses
        // `table.concat(parts[3..], "//")` to rejoin any such filenames
        // correctly, so the round-trip is lossless.
        writeln!(out, "{}//{}//{}", e.line, e.col, e.filename)?;
    }
    out.flush()
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── msgpack helpers ───────────────────────────────────────────────────────

    /// Pack a small positive integer as a fixint (0–127).
    fn pack_fixint(v: u8) -> Vec<u8> {
        assert!(v < 128);
        vec![v]
    }

    /// Pack a uint64 using the smallest valid encoding.
    fn pack_uint(v: u64) -> Vec<u8> {
        if v < 128 {
            vec![v as u8]
        } else if v < 256 {
            vec![0xcc, v as u8]
        } else if v < 65536 {
            let b = (v as u16).to_be_bytes();
            vec![0xcd, b[0], b[1]]
        } else if v < 0x1_0000_0000 {
            let b = (v as u32).to_be_bytes();
            vec![0xce, b[0], b[1], b[2], b[3]]
        } else {
            let b = v.to_be_bytes();
            let mut out = vec![0xcf];
            out.extend_from_slice(&b);
            out
        }
    }

    /// Pack a signed int64 (uses the smallest encoding).
    fn pack_int(v: i64) -> Vec<u8> {
        if v >= 0 {
            pack_uint(v as u64)
        } else if v >= -32 {
            vec![(v as i8) as u8] // negative fixint
        } else if v >= i8::MIN as i64 {
            vec![0xd0, (v as i8) as u8]
        } else if v >= i16::MIN as i64 {
            let b = (v as i16).to_be_bytes();
            vec![0xd1, b[0], b[1]]
        } else if v >= i32::MIN as i64 {
            let b = (v as i32).to_be_bytes();
            vec![0xd2, b[0], b[1], b[2], b[3]]
        } else {
            let b = v.to_be_bytes();
            let mut out = vec![0xd3];
            out.extend_from_slice(&b);
            out
        }
    }

    /// Pack a short string as fixstr.
    fn pack_str(s: &str) -> Vec<u8> {
        assert!(s.len() < 32);
        let mut out = vec![0xa0 | s.len() as u8];
        out.extend_from_slice(s.as_bytes());
        out
    }

    /// Pack a fixmap with the given key-value pairs (both already packed).
    fn pack_map(pairs: &[(&str, Vec<u8>)]) -> Vec<u8> {
        assert!(pairs.len() < 16);
        let mut out = vec![0x80 | pairs.len() as u8];
        for (k, v) in pairs {
            out.extend(pack_str(k));
            out.extend(v);
        }
        out
    }

    /// Build a complete shada record for a local mark.
    fn make_local_mark_record(
        fname: &str,
        mark_name: i64,
        line: i64,
        col: i64,
        timestamp: u64,
    ) -> Vec<u8> {
        let data = pack_map(&[
            ("f", pack_str(fname)),
            ("n", pack_int(mark_name)),
            ("l", pack_int(line)),
            ("c", pack_int(col)),
        ]);
        let mut rec = Vec::new();
        rec.extend(pack_fixint(11)); // type = kSDItemLocalMark
        rec.extend(pack_uint(timestamp));
        rec.extend(pack_uint(data.len() as u64));
        rec.extend(data);
        rec
    }

    // ── decode_local_mark ─────────────────────────────────────────────────────

    #[test]
    fn decode_double_quote_mark() {
        let data = pack_map(&[
            ("f", pack_str("file.lua")),
            ("n", pack_int(34)), // '"'
            ("l", pack_int(42)),
            ("c", pack_int(5)),
        ]);
        let e = decode_local_mark(&data, 1000).unwrap();
        assert_eq!(e.filename, "file.lua");
        assert_eq!(e.line, 42);
        assert_eq!(e.col, 5);
        assert_eq!(e.timestamp, 1000);
    }

    #[test]
    fn decode_ignores_non_double_quote_marks() {
        // mark 'a' (97) should be ignored
        let data = pack_map(&[
            ("f", pack_str("file.lua")),
            ("n", pack_int(97)), // 'a'
            ("l", pack_int(10)),
            ("c", pack_int(0)),
        ]);
        assert!(decode_local_mark(&data, 1000).is_none());
    }

    #[test]
    fn decode_skips_unknown_keys() {
        let data = pack_map(&[
            ("f", pack_str("file.rs")),
            ("n", pack_int(34)),
            ("l", pack_int(7)),
            ("c", pack_int(3)),
            // "t" key (timestamp) — must be skipped gracefully
            ("t", pack_uint(999)),
        ]);
        let e = decode_local_mark(&data, 500).unwrap();
        assert_eq!(e.filename, "file.rs");
        assert_eq!(e.line, 7);
        assert_eq!(e.col, 3);
    }

    // ── parse_shada ───────────────────────────────────────────────────────────

    #[test]
    fn parse_single_record() {
        let rec = make_local_mark_record("a.lua", 34, 10, 2, 1700000000);
        let entries = parse_shada(&rec);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].filename, "a.lua");
        assert_eq!(entries[0].line, 10);
        assert_eq!(entries[0].col, 2);
    }

    #[test]
    fn parse_multiple_files() {
        let mut data = make_local_mark_record("a.lua", 34, 1, 0, 100);
        data.extend(make_local_mark_record("b.lua", 34, 2, 0, 200));
        let entries = parse_shada(&data);
        assert_eq!(entries.len(), 2);
        // Most recent (b.lua, ts=200) should be first
        assert_eq!(entries[0].filename, "b.lua");
        assert_eq!(entries[1].filename, "a.lua");
    }

    #[test]
    fn parse_deduplicates_same_file_keeps_latest() {
        // Same file appears twice; the entry with the higher timestamp wins
        let mut data = make_local_mark_record("dup.lua", 34, 5, 0, 100); // old
        data.extend(make_local_mark_record("dup.lua", 34, 99, 3, 200)); // new
        let entries = parse_shada(&data);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].line, 99);
        assert_eq!(entries[0].col, 3);
        assert_eq!(entries[0].timestamp, 200);
    }

    #[test]
    fn parse_ignores_other_mark_names() {
        // Mark 'a' (97) should produce no entries
        let data = make_local_mark_record("file.lua", 97, 1, 0, 100);
        let entries = parse_shada(&data);
        assert!(entries.is_empty());
    }

    #[test]
    fn parse_skips_non_local_mark_records() {
        // Fabricate a type-8 (global mark) record — same structure but type 8
        let inner = pack_map(&[
            ("f", pack_str("global.lua")),
            ("n", pack_int(65)), // 'A'
            ("l", pack_int(1)),
            ("c", pack_int(0)),
        ]);
        let mut rec = Vec::new();
        rec.extend(pack_fixint(8)); // type = kSDItemGlobalMark (not LocalMark)
        rec.extend(pack_uint(999));
        rec.extend(pack_uint(inner.len() as u64));
        rec.extend(inner);
        let entries = parse_shada(&rec);
        assert!(entries.is_empty());
    }

    #[test]
    fn parse_empty_input() {
        assert!(parse_shada(&[]).is_empty());
    }

    #[test]
    fn parse_mru_order() {
        // Three files written in chronological order; output should be newest first
        let mut data = make_local_mark_record("old.lua", 34, 1, 0, 1000);
        data.extend(make_local_mark_record("middle.lua", 34, 2, 0, 2000));
        data.extend(make_local_mark_record("new.lua", 34, 3, 0, 3000));
        let entries = parse_shada(&data);
        assert_eq!(entries[0].filename, "new.lua");
        assert_eq!(entries[1].filename, "middle.lua");
        assert_eq!(entries[2].filename, "old.lua");
    }

    #[test]
    fn pack_uint_roundtrip() {
        for &v in &[
            0u64,
            1,
            127,
            128,
            255,
            256,
            65535,
            65536,
            0xffff_ffff,
            0x1_0000_0000,
        ] {
            let packed = pack_uint(v);
            let mut r = Reader::new(&packed);
            assert_eq!(r.read_uint(), Some(v), "roundtrip failed for {v}");
        }
    }

    #[test]
    fn pack_int_roundtrip() {
        for &v in &[0i64, 1, 127, -1, -32, -33, i8::MIN as i64, i16::MIN as i64] {
            let packed = pack_int(v);
            let mut r = Reader::new(&packed);
            assert_eq!(r.read_int(), Some(v), "roundtrip failed for {v}");
        }
    }
}
