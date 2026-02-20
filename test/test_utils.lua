-- test/test_utils.lua – tests for lua/siefe/utils.lua (pure-Lua helpers)
-- Run with: nvim --headless -u NONE -l test/test_utils.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

local T = require('test.helpers')

-- Clear the siefe.config singleton so utils lazy-loads fresh defaults
package.loaded['siefe.config'] = nil

local utils = require('siefe.utils')

-- ── rg_delimiter ─────────────────────────────────────────────────────────────

T.group('rg_delimiter', function()
  T.eq(utils.rg_delimiter(), ':', 'returns colon')
  -- Idempotent
  T.eq(utils.rg_delimiter(), ':', 'idempotent')
end)

-- ── parse_rg_line ─────────────────────────────────────────────────────────────

T.group('parse_rg_line', function()
  -- Standard rg --column output: file:line:col:text
  local r = utils.parse_rg_line('src/foo.lua:10:5:hello world')
  T.eq(r.filename, 'src/foo.lua', 'filename')
  T.eq(r.lnum,     10,            'lnum')
  T.eq(r.col,      5,             'col')
  T.eq(r.text,     'hello world', 'text')

  -- Colons inside text are preserved
  local r2 = utils.parse_rg_line('a.lua:1:1:foo:bar:baz')
  T.eq(r2.filename, 'a.lua',       'filename with colons in text')
  T.eq(r2.text,     'foo:bar:baz', 'text with colons preserved')

  -- Non-matching line returns nil
  local r3 = utils.parse_rg_line('not a match')
  T.ok(r3 == nil, 'non-rg line returns nil')

  -- ANSI-escaped line (rg --color=always adds escape sequences in text)
  local ansi_line = 'file.lua:3:1:\27[31mhello\27[0m'
  local r4 = utils.parse_rg_line(ansi_line)
  T.eq(r4.filename, 'file.lua', 'filename with ANSI in text')
  T.eq(r4.lnum, 3,              'lnum with ANSI in text')
end)

-- ── detect_dups ───────────────────────────────────────────────────────────────

T.group('detect_dups', function()
  T.eq(utils.detect_dups({'a', 'b', 'c'}),       '',    'no duplicates')
  T.eq(utils.detect_dups({'a', 'b', 'a'}),       'a',   'one duplicate')
  T.eq(utils.detect_dups({'x', 'x', 'y', 'y'}), 'x y', 'two duplicates')
  T.eq(utils.detect_dups({}),                    '',    'empty list')
end)

-- ── preview_window_size ───────────────────────────────────────────────────────

T.group('preview_window_size', function()
  -- Narrow window: preview should be hidden by default, other_size visible
  package.loaded['siefe.config'] = nil
  require('siefe.config').setup({ preview_hide_threshold = 200, default_preview_size = 40 })
  vim.o.columns = 100  -- below threshold

  local def, other = utils.preview_window_size()
  T.eq(def,   '0%',    'narrow: default_size is 0% (hidden)')
  T.eq(other, '40%',   'narrow: other_size shows preview')

  -- Wide window: preview visible by default
  vim.o.columns = 300  -- above threshold
  def, other = utils.preview_window_size()
  T.eq(def,   '40%',    'wide: default_size shows preview')
  T.eq(other, 'hidden', 'wide: other_size is hidden')

  -- Reset
  package.loaded['siefe.config'] = nil
end)

-- ── ANSI color helpers ────────────────────────────────────────────────────────

T.group('ANSI helpers', function()
  -- Helpers return non-empty strings wrapping the input
  local r = utils.red('hello')
  T.ok(r:find('hello', 1, true), 'red() contains original text')
  T.ok(r:find('\27%[', 1), 'red() contains ESC sequence')

  local b = utils.blue('world')
  T.ok(b:find('world', 1, true), 'blue() contains original text')

  -- reset sequence present
  T.ok(r:find('\27%[m'), 'red() ends with reset')
end)

-- ── data_path ─────────────────────────────────────────────────────────────────

T.group('data_path', function()
  local p = utils.data_path()
  T.ok(type(p) == 'string' and #p > 0, 'data_path returns a non-empty string')
  T.ok(vim.fn.isdirectory(p) == 1, 'data_path directory was created')
end)

-- ── bin_path ──────────────────────────────────────────────────────────────────

T.group('bin_path', function()
  local preview = utils.bin_path('preview')
  T.ok(preview:find('/bin/preview$'), 'bin_path returns correct path')
  T.ok(vim.fn.filereadable(preview) == 1, 'bin/preview exists')
end)

T.finish()
