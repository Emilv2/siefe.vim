-- test/test_picker_actions.lua
-- Real integration tests for siefe picker action callbacks.
--
-- Strategy: mock fzf-lua so that fzf_exec / fzf_live capture the opts.actions
-- table instead of launching an interactive terminal.  We then call each action
-- fn(selected, opts) directly with a real entry and assert the expected Neovim
-- side-effects (buffer, cursor, register, quickfix list).
--
-- This exercises the full Lua code path from the top-level picker function
-- through the action callback, without requiring a real fzf process.
--
-- Run with: nvim --headless -u NONE -l test/test_picker_actions.lua
--
-- Inspired by nvim-autopairs:
--   https://github.com/windwp/nvim-autopairs/blob/master/tests/test_utils.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

-- Reset config module so each test file starts from a clean state.
package.loaded['siefe.config'] = nil

local T = require('test.helpers')
local utils = require('siefe.utils')

-- ── Temp directory ───────────────────────────────────────────────────────────

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, 'p')

local function make_file(name, lines)
  local path = tmpdir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

local function reset_buf()
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
end

-- ── fzf-lua mock ─────────────────────────────────────────────────────────────

-- Captured state from the last picker launch (set by mock).
local last_captured = { actions = nil, source = nil, opts = nil }

-- Stub file-open action: parses a "file:line:col[:text]" rg-format entry.
local function stub_open(cmd, entry)
  if not entry or entry == '' then
    return
  end
  local r = utils.parse_rg_line(entry)
  if r and vim.fn.filereadable(r.filename) == 1 then
    utils.open_file(cmd, r.filename, r.lnum, r.col)
  end
end

-- fzl_actions_stubs is the table that rg.lua reads via require('fzf-lua.actions').
local fzl_actions_stubs = {
  file_edit = function(sel, _o)
    stub_open('edit', sel and sel[1])
  end,
  file_split = function(sel, _o)
    stub_open('split', sel and sel[1])
  end,
  file_vsplit = function(sel, _o)
    stub_open('vsplit', sel and sel[1])
  end,
  file_tabedit = function(sel, _o)
    stub_open('tabedit', sel and sel[1])
  end,
  file_sel_to_qf = function(entries, _o)
    if not entries or #entries < 2 then
      return
    end
    local qf = {}
    for _, e in ipairs(entries) do
      local r = utils.parse_rg_line(e)
      if r then
        table.insert(qf, { filename = r.filename, lnum = r.lnum, col = r.col, text = r.text })
      end
    end
    if #qf >= 2 then
      vim.fn.setqflist({}, 'r', { items = qf })
    end
  end,
  file_sel_to_ll = function(_entries, _o) end,
}

local function make_fzl_mock()
  last_captured = { actions = nil, source = nil, opts = nil }
  -- rg.lua requires both 'fzf-lua' (for fzf_live/fzf_exec) and the submodule
  -- 'fzf-lua.actions' (for file_edit, file_split, …).  Both must be mocked.
  package.loaded['fzf-lua.actions'] = fzl_actions_stubs
  return {
    -- fzf_exec: static source (files mode, history, buffers, …)
    fzf_exec = function(src, opts)
      last_captured.source = src
      last_captured.opts = opts
      last_captured.actions = opts and opts.actions
    end,
    -- fzf_live: function source (live-rg mode)
    fzf_live = function(_src_fn, opts)
      last_captured.opts = opts
      last_captured.actions = opts and opts.actions
    end,
    -- fzl.actions also referenced directly (fzl = require('fzf-lua'))
    actions = fzl_actions_stubs,
  }
end

-- ── capture() helper ─────────────────────────────────────────────────────────

-- Run picker_fn() with a mocked fzf-lua; return the captured actions table.
-- config_opts: if provided, call siefe.config.setup(config_opts) first, then
--              reset to defaults after capture so tests don't bleed state.
local function capture(picker_fn, config_opts)
  local cfg = require('siefe.config')
  if config_opts then
    cfg.setup(config_opts)
  end

  -- Install mock before any picker module is (re)loaded.
  package.loaded['fzf-lua'] = make_fzl_mock() -- also sets package.loaded['fzf-lua.actions']

  -- Clear picker modules so they reload fresh with the current config & mock.
  -- Keep siefe.config (just configured) and siefe.utils (no fzf-lua dep).
  for k in pairs(package.loaded) do
    if k:match('^siefe%.') and k ~= 'siefe.config' and k ~= 'siefe.utils' then
      package.loaded[k] = nil
    end
  end

  picker_fn()

  local actions = last_captured.actions or {}

  -- Restore defaults after tests that customise config.
  if config_opts then
    cfg.setup({})
    -- Clear picker modules once more so subsequent tests get fresh defaults.
    for k in pairs(package.loaded) do
      if k:match('^siefe%.') and k ~= 'siefe.config' and k ~= 'siefe.utils' then
        package.loaded[k] = nil
      end
    end
  end

  -- Remove mock so accidental re-requires after capture() fail loudly.
  package.loaded['fzf-lua'] = nil
  package.loaded['fzf-lua.actions'] = nil

  return actions
