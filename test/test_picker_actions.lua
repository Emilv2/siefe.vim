-- test/test_picker_actions.lua
-- Real integration tests for siefe picker action callbacks.
--
-- Strategy: mock fzf-lua so that fzf_exec / fzf_live capture opts.actions AND
-- opts.keymap.fzf instead of launching an interactive terminal.  We then call
-- each action fn(selected, opts) directly with a real entry and assert the
-- expected Neovim side-effects (buffer, cursor, register, quickfix list).
--
-- We also test keymap.fzf binds (toggle-preview, F7 preview cycle, etc.)
-- and verify that custom config keys are reflected in both tables.
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
-- Returns: { actions, keymap_fzf, keymap_builtin, source, opts }
-- • actions:        opts.actions table (Lua-side action callbacks)
-- • keymap_fzf:     opts.keymap.fzf table (fzf-native bind strings)
-- • keymap_builtin: opts.keymap.builtin table (fzf-lua builtin action strings)
-- • source:         the source passed to fzf_exec (table of entries)
-- • opts:           the full opts table
local last_captured = { actions = nil, keymap_fzf = nil, keymap_builtin = nil, source = nil, opts = nil }

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
  last_captured = { actions = nil, keymap_fzf = nil, keymap_builtin = nil, source = nil, opts = nil }
  -- rg.lua requires both 'fzf-lua' (for fzf_live/fzf_exec) and the submodule
  -- 'fzf-lua.actions' (for file_edit, file_split, …).  Both must be mocked.
  package.loaded['fzf-lua.actions'] = fzl_actions_stubs
  return {
    -- fzf_exec: static source (files mode, history, buffers, …)
    fzf_exec = function(src, opts)
      last_captured.source = src
      last_captured.opts = opts
      last_captured.actions = opts and opts.actions
      last_captured.keymap_fzf = opts and opts.keymap and opts.keymap.fzf
      last_captured.keymap_builtin = opts and opts.keymap and opts.keymap.builtin
    end,
    -- fzf_live: function source (live-rg mode)
    fzf_live = function(_src_fn, opts)
      last_captured.opts = opts
      last_captured.actions = opts and opts.actions
      last_captured.keymap_fzf = opts and opts.keymap and opts.keymap.fzf
      last_captured.keymap_builtin = opts and opts.keymap and opts.keymap.builtin
    end,
    -- fzl.actions also referenced directly (fzl = require('fzf-lua'))
    actions = fzl_actions_stubs,
  }
end

-- ── capture() helper ─────────────────────────────────────────────────────────

-- Run picker_fn() with a mocked fzf-lua; return the captured state table:
--   { actions, keymap_fzf, source, opts }
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

  -- Snapshot the captured state before teardown.
  local cap = {
    actions = last_captured.actions or {},
    keymap_fzf = last_captured.keymap_fzf or {},
    keymap_builtin = last_captured.keymap_builtin or {},
    source = last_captured.source,
    opts = last_captured.opts,
  }

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

  return cap
end

-- ── call_action helper ────────────────────────────────────────────────────────

-- Call an action by key from either cap.actions or cap.keymap_fzf.
-- For actions: calls { fn = ..., desc = ... }.fn(selected, opts)
-- For keymap_fzf: the value may be a string bind or {bind_str, desc=...};
--   we just verify it is registered (string or table), not call it
--   (fzf-native binds like "change-preview-window(…)" run inside fzf, not Lua).
local function call_action(cap, key, selected, opts)
  local a = cap.actions[key]
  if a and type(a) == 'table' and type(a.fn) == 'function' then
    a.fn(selected or {}, opts or {})
    return true
  end
  return false
end

-- Return true when the key is registered in either actions or keymap_fzf.
local function has_bind(cap, key)
  if cap.actions[key] ~= nil then
    return true
  end
  if cap.keymap_fzf[key] ~= nil then
    return true
  end
  return false
end

-- ── RG picker tests ───────────────────────────────────────────────────────────

