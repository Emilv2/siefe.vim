-- test/test_history.lua – unit tests for lua/siefe/history.lua pure-logic helpers
-- Run with: nvim --headless -u NONE -l test/test_history.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

local T = require('test.helpers')

package.loaded['siefe.config'] = nil
package.loaded['siefe.utils'] = nil
package.loaded['siefe.history'] = nil

local hist = require('siefe.history')
local parse = hist._test.parse_entry
local make_entry = hist._test.make_history_entry

-- ── parse_entry: legacy //-separated format ───────────────────────────────────

T.group('parse_entry (legacy // format)', function()
  -- Standard three-field format: line//col//filename
  local l, c, f = parse('10//2//a.lua')
  T.eq(l, 10, 'lnum')
  T.eq(c, 2, 'col')
  T.eq(f, 'a.lua', 'filename')

  -- Zero values
  local l2, c2, f2 = parse('0//0//simple.lua')
  T.eq(l2, 0, 'zero lnum')
  T.eq(c2, 0, 'zero col')
  T.eq(f2, 'simple.lua', 'zero filename')

  -- Filename containing "//" is reconstructed faithfully
  local l3, c3, f3 = parse('5//0//path//with//slashes.lua')
  T.eq(l3, 5, 'double-slash filename: lnum')
  T.eq(c3, 0, 'double-slash filename: col')
  T.eq(f3, 'path//with//slashes.lua', 'double-slash filename: filename rejoined')

  -- Legacy two-field format: line//filename (no col field)
  local l4, c4, f4 = parse('7//legacy.lua')
  T.eq(l4, 7, 'legacy: lnum')
  T.eq(c4, 0, 'legacy: col defaults to 0')
  T.eq(f4, 'legacy.lua', 'legacy: filename')

  -- No "//" separator: fall back to (0, 0, original line)
  local l5, c5, f5 = parse('no-separator')
  T.eq(l5, 0, 'no sep: lnum')
  T.eq(c5, 0, 'no sep: col')
  T.eq(f5, 'no-separator', 'no sep: returns original line')

  -- Non-numeric line number coerces to 0
  local l6, c6, f6 = parse('abc//0//file.lua')
  T.eq(l6, 0, 'non-numeric lnum → 0')
  T.eq(c6, 0, 'non-numeric lnum: col still 0')
  T.eq(f6, 'file.lua', 'non-numeric lnum: filename still parsed')
end)

-- ── parse_entry: intermediate \t format (backward compat) ─────────────────────

T.group('parse_entry (intermediate tab format)', function()
  -- Intermediate format: lnum\tcol\tfname\tdisplay
  local l, c, f = parse('15\t3\tsome/file.rs\tdisplay text')
  T.eq(l, 15, 'tab lnum')
  T.eq(c, 3, 'tab col')
  T.eq(f, 'some/file.rs', 'tab filename')
end)

-- ── make_history_entry + parse_entry round-trip ───────────────────────────────

T.group('make_history_entry / parse_entry round-trip', function()
  -- Normal entry with line and col
  local e1 = make_entry(42, 5, 'src/main.lua')
  local l1, c1, f1 = parse(e1)
  T.eq(l1, 42, 'round-trip lnum')
  T.eq(c1, 5, 'round-trip col')
  T.eq(f1, 'src/main.lua', 'round-trip filename')

  -- Entry with lnum=0 (no position)
  local e2 = make_entry(0, 0, 'readme.md')
  local l2, c2, f2 = parse(e2)
  T.eq(l2, 0, 'zero lnum round-trip')
  T.eq(c2, 0, 'zero col round-trip')
  T.eq(f2, 'readme.md', 'zero lnum filename round-trip')

  -- Entry whose filename contains spaces
  local e3 = make_entry(7, 0, 'my docs/file.md')
  local l3, _, f3 = parse(e3)
  T.eq(l3, 7, 'spaces in filename: lnum')
  T.eq(f3, 'my docs/file.md', 'spaces in filename: filename')

  -- New format: fname:lnum:col\x01display (entry_to_file reads ':'-separated prefix)
  local sep = e1:find('\x01', 1, true)
  T.ok(sep ~= nil, 'make_history_entry contains \\x01 separator')
  local prefix = e1:sub(1, sep - 1)
  local display = e1:sub(sep + 1)
  -- prefix must be fname:lnum:col
  T.ok(prefix == 'src/main.lua:42:5', 'prefix is fname:lnum:col')
  -- display contains the filename
  T.ok(display:find('src/main.lua', 1, true), 'display contains filename')
end)

-- ── make_absolute ──────────────────────────────────────────────────────────────

local make_abs = hist._test.make_absolute

T.group('make_absolute', function()
  -- non-project mode: fname returned unchanged (even if relative)
  T.eq(make_abs('src/foo.lua', '/repo', false), 'src/foo.lua', 'non-project: relative unchanged')
  T.eq(make_abs('/abs/path.lua', '/repo', false), '/abs/path.lua', 'non-project: absolute unchanged')

  -- project mode, relative fname: git_root prepended
  T.eq(make_abs('src/foo.lua', '/repo', true), '/repo/src/foo.lua', 'project: relative resolved')
  T.eq(make_abs('a/b/c.lua', '/home/user/proj', true), '/home/user/proj/a/b/c.lua', 'project: deep relative')

  -- project mode, already absolute: returned unchanged
  T.eq(make_abs('/abs/path.lua', '/repo', true), '/abs/path.lua', 'project: absolute unchanged')

  -- edge cases
  T.eq(make_abs('', '/repo', true), '', 'empty fname unchanged')
  T.eq(make_abs('file.lua', '', true), 'file.lua', 'empty git_root: fname unchanged')
  T.eq(make_abs('file.lua', nil, true), 'file.lua', 'nil git_root: fname unchanged')
end)

T.finish()
