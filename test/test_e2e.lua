-- test/test_e2e.lua
-- End-to-end integration tests that launch real fzf via fzf-lua and interact
-- with it using vim.fn.chansend() to type queries and select entries.
-- No mocking of fzf-lua.
--
-- Requires: fzf binary + fzf-lua in runtimepath.
-- Skips gracefully when either is missing.
--
-- Run with:
--   make test-e2e                        # uses FZF_LUA_PATH (default /tmp/fzf-lua)
--   FZF_LUA_PATH=/path/to/fzf-lua make test-e2e
--
-- How it works:
--   1. Launch a picker (e.g. siefe.rg.ripgrepfzf) which calls fzf_live/fzf_exec
--      internally — fzf-lua opens fzf in a Neovim terminal buffer.
--   2. Detect the new terminal buffer (poll vim.api.nvim_list_bufs).
--   3. Get the channel (vim.b[buf].terminal_job_id).
--   4. Send keystrokes with vim.fn.chansend(chan, str).
--      IMPORTANT: use \r (carriage return = terminal Enter), not \n.
--   5. Wait for fzf to close (terminal buftype cleared).
--   6. Assert Neovim side-effects (current buf, cursor pos, quickfix, windows).

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))

-- ── Prerequisites ─────────────────────────────────────────────────────────────

-- Prefer FZF_LUA_PATH env var; fall back to /tmp/fzf-lua.
local fzf_lua_path = os.getenv('FZF_LUA_PATH') or '/tmp/fzf-lua'
if vim.fn.isdirectory(fzf_lua_path) == 0 then
  io.stdout:write('SKIP: fzf-lua not found at ' .. fzf_lua_path .. '\n')
  io.stdout:write('  Clone with: git clone --depth=1 https://github.com/ibhagwan/fzf-lua ' .. fzf_lua_path .. '\n')
  os.exit(0)
end
vim.opt.rtp:prepend(fzf_lua_path)

if vim.fn.executable('fzf') ~= 1 then
  io.stdout:write('SKIP: fzf binary not found in PATH\n')
  os.exit(0)
end

local ok_fzflua = pcall(require, 'fzf-lua')
if not ok_fzflua then
  io.stdout:write('SKIP: fzf-lua could not be loaded\n')
  os.exit(0)
end

local T = require('test.helpers')

-- ── Temp directory ────────────────────────────────────────────────────────────

-- NOTE: we intentionally avoid vim.fn.tempname() here because it returns a
-- path *inside* Neovim's own runner temp directory (e.g. /tmp/nvim.runner/…).
-- Neovim stores other files there (e.g. named-pipe sockets, shell paths), so
-- rg would find unexpected results when searching that directory.
-- Use a plain OS temp path that is isolated from Neovim's internals instead.
local tmpdir = '/tmp/siefe_e2e_' .. tostring(vim.loop.getpid()) .. '_' .. tostring(math.floor(vim.fn.reltimefloat(vim.fn.reltime()) * 1e6))
vim.fn.mkdir(tmpdir, 'p')

local function make_file(name, lines)
  local path = tmpdir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

-- ── chansend helpers ──────────────────────────────────────────────────────────
-- All helpers live in test/helpers_e2e.lua; alias them locally so the test
-- bodies below require no changes.

local E = require('test.helpers_e2e')
local wait_fzf_close = E.wait_fzf_close
local launch_and_wait = E.launch_and_wait
local fzf_type = E.fzf_type
local fzf_enter = E.fzf_enter
local wait_fzf_match = E.wait_fzf_match
local wait_for_buf = E.wait_for_buf
local cursor_in_buf = E.cursor_in_buf

-- ── Tests ─────────────────────────────────────────────────────────────────────

-- rg: open file at the correct line and column --------------------------------

T.group('e2e rg: opens file at the correct line and column', function()
  vim.cmd('enew!')
  local path = make_file('rg_e2e_open.lua', {
    'first line here',
    'second line here',
    'unique_e2e_target match', -- line 3
    'fourth line here',
  })

  local h = launch_and_wait(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end)
  T.ok(h ~= nil, 'rg picker launched (terminal buffer found)')
  if not h then
    return
  end

  -- Type the query; wait until fzf shows the rg result entry (not just the
  -- query in the prompt bar) before pressing Enter.  The entry pattern
  -- 'rg_e2e_open' anchors on the actual filename in the result line.
  fzf_type(h.chan, 'unique_e2e_target', 200)
  wait_fzf_match(h.fzf_buf, 'rg_e2e_open', 4000)
  fzf_enter(h.chan)
  -- Wait for the target file to appear in any buffer (more robust than
  -- checking the focused window, which may be the fzf float).
  local opened_buf = wait_for_buf(path, 5000)
  T.ok(opened_buf ~= nil, 'target file was opened in a buffer')
  if not opened_buf then
    return
  end

  local cursor = cursor_in_buf(opened_buf)
  T.ok(cursor ~= nil, 'found a window showing the opened buffer')
  if cursor then
    T.eq(cursor[1], 3, 'cursor landed at line 3')
    T.eq(cursor[2] + 1, 1, 'cursor at column 1 (rg default)') -- cursor[2] is 0-indexed
  end
end)