T.group('rg: default action opens file at correct line and column', function()
  reset_buf()
  local path = make_file('rg_basic.lua', { 'line one', 'line two', 'target here', 'line four' })
  local kwargs = {}
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  local entry = path .. ':3:5:target here'
  T.ok(type(cap.actions['default']) == 'table', 'default action is registered')
  call_action(cap, 'default', { entry })

  T.eq(vim.fn.expand('%:p'), path, 'correct file opened')
  T.eq(vim.api.nvim_win_get_cursor(0)[1], 3, 'cursor at line 3')
  T.eq(vim.api.nvim_win_get_cursor(0)[2] + 1, 5, 'cursor at col 5 (1-indexed)')
end)

T.group('rg: default action multi-select populates quickfix', function()
  vim.fn.setqflist({})
  local path = make_file('rg_qf.lua', { 'alpha', 'beta', 'gamma' })
  local kwargs = {}
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  local entries = {
    path .. ':1:1:alpha',
    path .. ':2:1:beta',
    path .. ':3:1:gamma',
  }
  call_action(cap, 'default', entries)

  local qf = vim.fn.getqflist()
  T.ok(#qf >= 2, 'quickfix has entries for multi-select (got ' .. tostring(#qf) .. ')')
end)

T.group('rg: yank action copies matched text to register', function()
  local path = make_file('rg_yank.lua', { 'hello world' })
  local kwargs = {}
  local config = require('siefe.config')
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  local entry = path .. ':1:1:hello world'
  T.ok(type(cap.actions[config.rg_yank_key]) == 'table', 'yank action registered')
  call_action(cap, config.rg_yank_key, { entry })
  T.eq(vim.fn.getreg('"'), 'hello world', 'yank registers matched text')
end)

T.group('rg: word toggle sets kwargs.word on/off', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  T.ok(cap.actions[config.rg_word_key] ~= nil, 'word toggle action registered')
  T.ok(not kwargs.word, 'word initially false')
  call_action(cap, config.rg_word_key)
  T.ok(kwargs.word == true, 'first toggle → word = true')
  call_action(cap, config.rg_word_key)
  T.ok(kwargs.word == false, 'second toggle → word = false')
end)

T.group('rg: case toggle cycles 1 (smart) → 2 (ignore) → 0 (sensitive)', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  -- Default case_sensitive = 1 (smart)
  T.eq(kwargs.case_sensitive, 1, 'initial case_sensitive = 1 (smart)')
  call_action(cap, config.rg_case_key)
  T.eq(kwargs.case_sensitive, 2, 'after 1 toggle → 2 (ignore-case)')
  call_action(cap, config.rg_case_key)
  T.eq(kwargs.case_sensitive, 0, 'after 2 toggles → 0 (case-sensitive)')
  call_action(cap, config.rg_case_key)
  T.eq(kwargs.case_sensitive, 1, 'after 3 toggles → back to 1 (smart)')
end)

T.group('rg: hidden toggle sets kwargs.hidden', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  T.ok(not kwargs.hidden, 'hidden initially false')
  call_action(cap, config.rg_hidden_key)
  T.ok(kwargs.hidden == true, 'hidden toggle → true')
end)

T.group('rg: no-ignore toggle cycles 0 → 1 → 2 → 3 → 0', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  T.eq(kwargs.no_ignore, 0, 'no_ignore initially 0')
  call_action(cap, config.rg_no_ignore_key)
  T.eq(kwargs.no_ignore, 1, 'after 1 toggle → 1 (-u)')
  call_action(cap, config.rg_no_ignore_key)
  T.eq(kwargs.no_ignore, 2, 'after 2 toggles → 2 (-uu)')
  call_action(cap, config.rg_no_ignore_key)
  T.eq(kwargs.no_ignore, 3, 'after 3 toggles → 3 (-uuu)')
  call_action(cap, config.rg_no_ignore_key)
  T.eq(kwargs.no_ignore, 0, 'after 4 toggles → back to 0')
end)

T.group('rg: vdiffsplit action opens file in vertical diffsplit', function()
  reset_buf()
  local path = make_file('rg_diff.lua', { 'diff line 1', 'diff line 2' })
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  local win_before = #vim.api.nvim_list_wins()
  local entry = path .. ':1:1:diff line 1'
  T.ok(type(cap.actions[config.vdiffsplit_key]) == 'table', 'vdiffsplit action registered')
  call_action(cap, config.vdiffsplit_key, { entry })
  T.ok(#vim.api.nvim_list_wins() > win_before, 'vdiffsplit opened a new window')
  vim.cmd('only!')
end)

T.group('rg: toggle_preview_key registered in keymap.builtin with Neovim notation', function()
  local config = require('siefe.config')
  local utils = require('siefe.utils')
  local keys = utils.builtin_toggle_keys(config.toggle_preview_key)
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end)
  -- toggle_preview_key must be in Neovim notation in keymap.builtin.
  -- For ctrl-/, both <C-/> (CSI-u terminals) and <C-_> (standard terminals)
  -- are registered for cross-terminal compatibility.
  for _, nk in ipairs(keys) do
    T.ok(
      cap.keymap_builtin[nk] == 'toggle-preview',
      'toggle_preview_key registered in keymap.builtin as toggle-preview (' .. nk .. ')'
    )
  end
  T.ok(
    cap.keymap_builtin[config.toggle_preview_key] == nil,
    'fzf-notation key not present in keymap.builtin (would silently fail)'
  )
  T.ok(
    cap.keymap_fzf[config.toggle_preview_key] == nil,
    'toggle_preview_key not in keymap.fzf for builtin-previewer picker'
  )
end)

T.group('rg: fixed-strings toggle sets kwargs.fixed_strings', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, kwargs)
  end)

  T.ok(not kwargs.fixed_strings, 'fixed_strings initially false')
  call_action(cap, config.rg_fixed_strings_key)
  T.ok(kwargs.fixed_strings == true, 'toggle → fixed_strings = true')
  call_action(cap, config.rg_fixed_strings_key)
  T.ok(kwargs.fixed_strings == false, 'second toggle → fixed_strings = false')
