-- test/test_rg.lua – unit tests for lua/siefe/rg.lua pure-logic helpers
-- Run with: nvim --headless -u NONE -l test/test_rg.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

local T = require('test.helpers')

-- Reset module caches so each group starts fresh
package.loaded['siefe.config']  = nil
package.loaded['siefe.utils']   = nil
package.loaded['siefe.rg']      = nil

local rg = require('siefe.rg')
local t  = rg._test

-- ── parse_rg2fzf_entry ────────────────────────────────────────────────────────

T.group('parse_rg2fzf_entry', function()
  -- Normal entry: filename SOH line:col:text
  local r = t.parse_rg2fzf_entry('file.lua\x011:5:hello world')
  T.eq(r.filename, 'file.lua',    'filename')
  T.eq(r.lnum,     1,             'lnum')
  T.eq(r.col,      5,             'col')
  T.eq(r.text,     'hello world', 'text')

  -- Colons in filename: SOH still unambiguously marks the boundary
  local r2 = t.parse_rg2fzf_entry('server:8080/api.go\x011:1:GET /api')
  T.eq(r2.filename, 'server:8080/api.go', 'colons-in-filename: filename correct')
  T.eq(r2.lnum,     1,                    'colons-in-filename: lnum')
  T.eq(r2.text,     'GET /api',           'colons-in-filename: text')

  -- Colons in match text: all preserved
  local r3 = t.parse_rg2fzf_entry('file.rs\x011:1:foo:bar:baz')
  T.eq(r3.text, 'foo:bar:baz', 'colons in text preserved')

  -- Simple ANSI CSI stripped from filename before SOH
  local r4 = t.parse_rg2fzf_entry('\x1b[32mfile.lua\x1b[0m\x011:1:text')
  T.eq(r4.filename, 'file.lua', 'simple ANSI stripped from filename')
  T.eq(r4.lnum,     1,          'ANSI-stripped: lnum')

  -- Complex ANSI (bold + colour) in match text
  local r5 = t.parse_rg2fzf_entry('a.lua\x011:1:\x1b[1;31mhello\x1b[0m world')
  T.eq(r5.filename, 'a.lua', 'complex ANSI in text: filename ok')
  T.eq(r5.lnum,     1,       'complex ANSI in text: lnum ok')

  -- No SOH separator → nil
  local r6 = t.parse_rg2fzf_entry('file.lua:1:1:text')
  T.ok(r6 == nil, 'no SOH returns nil')

  -- SOH present but tail has no line:col pattern → nil
  local r7 = t.parse_rg2fzf_entry('file.lua\x01not-a-position')
  T.ok(r7 == nil, 'SOH but no line:col returns nil')
end)

-- ── build_rg_command ──────────────────────────────────────────────────────────

T.group('build_rg_command', function()
  local base = {
    case_sensitive = 1, word = false, depth1 = false, hidden = false,
    no_ignore = 0, fixed_strings = false, max_1 = false,
    search_zip = false, text = false, type = '', paths = {},
  }

  -- Must contain core rg flags
  local cmd = t.build_rg_command(base, nil)
  T.ok(cmd:find('rg ',           1, true), 'contains rg')
  T.ok(cmd:find('--column',      1, true), 'contains --column')
  T.ok(cmd:find('--line-number', 1, true), 'contains --line-number')
  T.ok(cmd:find('--with-filename',1,true), 'contains --with-filename')
  -- %s placeholder is present for fzf_live / shellescape substitution
  T.ok(cmd:find('%s', 1, true),            'contains %s placeholder')

  -- No --null when no rg2fzf_path given
  T.ok(not cmd:find('--null', 1, true), 'no --null without rg2fzf')

  -- With rg2fzf_path: --null added, binary piped
  local cmd2 = t.build_rg_command(base, '/bin/rg2fzf')
  T.ok(cmd2:find('--null',  1, true), '--null with rg2fzf')
  T.ok(cmd2:find('rg2fzf',  1, true), 'rg2fzf pipe appended')

  -- Case sensitivity flags
  local smart = t.build_rg_command(vim.tbl_extend('force', base, {case_sensitive=1}), nil)
  T.ok(smart:find('--smart-case', 1, true), '--smart-case when case_sensitive=1')

  local ignore = t.build_rg_command(vim.tbl_extend('force', base, {case_sensitive=2}), nil)
  T.ok(ignore:find('--ignore-case', 1, true), '--ignore-case when case_sensitive=2')

  local sens = t.build_rg_command(vim.tbl_extend('force', base, {case_sensitive=0}), nil)
  T.ok(sens:find('--case-sensitive', 1, true), '--case-sensitive when case_sensitive=0')

  -- Word-boundary flag
  local word = t.build_rg_command(vim.tbl_extend('force', base, {word=true}), nil)
  T.ok(word:find('-w ', 1, true), '-w when word=true')

  -- Hidden files flag
  local hidden = t.build_rg_command(vim.tbl_extend('force', base, {hidden=true}), nil)
  T.ok(hidden:find('--hidden', 1, true), '--hidden when hidden=true')

  -- Paths are appended to the command
  local with_paths = t.build_rg_command(
    vim.tbl_extend('force', base, {paths={'src/', 'lib/'}}), nil)
  T.ok(with_paths:find('src', 1, true), 'paths appended')
end)

-- ── build_files_command ───────────────────────────────────────────────────────

T.group('build_files_command', function()
  local base = {
    search_zip = false, text = false, no_ignore = 0,
    hidden = false, depth1 = false, type = '',
  }

  local cmd = t.build_files_command(base)
  -- rg --null is always present (NUL-terminated paths for --read0)
  T.ok(cmd:find('rg --null', 1, true), 'always has rg --null')
  T.ok(cmd:find('--files',   1, true), 'always has --files')
  T.ok(not cmd:find('--hidden', 1, true), 'no --hidden by default')

  local hidden = t.build_files_command(vim.tbl_extend('force', base, {hidden=true}))
  T.ok(hidden:find('--hidden', 1, true), '--hidden when hidden=true')

  local depth1 = t.build_files_command(vim.tbl_extend('force', base, {depth1=true}))
  T.ok(depth1:find('-d1', 1, true), '-d1 when depth1=true')
end)

-- ── build_prompt ──────────────────────────────────────────────────────────────

T.group('build_prompt', function()
  local base = {
    case_sensitive = 1, word = false, depth1 = false, hidden = false,
    no_ignore = 0, fixed_strings = false, max_1 = false,
    search_zip = false, text = false, type = '', fzf = false,
    prompt = 'testdir',
  }

  -- rg mode (fzf=false) → prompt ends with "rg> "
  local rg_p = t.build_prompt(base, 'rg')
  T.ok(rg_p:find('rg>', 1, true), 'rg mode contains rg>')

  -- fzf mode (fzf=true) → prompt ends with "fzf> "
  local fzf_p = t.build_prompt(vim.tbl_extend('force', base, {fzf=true}), 'fzf')
  T.ok(fzf_p:find('fzf>', 1, true), 'fzf mode contains fzf>')

  -- files mode → prompt ends with "Files> "
  local files_p = t.build_prompt(base, 'files')
  T.ok(files_p:find('Files>', 1, true), 'files mode contains Files>')

  -- smart-case (case_sensitive=1) shows -S symbol in prompt
  T.ok(rg_p:find('-S', 1, true), 'smart-case shows -S in prompt')
end)

T.finish()