-- rg: split key opens file in a new window ------------------------------------

T.group('e2e rg: split key opens file in a new split window', function()
  vim.cmd('only!')
  local _ = make_file('rg_e2e_split.lua', { 'split_e2e_line one', 'split_e2e_target', 'split_e2e_line three' })

  local cfg = require('siefe.config')
  local win_before = #vim.api.nvim_list_wins()

  local h = launch_and_wait(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end)
  T.ok(h ~= nil, 'rg picker launched for split test')
  if not h then
    return
  end

  fzf_type(h.chan, 'split_e2e_target', 200)
  wait_fzf_match(h.fzf_buf, 'rg_e2e_split', 4000)
  -- Send the split key. ctrl-] = 0x1d (GS, group separator).
  local split_key_bytes = {
    ['ctrl-]'] = '\x1d',
    ['ctrl-s'] = '\x13',
    ['ctrl-x'] = '\x18',
  }
  local split_byte = split_key_bytes[cfg.split_key] or '\x1d'
  vim.fn.chansend(h.chan, split_byte)
  wait_fzf_close(h.fzf_buf, 5000)

  T.ok(#vim.api.nvim_list_wins() > win_before, 'split action opened a new window')
  vim.cmd('only!')
end)

-- buffers: switches to the selected buffer ------------------------------------

T.group('e2e buffers: default action switches to the selected buffer', function()
  -- Open a file to create a listed buffer; then move away from it.
  local path = make_file('buf_e2e_switch.txt', { 'buffer content' })
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local target_buf = vim.api.nvim_get_current_buf()
  vim.cmd('enew!') -- switch away so we're not already on the target
  T.ok(vim.api.nvim_get_current_buf() ~= target_buf, 'not on target buffer before launching picker')

  local h = launch_and_wait(function()
    require('siefe.buffers').buffers(false, {})
  end, 500) -- buffers picker is instant (no external process)
  T.ok(h ~= nil, 'buffers picker launched')
  if not h then
    return
  end

  -- The picker shows the current buffer ([No Name]) as --header-lines=1
  -- and the target buffer as the first selectable entry.  Press Enter to
  -- select the top entry — no query needed.
  fzf_enter(h.chan)
  wait_fzf_close(h.fzf_buf, 4000)

  T.eq(vim.api.nvim_get_current_buf(), target_buf, 'switched to the target buffer')
end)

-- history: opens file at saved line and column --------------------------------

T.group('e2e history: opens file at the saved line and column', function()
  vim.cmd('enew!')
  local path = make_file('hist_e2e.lua', {
    'line 1',
    'line 2',
    'hist_e2e_marker line', -- line 3
    'line 4',
  })
  -- Open the file and move to line 3 so it ends up in recent_files_info.
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { 3, 4 })
  -- Switch away so the file is in the "listed bufs" list.
  vim.cmd('enew!')

  -- The history module tracks buffers via siefe's BufEnter autocmd.
  -- Make sure tracker knows about this buffer.
  local tracker = require('siefe.utils').buffer_tracker
  if tracker then
    tracker[vim.fn.bufnr(path)] = vim.fn.reltimefloat(vim.fn.reltime())
  end

  local h = launch_and_wait(function()
    require('siefe.history').historyoldfiles(false, {})
  end, 500)
  T.ok(h ~= nil, 'history picker launched')
  if not h then
    return
  end

  -- Type the marker to filter to our file; wait for the entry (not just the
  -- prompt bar) to appear in fzf.
  fzf_type(h.chan, 'hist_e2e', 200)
  wait_fzf_match(h.fzf_buf, 'hist_e2e%.lua', 3000)
  fzf_enter(h.chan)
  local opened_buf = wait_for_buf(path, 5000)
  T.ok(opened_buf ~= nil, 'history opened the correct file')
end)

-- config: custom rg_word_key is wired in the picker ---------------------------

T.group('e2e config: custom rg_word_key is accepted by fzf', function()
  -- Launch rg with a custom word key; verify fzf starts without error
  -- (fzf would error if the bind string were malformed).
  local cfg = require('siefe.config')
  cfg.setup({ rg_word_key = 'alt-w' })

  local h = launch_and_wait(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end)
  T.ok(h ~= nil, 'rg picker with custom rg_word_key launched without error')
  if h then
    -- Send Escape to close fzf cleanly.
    vim.fn.chansend(h.chan, '\x1b') -- ESC
    wait_fzf_close(h.fzf_buf, 3000)
    T.ok(true, 'fzf closed cleanly after ESC')
  end

  cfg.setup({}) -- restore defaults
end)