end)

-- ── History picker tests ──────────────────────────────────────────────────────

T.group('history: default action opens file at saved line and column', function()
  reset_buf()
  local path = make_file('hist_action.lua', { 'a', 'b', 'saved line', 'd', 'e' })
  local history_m = require('siefe.history')
  -- Build a valid history entry using the module's own format
  local entry = history_m._test.make_history_entry(3, 2, path)

  local kwargs = {}
  local cap = capture(function()
    require('siefe.history').historyoldfiles(false, kwargs)
  end)

  T.ok(type(cap.actions['default']) == 'table', 'default action registered')
  call_action(cap, 'default', { entry })

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
  local cap = capture(function()
    require('siefe.history').historyoldfiles(false, kwargs)
  end)

  call_action(cap, 'default', { e1, e2 })
  local qf = vim.fn.getqflist()
  T.ok(#qf >= 2, 'multi-select populates quickfix (' .. tostring(#qf) .. ' entries)')
end)

T.group('history: project toggle flips kwargs.project', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.history').historyoldfiles(false, kwargs)
  end)

  T.ok(not kwargs.project, 'project initially false')
  T.ok(type(cap.actions[config.history_git_key]) == 'table', 'project toggle registered')
  call_action(cap, config.history_git_key)
  T.ok(kwargs.project == true, 'toggle sets kwargs.project = true')
end)

T.group('history: split action opens file in a new window', function()
  reset_buf()
  local path = make_file('hist_split.lua', { 'split content' })
  local history_m = require('siefe.history')
  local entry = history_m._test.make_history_entry(1, 1, path)
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.history').historyoldfiles(false, kwargs)
  end)

  local win_before = #vim.api.nvim_list_wins()
  T.ok(type(cap.actions[config.split_key]) == 'table', 'split action registered')
  call_action(cap, config.split_key, { entry })
  T.ok(#vim.api.nvim_list_wins() > win_before, 'split opened a new window')
  vim.cmd('only!')
end)

