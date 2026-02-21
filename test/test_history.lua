-- test/test_history.lua – unit tests for lua/siefe/history.lua pure-logic helpers
-- Run with: nvim --headless -u NONE -l test/test_history.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

local T = require('test.helpers')

package.loaded['siefe.config']  = nil
package.loaded['siefe.utils']   = nil
package.loaded['siefe.history'] = nil

local hist  = require('siefe.history')
local parse = hist._test.parse_entry

-- ── parse_entry ───────────────────────────────────────────────────────────────

T.group('parse_entry', function()
  -- Standard three-field format: line//col//filename
  local l, c, f = parse('10//2//a.lua')
  T.eq(l, 10,      'lnum')
  T.eq(c, 2,       'col')
  T.eq(f, 'a.lua', 'filename')

  -- Zero values
  local l2, c2, f2 = parse('0//0//simple.lua')
  T.eq(l2, 0,            'zero lnum')
  T.eq(c2, 0,            'zero col')
  T.eq(f2, 'simple.lua', 'zero filename')

  -- Filename containing "//" is reconstructed faithfully
  local l3, c3, f3 = parse('5//0//path//with//slashes.lua')
  T.eq(l3, 5,                        'double-slash filename: lnum')
  T.eq(c3, 0,                        'double-slash filename: col')
  T.eq(f3, 'path//with//slashes.lua','double-slash filename: filename rejoined')

  -- Legacy two-field format: line//filename (no col field)
  local l4, c4, f4 = parse('7//legacy.lua')
  T.eq(l4, 7,            'legacy: lnum')
  T.eq(c4, 0,            'legacy: col defaults to 0')
  T.eq(f4, 'legacy.lua', 'legacy: filename')

  -- No "//" separator: fall back to (0, 0, original line)
  local l5, c5, f5 = parse('no-separator')
  T.eq(l5, 0,             'no sep: lnum')
  T.eq(c5, 0,             'no sep: col')
  T.eq(f5, 'no-separator','no sep: returns original line')

  -- Non-numeric line number coerces to 0
  local l6, c6, f6 = parse('abc//0//file.lua')
  T.eq(l6, 0,         'non-numeric lnum → 0')
  T.eq(c6, 0,         'non-numeric lnum: col still 0')
  T.eq(f6, 'file.lua','non-numeric lnum: filename still parsed')
end)

T.finish()