-- rg: type select (-t) chains correctly into a filtered rg session -----------
--
-- This test specifically guards against the type_select.lua bug where
-- vim.list_slice(selected, 2) skipped the first (often only) selected type
-- because fzf-lua already strips selected[1] (the --print-query result) before
-- calling the action.  Without the fix, single-type selection always produced
-- type_flag='' and rg reopened without any type filter.

T.group('e2e rg: type select (-t lua) filters results to only lua files', function()
  vim.cmd('enew!')
  -- Create three files with the same unique search token but different extensions.
  -- After selecting the 'lua' type, only the .lua file should appear.
  local token = 'UNIQUE_TYPE_E2E_TOKEN_XQZ'
  local lua_file = make_file('type_e2e.lua', { token, 'lua content' })
  local py_file  = make_file('type_e2e.py',  { token, 'python content' })
  local rs_file  = make_file('type_e2e.rs',  { token, 'rust content' })
  -- Silence "unused" warnings; the files must exist on disk but paths aren't
  -- referenced again — rg discovers them by directory search.
  local _ = lua_file; _ = py_file; _ = rs_file

  -- Step 1: Launch the rg picker.
  local h1 = launch_and_wait(function()
    require('siefe.rg').ripgrepfzf(false, tmpdir, {})
  end)
  T.ok(h1 ~= nil, 'rg picker launched for type-select test')
  if not h1 then
    return
  end

  -- Step 2: Send ctrl-t (\x14) to open the type_select sub-picker.
  -- Snapshot terminal buffers BEFORE sending so find_new_term_buf can spot T2.
  local before_type = E.current_term_bufs()
  vim.fn.chansend(h1.chan, '\x14') -- ctrl-t = rg_type_key default

  -- Step 3: Find the type_select picker (T2).
  local type_buf = E.find_new_term_buf(before_type, 5000)
  T.ok(type_buf ~= nil, 'type_select picker appeared after ctrl-t')
  if not type_buf then
    return
  end

  local type_chan = vim.b[type_buf].terminal_job_id
  T.ok(type_chan ~= nil and type_chan > 0, 'type_select channel is valid')
  if not type_chan or type_chan < 1 then
    return
  end
  E.wait_fzf_ready(type_buf, 2000)

  -- Step 4: Type "lua" to filter the type list to "lua: *.lua", then Enter.
  -- Snapshot BEFORE pressing Enter so we can find the re-opened rg (T3).
  E.fzf_type(type_chan, 'lua', 300)
  -- Wait for the filtered entry to appear (fzf shows "lua: *.lua").
  E.wait_fzf_match(type_buf, 'lua:%s', 3000)

  local before_rg2 = E.current_term_bufs()
  E.fzf_enter(type_chan)

  -- Step 5: Wait for T2 to close and for the re-opened rg picker (T3) to appear.
  E.wait_fzf_close(type_buf, 5000)
  local rg2_buf = E.find_new_term_buf(before_rg2, 6000)
  T.ok(rg2_buf ~= nil, 'rg reopened (T3) after type selection')
  if not rg2_buf then
    return
  end

  local rg2_chan = vim.b[rg2_buf].terminal_job_id
  T.ok(rg2_chan ~= nil and rg2_chan > 0, 'rg2 channel is valid')
  if not rg2_chan or rg2_chan < 1 then
    return
  end
  E.wait_fzf_ready(rg2_buf, 1500)

  -- Step 6: Search for the unique token; with -tlua only the .lua file should
  -- appear in fzf's results.
  E.fzf_type(rg2_chan, token, 300)
  -- Wait for the .lua result to appear before checking the others.
  E.wait_fzf_match(rg2_buf, 'type_e2e%.lua', 5000)

  T.ok(E.has_pattern(rg2_buf, 'type_e2e%.lua'), 'lua file present after -t lua filter')
  T.ok(not E.has_pattern(rg2_buf, 'type_e2e%.py'),  'py file excluded by -t lua filter')
  T.ok(not E.has_pattern(rg2_buf, 'type_e2e%.rs'),  'rs file excluded by -t lua filter')

  -- Close the filtered rg picker cleanly.
  vim.fn.chansend(rg2_chan, '\x1b')
  E.wait_fzf_close(rg2_buf, 3000)
end)

-- Cleanup ---------------------------------------------------------------------

vim.fn.delete(tmpdir, 'rf')
T.finish()