T.group('history: delete action registered when history_delete_key is configured', function()
  -- history_delete_key is in config.lua but the history picker does not
  -- currently implement a delete action — verify only that the key exists
  -- in config so that future implementation has a stable default key.
  local config = require('siefe.config')
  T.ok(type(config.history_delete_key) == 'string' and config.history_delete_key ~= '', 'history_delete_key is a non-empty string in config')
  T.eq(config.history_delete_key, 'del', 'default history_delete_key is del')
end)

-- ── Buffers picker tests ──────────────────────────────────────────────────────

T.group('buffers: default action switches to the selected buffer', function()
  local path = make_file('buf_switch.txt', { 'buffer content' })
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local target_buf = vim.api.nvim_get_current_buf()
  reset_buf() -- switch away from target_buf

  T.ok(vim.api.nvim_get_current_buf() ~= target_buf, 'not on target buffer initially')

  local cap = capture(function()
    require('siefe.buffers').buffers(false, {})
  end)

  -- Find the entry for target_buf in the captured source.
  local target_entry
  for _, e in ipairs(cap.source or {}) do
    if e:match('%[' .. tostring(target_buf) .. '%]') then
      target_entry = e
      break
    end
  end

  T.ok(target_entry ~= nil, 'target buffer has an entry in picker source')
  T.ok(type(cap.actions['default']) == 'table', 'default action registered')
  call_action(cap, 'default', { target_entry })
  T.eq(vim.api.nvim_get_current_buf(), target_buf, 'switched to target buffer')
end)

T.group('buffers: delete action removes the buffer', function()
  local path = make_file('buf_delete.txt', { 'will be deleted' })
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local del_buf = vim.api.nvim_get_current_buf()
  reset_buf() -- leave del_buf so it is listed but not current

  T.ok(vim.fn.buflisted(del_buf) == 1, 'buffer is listed before delete')

  local cap = capture(function()
    require('siefe.buffers').buffers(false, {})
  end)

  local del_entry
  for _, e in ipairs(cap.source or {}) do
    if e:match('%[' .. tostring(del_buf) .. '%]') then
      del_entry = e
      break
    end
  end

  T.ok(del_entry ~= nil, 'buffer-to-delete has an entry in source')
  local config = require('siefe.config')
  T.ok(type(cap.actions[config.buffers_delete_key]) == 'table', 'delete action registered')
  call_action(cap, config.buffers_delete_key, { del_entry })
  T.eq(vim.fn.buflisted(del_buf), 0, 'buffer is no longer listed after delete')
end)

T.group('buffers: project toggle flips kwargs.project', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.buffers').buffers(false, kwargs)
  end)

  T.ok(not kwargs.project, 'project initially false')
  T.ok(type(cap.actions[config.buffers_git_key]) == 'table', 'project toggle registered')
  call_action(cap, config.buffers_git_key)
  T.ok(kwargs.project == true, 'toggle sets kwargs.project = true')
end)

T.group('buffers: toggle_preview_key registered in keymap.builtin with Neovim notation', function()
  local config = require('siefe.config')
  local utils = require('siefe.utils')
  local keys = utils.builtin_toggle_keys(config.toggle_preview_key)
  local cap = capture(function()
    require('siefe.buffers').buffers(false, {})
  end)
  for _, nk in ipairs(keys) do
    T.ok(
      cap.keymap_builtin[nk] == 'toggle-preview',
      'toggle_preview_key in keymap.builtin (' .. nk .. ') for buffers picker'
    )
  end
  T.ok(
    cap.keymap_builtin[config.toggle_preview_key] == nil,
    'fzf-notation key not present in keymap.builtin'
  )
  T.ok(
    cap.keymap_fzf[config.toggle_preview_key] == nil,
    'toggle_preview_key not in keymap.fzf for builtin-previewer picker'
  )
end)

