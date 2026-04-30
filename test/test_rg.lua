-- test/test_rg.lua – unit tests for lua/siefe/rg.lua pure-logic helpers
-- Run with: nvim --headless -u NONE -l test/test_rg.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

local T = require('test.helpers')

-- Reset module caches so each group starts fresh
package.loaded['siefe.config'] = nil
package.loaded['siefe.utils'] = nil
package.loaded['siefe.rg'] = nil

local rg = require('siefe.rg')
local t = rg._test

-- ── build_rg_command ──────────────────────────────────────────────────────────

T.group('build_rg_command', function()
  local base = {
    case_sensitive = 1,
    word = false,
    depth1 = false,
    hidden = false,
    no_ignore = 0,
    fixed_strings = false,
    max_1 = false,
    search_zip = false,
    text = false,
    type = '',
    paths = {},
  }

  -- Must contain core rg flags
  local cmd = t.build_rg_command(base)
  T.ok(cmd:find('rg ', 1, true), 'contains rg')
  T.ok(cmd:find('--column', 1, true), 'contains --column')
  T.ok(cmd:find('--line-number', 1, true), 'contains --line-number')
  T.ok(cmd:find('--with-filename', 1, true), 'contains --with-filename')
  -- %s placeholder is present for fzf_live / shellescape substitution
  T.ok(cmd:find('%s', 1, true), 'contains %s placeholder')

  -- No --null in search mode (fzf-lua builtin handles colon-delimited output)
  T.ok(not cmd:find('--null', 1, true), 'no --null in search mode')

  -- Case sensitivity flags
  local smart = t.build_rg_command(vim.tbl_extend('force', base, { case_sensitive = 1 }))
  T.ok(smart:find('--smart-case', 1, true), '--smart-case when case_sensitive=1')

  local ignore = t.build_rg_command(vim.tbl_extend('force', base, { case_sensitive = 2 }))
  T.ok(ignore:find('--ignore-case', 1, true), '--ignore-case when case_sensitive=2')

  local sens = t.build_rg_command(vim.tbl_extend('force', base, { case_sensitive = 0 }))
  T.ok(sens:find('--case-sensitive', 1, true), '--case-sensitive when case_sensitive=0')

  -- Word-boundary flag
  local word = t.build_rg_command(vim.tbl_extend('force', base, { word = true }))
  T.ok(word:find('-w ', 1, true), '-w when word=true')

  -- Hidden files flag
  local hidden = t.build_rg_command(vim.tbl_extend('force', base, { hidden = true }))
  T.ok(hidden:find('--hidden', 1, true), '--hidden when hidden=true')

  -- Paths are appended to the command
  local with_paths = t.build_rg_command(vim.tbl_extend('force', base, { paths = { 'src/', 'lib/' } }))
  T.ok(with_paths:find('src', 1, true), 'paths appended')
end)

-- ── build_files_command ───────────────────────────────────────────────────────

T.group('build_files_command', function()
  local base = {
    search_zip = false,
    text = false,
    no_ignore = 0,
    hidden = false,
    depth1 = false,
    type = '',
  }

  local cmd = t.build_files_command(base)
  -- rg --null is always present for files mode (NUL-terminated paths for --read0)
  T.ok(cmd:find('rg --null', 1, true), 'always has rg --null')
  T.ok(cmd:find('--files', 1, true), 'always has --files')
  T.ok(not cmd:find('--hidden', 1, true), 'no --hidden by default')

  local hidden = t.build_files_command(vim.tbl_extend('force', base, { hidden = true }))
  T.ok(hidden:find('--hidden', 1, true), '--hidden when hidden=true')

  local depth1 = t.build_files_command(vim.tbl_extend('force', base, { depth1 = true }))
  T.ok(depth1:find('-d1', 1, true), '-d1 when depth1=true')
end)

-- ── build_prompt ──────────────────────────────────────────────────────────────

T.group('build_prompt', function()
  local base = {
    case_sensitive = 1,
    word = false,
    depth1 = false,
    hidden = false,
    no_ignore = 0,
    fixed_strings = false,
    max_1 = false,
    search_zip = false,
    text = false,
    type = '',
    fzf = false,
    prompt = 'testdir',
  }

  -- rg mode (fzf=false) → prompt ends with "rg> "
  local rg_p = t.build_prompt(base, 'rg')
  T.ok(rg_p:find('rg>', 1, true), 'rg mode contains rg>')

  -- fzf mode (fzf=true) → prompt ends with "fzf> "
  local fzf_p = t.build_prompt(vim.tbl_extend('force', base, { fzf = true }), 'fzf')
  T.ok(fzf_p:find('fzf>', 1, true), 'fzf mode contains fzf>')

  -- files mode → prompt ends with "Files> "
  local files_p = t.build_prompt(base, 'files')
  T.ok(files_p:find('Files>', 1, true), 'files mode contains Files>')

  -- smart-case (case_sensitive=1) shows -S symbol in prompt
  T.ok(rg_p:find('-S', 1, true), 'smart-case shows -S in prompt')
end)

T.finish()