end

-- ── RG picker tests ───────────────────────────────────────────────────────────

T.group('rg: default action opens file at correct line and column', function()
  reset_buf()
  local path = make_file('rg_basic.lua', { 'line one', 'line two', 'target here', 'line four' })
  local kwargs = {}
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  local entry = path .. ':3:5:target here'
  T.ok(type(actions['default']) == 'table', 'default action is registered')
  actions['default'].fn({ entry }, {})

  T.eq(vim.fn.expand('%:p'), path, 'correct file opened')
  T.eq(vim.api.nvim_win_get_cursor(0)[1], 3, 'cursor at line 3')
  T.eq(vim.api.nvim_win_get_cursor(0)[2] + 1, 5, 'cursor at col 5 (1-indexed)')
end)

T.group('rg: default action multi-select populates quickfix', function()
  vim.fn.setqflist({})
  local path = make_file('rg_qf.lua', { 'alpha', 'beta', 'gamma' })
  local kwargs = {}
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  local entries = {
    path .. ':1:1:alpha',
    path .. ':2:1:beta',
    path .. ':3:1:gamma',
  }
  actions['default'].fn(entries, {})

  local qf = vim.fn.getqflist()
  T.ok(#qf >= 2, 'quickfix has entries for multi-select (got ' .. tostring(#qf) .. ')')
end)

T.group('rg: yank action copies matched text to register', function()
  local path = make_file('rg_yank.lua', { 'hello world' })
  local kwargs = {}
  local config = require('siefe.config')
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  local entry = path .. ':1:1:hello world'
  T.ok(type(actions[config.rg_yank_key]) == 'table', 'yank action registered')
  actions[config.rg_yank_key].fn({ entry }, {})
  T.eq(vim.fn.getreg('"'), 'hello world', 'yank registers matched text')
end)

T.group('rg: word toggle sets kwargs.word on/off', function()
  local config = require('siefe.config')
  local kwargs = {}
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  T.ok(actions[config.rg_word_key] ~= nil, 'word toggle action registered')
  T.ok(not kwargs.word, 'word initially false')
  actions[config.rg_word_key].fn({}, {})
  T.ok(kwargs.word == true, 'first toggle → word = true')
  actions[config.rg_word_key].fn({}, {})
  T.ok(kwargs.word == false, 'second toggle → word = false')
end)

T.group('rg: case toggle cycles 1 (smart) → 2 (ignore) → 0 (sensitive)', function()
  local config = require('siefe.config')
  local kwargs = {}
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  -- Default case_sensitive = 1 (smart)
  T.eq(kwargs.case_sensitive, 1, 'initial case_sensitive = 1 (smart)')
  actions[config.rg_case_key].fn({}, {})
  T.eq(kwargs.case_sensitive, 2, 'after 1 toggle → 2 (ignore-case)')
  actions[config.rg_case_key].fn({}, {})
  T.eq(kwargs.case_sensitive, 0, 'after 2 toggles → 0 (case-sensitive)')
  actions[config.rg_case_key].fn({}, {})
  T.eq(kwargs.case_sensitive, 1, 'after 3 toggles → back to 1 (smart)')
end)

T.group('rg: hidden toggle sets kwargs.hidden', function()
  local config = require('siefe.config')
  local kwargs = {}
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  T.ok(not kwargs.hidden, 'hidden initially false')
  actions[config.rg_hidden_key].fn({}, {})
  T.ok(kwargs.hidden == true, 'hidden toggle → true')
end)

T.group('rg: no-ignore toggle cycles 0 → 1 → 2 → 3 → 0', function()
  local config = require('siefe.config')
  local kwargs = {}
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  T.eq(kwargs.no_ignore, 0, 'no_ignore initially 0')
  actions[config.rg_no_ignore_key].fn({}, {})
  T.eq(kwargs.no_ignore, 1, 'after 1 toggle → 1 (-u)')
  actions[config.rg_no_ignore_key].fn({}, {})
  T.eq(kwargs.no_ignore, 2, 'after 2 toggles → 2 (-uu)')
  actions[config.rg_no_ignore_key].fn({}, {})
  T.eq(kwargs.no_ignore, 3, 'after 3 toggles → 3 (-uuu)')
  actions[config.rg_no_ignore_key].fn({}, {})
  T.eq(kwargs.no_ignore, 0, 'after 4 toggles → back to 0')
end)

T.group('rg: vdiffsplit action opens file in vertical diffsplit', function()
  reset_buf()
  local path = make_file('rg_diff.lua', { 'diff line 1', 'diff line 2' })
  local config = require('siefe.config')
  local kwargs = {}
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  local win_before = #vim.api.nvim_list_wins()
  local entry = path .. ':1:1:diff line 1'
  T.ok(type(actions[config.vdiffsplit_key]) == 'table', 'vdiffsplit action registered')
  actions[config.vdiffsplit_key].fn({ entry }, {})
  T.ok(#vim.api.nvim_list_wins() > win_before, 'vdiffsplit opened a new window')
  vim.cmd('only!')
end)

-- ── History picker tests ──────────────────────────────────────────────────────

T.group('history: default action opens file at saved line and column', function()
  reset_buf()
  local path = make_file('hist_action.lua', { 'a', 'b', 'saved line', 'd', 'e' })
  local history_m = require('siefe.history')
  -- Build a valid history entry using the module's own format
  local entry = history_m._test.make_history_entry(3, 2, path)

  local kwargs = {}
  local actions = capture(function()
    require('siefe.history').historyoldfiles(false, kwargs)
  end)

  T.ok(type(actions['default']) == 'table', 'default action registered')
  actions['default'].fn({ entry }, {})

  T.eq(vim.fn.expand('%:p'), path, 'correct file opened')
  T.eq(vim.api.nvim_win_get_cursor(0)[1], 3, 'cursor at saved line 3')
  T.eq(vim.api.nvim_win_get_cursor(0)[2] + 1, 2, 'cursor at saved col 2')
end)

T.group('history: default action multi-select populates quickfix', function()
  vim.fn.setqflist({})
  local p1 = make_file('hist_qf1.lua', { 'aaa' })
  local p2 = make_file('hist_qf2.lua', { 'bbb' })
  local history_m = require('siefe.history')
  local e1 = history_m._test.make_history_entry(1, 1, p1)
  local e2 = history_m._test.make_history_entry(1, 1, p2)

  local kwargs = {}
  local actions = capture(function()
    require('siefe.history').historyoldfiles(false, kwargs)
  end)

  actions['default'].fn({ e1, e2 }, {})
  local qf = vim.fn.getqflist()
  T.ok(#qf >= 2, 'multi-select populates quickfix (' .. tostring(#qf) .. ' entries)')
end)

T.group('history: project toggle flips kwargs.project', function()
  local config = require('siefe.config')
  local kwargs = {}
  local actions = capture(function()
    require('siefe.history').historyoldfiles(false, kwargs)
  end)

  T.ok(not kwargs.project, 'project initially false')
  T.ok(type(actions[config.history_git_key]) == 'table', 'project toggle registered')
  actions[config.history_git_key].fn({}, {})
  T.ok(kwargs.project == true, 'toggle sets kwargs.project = true')
end)

T.group('history: split action opens file in a new window', function()
  reset_buf()
  local path = make_file('hist_split.lua', { 'split content' })
  local history_m = require('siefe.history')
  local entry = history_m._test.make_history_entry(1, 1, path)
  local config = require('siefe.config')
  local kwargs = {}
  local actions = capture(function()
    require('siefe.history').historyoldfiles(false, kwargs)
  end)

  local win_before = #vim.api.nvim_list_wins()
  T.ok(type(actions[config.split_key]) == 'table', 'split action registered')
  actions[config.split_key].fn({ entry }, {})
  T.ok(#vim.api.nvim_list_wins() > win_before, 'split opened a new window')
  vim.cmd('only!')
end)

-- ── Buffers picker tests ──────────────────────────────────────────────────────

T.group('buffers: default action switches to the selected buffer', function()
  local path = make_file('buf_switch.txt', { 'buffer content' })
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local target_buf = vim.api.nvim_get_current_buf()
  reset_buf() -- switch away from target_buf

  T.ok(vim.api.nvim_get_current_buf() ~= target_buf, 'not on target buffer initially')

  local actions = capture(function()
    require('siefe.buffers').buffers(false, {})
  end)

  -- Find the entry for target_buf in the captured source.
  local target_entry
  for _, e in ipairs(last_captured.source or {}) do
    if e:match('%[' .. tostring(target_buf) .. '%]') then
      target_entry = e
      break
    end
  end

  T.ok(target_entry ~= nil, 'target buffer has an entry in picker source')
  T.ok(type(actions['default']) == 'table', 'default action registered')
  actions['default'].fn({ target_entry }, {})
  T.eq(vim.api.nvim_get_current_buf(), target_buf, 'switched to target buffer')
end)

T.group('buffers: delete action removes the buffer', function()
  local path = make_file('buf_delete.txt', { 'will be deleted' })
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local del_buf = vim.api.nvim_get_current_buf()
  reset_buf() -- leave del_buf so it is listed but not current

  T.ok(vim.fn.buflisted(del_buf) == 1, 'buffer is listed before delete')

  local actions = capture(function()
    require('siefe.buffers').buffers(false, {})
  end)

  local del_entry
  for _, e in ipairs(last_captured.source or {}) do
    if e:match('%[' .. tostring(del_buf) .. '%]') then
      del_entry = e
      break
    end
  end

  T.ok(del_entry ~= nil, 'buffer-to-delete has an entry in source')
  local config = require('siefe.config')
  T.ok(type(actions[config.buffers_delete_key]) == 'table', 'delete action registered')
  actions[config.buffers_delete_key].fn({ del_entry }, {})
  T.eq(vim.fn.buflisted(del_buf), 0, 'buffer is no longer listed after delete')
end)

T.group('buffers: project toggle flips kwargs.project', function()
  local config = require('siefe.config')
  local kwargs = {}
  local actions = capture(function()
    require('siefe.buffers').buffers(false, kwargs)
  end)

  T.ok(not kwargs.project, 'project initially false')
  T.ok(type(actions[config.buffers_git_key]) == 'table', 'project toggle registered')
  actions[config.buffers_git_key].fn({}, {})
  T.ok(kwargs.project == true, 'toggle sets kwargs.project = true')
end)

-- ── Config / custom shortcuts tests ──────────────────────────────────────────

T.group('config: default rg_word_key is ctrl-w', function()
  local config = require('siefe.config')
  T.eq(config.rg_word_key, 'ctrl-w', 'default rg_word_key is ctrl-w')

  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end)
  T.ok(type(actions['ctrl-w']) == 'table', 'ctrl-w wired to word toggle in rg actions')
end)

T.group('config: custom rg_word_key changes the action key', function()
  -- Custom config: move word toggle from ctrl-w to alt-w
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end, { rg_word_key = 'alt-w' })

  T.ok(type(actions['alt-w']) == 'table', 'alt-w is now the word toggle action')
  T.ok(actions['ctrl-w'] == nil, 'ctrl-w is no longer the word toggle action')
end)

T.group('config: custom split_key changes rg and history actions', function()
  -- Use ctrl-z as the custom split key
  local rg_actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end, { split_key = 'ctrl-z' })

  T.ok(type(rg_actions['ctrl-z']) == 'table', 'rg: ctrl-z is the split action')
  T.ok(rg_actions['ctrl-]'] == nil, 'rg: ctrl-] no longer registered for split')

  local hist_actions = capture(function()
    require('siefe.history').historyoldfiles(false, {})
  end, { split_key = 'ctrl-z' })

  T.ok(type(hist_actions['ctrl-z']) == 'table', 'history: ctrl-z is the split action')
  T.ok(hist_actions['ctrl-]'] == nil, 'history: ctrl-] no longer registered for split')
end)

T.group('config: custom rg_case_key changes case toggle action', function()
  local actions = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end, { rg_case_key = 'alt-c' })

  T.ok(type(actions['alt-c']) == 'table', 'alt-c is the case toggle action')
  T.ok(actions['ctrl-s'] == nil, 'ctrl-s no longer the case toggle')
end)

T.group('config: history_git_key (project toggle) default is ctrl-g', function()
  local config = require('siefe.config')
  T.eq(config.history_git_key, 'ctrl-g', 'default history_git_key is ctrl-g')

  local actions = capture(function()
    require('siefe.history').historyoldfiles(false, {})
  end)
  T.ok(type(actions['ctrl-g']) == 'table', 'ctrl-g is the project toggle in history')
end)

-- ── Cleanup ───────────────────────────────────────────────────────────────────

vim.fn.delete(tmpdir, 'rf')

T.finish()