-- ── Git log picker tests ──────────────────────────────────────────────────────

T.group('git_log: S/G toggle flips kwargs.G', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.git_log').gitlogfzf(false, kwargs)
  end)

  local initial_G = kwargs.G
  T.ok(type(cap.actions[config.gitlog_sg_key]) == 'table', 'S/G toggle registered')
  call_action(cap, config.gitlog_sg_key, {}, { last_query = 'testquery' })
  T.ok(kwargs.G ~= initial_G, 'S/G toggle flips kwargs.G')
end)

T.group('git_log: ignore_case toggle flips kwargs.ignore_case', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.git_log').gitlogfzf(false, kwargs)
  end)

  local initial_ic = kwargs.ignore_case
  T.ok(type(cap.actions[config.gitlog_ignore_case_key]) == 'table', 'ignore_case toggle registered')
  call_action(cap, config.gitlog_ignore_case_key, {}, { last_query = '' })
  T.ok(kwargs.ignore_case ~= initial_ic, 'ignore_case toggled')
end)

T.group('git_log: follow toggle flips kwargs.follow', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.git_log').gitlogfzf(false, kwargs)
  end)

  local initial_follow = kwargs.follow
  T.ok(type(cap.actions[config.gitlog_follow_key]) == 'table', 'follow toggle registered')
  call_action(cap, config.gitlog_follow_key, {}, { last_query = '' })
  T.ok(kwargs.follow ~= initial_follow, 'follow toggled')
end)

T.group('git_log: pickaxe_regex toggle flips kwargs.regex', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.git_log').gitlogfzf(false, kwargs)
  end)

  local initial_regex = kwargs.regex
  T.ok(type(cap.actions[config.gitlog_pickaxe_regex_key]) == 'table', 'regex toggle registered')
  call_action(cap, config.gitlog_pickaxe_regex_key, {}, { last_query = '' })
  T.ok(kwargs.regex ~= initial_regex, 'regex toggled')
end)

T.group('git_log: F7 preview cycle key registered in keymap.fzf', function()
  local config = require('siefe.config')
  local cap = capture(function()
    require('siefe.git_log').gitlogfzf(false, {})
  end)
  T.ok(
    cap.keymap_fzf[config.gitlog_preview_cycle_key] ~= nil,
    'F7 preview cycle key in keymap.fzf'
  )
end)

T.group('git_log: fzf-mode key registered in keymap.fzf', function()
  local config = require('siefe.config')
  local cap = capture(function()
    require('siefe.git_log').gitlogfzf(false, {})
  end)
  T.ok(cap.keymap_fzf[config.gitlog_fzf_key] ~= nil, 'gitlog_fzf_key in keymap.fzf')
end)

-- ── Git status picker tests ───────────────────────────────────────────────────

T.group('git_status: uno toggle flips kwargs.uno', function()
  local config = require('siefe.config')
  local kwargs = {}
  local cap = capture(function()
    require('siefe.git_status').gitstatus(false, kwargs)
  end)

  T.ok(not kwargs.uno, 'uno initially false')
  T.ok(type(cap.actions[config.gitstatus_uno_key]) == 'table', 'uno toggle registered')
  call_action(cap, config.gitstatus_uno_key)
  T.ok(kwargs.uno == true, 'toggle sets kwargs.uno = true')
end)

T.group('git_status: add action registered under gitstatus_add_key', function()
  local config = require('siefe.config')
  local cap = capture(function()
    require('siefe.git_status').gitstatus(false, {})
  end)
  T.ok(type(cap.actions[config.gitstatus_add_key]) == 'table', 'add action registered')
end)

T.group('git_status: restore action registered under gitstatus_restore_key', function()
  local config = require('siefe.config')
  local cap = capture(function()
    require('siefe.git_status').gitstatus(false, {})
  end)
  T.ok(type(cap.actions[config.gitstatus_restore_key]) == 'table', 'restore action registered')
end)

T.group('git_status: preview keys registered in keymap.fzf', function()
  local config = require('siefe.config')
  local cap = capture(function()
    require('siefe.git_status').gitstatus(false, {})
  end)
  T.ok(
    cap.keymap_fzf[config.gitstatus_preview_0_key] ~= nil,
    'gitstatus_preview_0_key in keymap.fzf'
  )
  T.ok(
    cap.keymap_fzf[config.gitstatus_preview_1_key] ~= nil,
    'gitstatus_preview_1_key in keymap.fzf'
  )
end)

-- ── Config / custom shortcuts tests ──────────────────────────────────────────

T.group('config: default rg_word_key is ctrl-w', function()
  local config = require('siefe.config')
  T.eq(config.rg_word_key, 'ctrl-w', 'default rg_word_key is ctrl-w')

  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end)
  T.ok(type(cap.actions['ctrl-w']) == 'table', 'ctrl-w wired to word toggle in rg actions')
end)

T.group('config: custom rg_word_key changes the action key', function()
  -- Custom config: move word toggle from ctrl-w to alt-w
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end, { rg_word_key = 'alt-w' })

  T.ok(type(cap.actions['alt-w']) == 'table', 'alt-w is now the word toggle action')
  T.ok(cap.actions['ctrl-w'] == nil, 'ctrl-w is no longer the word toggle action')
end)

T.group('config: custom split_key changes rg and history actions', function()
  -- Use ctrl-z as the custom split key
  local rg_cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end, { split_key = 'ctrl-z' })

  T.ok(type(rg_cap.actions['ctrl-z']) == 'table', 'rg: ctrl-z is the split action')
  T.ok(rg_cap.actions['ctrl-]'] == nil, 'rg: ctrl-] no longer registered for split')

  local hist_cap = capture(function()
    require('siefe.history').historyoldfiles(false, {})
  end, { split_key = 'ctrl-z' })

  T.ok(type(hist_cap.actions['ctrl-z']) == 'table', 'history: ctrl-z is the split action')
  T.ok(hist_cap.actions['ctrl-]'] == nil, 'history: ctrl-] no longer registered for split')
end)

T.group('config: custom rg_case_key changes case toggle action', function()
  local cap = capture(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end, { rg_case_key = 'alt-c' })

  T.ok(type(cap.actions['alt-c']) == 'table', 'alt-c is the case toggle action')
  T.ok(cap.actions['ctrl-s'] == nil, 'ctrl-s no longer the case toggle')
end)

T.group('config: history_git_key (project toggle) default is ctrl-g', function()
  local config = require('siefe.config')
  T.eq(config.history_git_key, 'ctrl-g', 'default history_git_key is ctrl-g')

  local cap = capture(function()
    require('siefe.history').historyoldfiles(false, {})
  end)
  T.ok(type(cap.actions['ctrl-g']) == 'table', 'ctrl-g is the project toggle in history')
end)

T.group('config: custom gitlog_preview_cycle_key moves F7 to F8', function()
  local cap = capture(function()
    require('siefe.git_log').gitlogfzf(false, {})
  end, { gitlog_preview_cycle_key = 'f8' })

  T.ok(cap.keymap_fzf['f8'] ~= nil, 'f8 is now the preview cycle key in keymap.fzf')
  T.ok(cap.keymap_fzf['f7'] == nil, 'f7 is no longer the preview cycle key')
end)

T.group('config: custom gitstatus_uno_key changes uno toggle', function()
  local kwargs = {}
  local cap = capture(function()
    require('siefe.git_status').gitstatus(false, kwargs)
  end, { gitstatus_uno_key = 'alt-u' })

  T.ok(type(cap.actions['alt-u']) == 'table', 'alt-u is the uno toggle action')
  T.ok(cap.actions['ctrl-n'] == nil, 'ctrl-n no longer uno toggle')
end)

-- ── Cleanup ───────────────────────────────────────────────────────────────────

vim.fn.delete(tmpdir, 'rf')

T.finish()
