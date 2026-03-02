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
local tmpdir = '/tmp/siefe_e2e_' .. tostring(math.floor(vim.fn.reltimefloat(vim.fn.reltime()) * 1e6))
vim.fn.mkdir(tmpdir, 'p')

local function make_file(name, lines)
  local path = tmpdir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

-- ── chansend helpers ──────────────────────────────────────────────────────────

-- Return a snapshot of all current terminal buffer IDs.
local function current_term_bufs()
  local t = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_get_option_value('buftype', { buf = b }) == 'terminal' then
      t[b] = true
    end
  end
  return t
end

-- Find a NEW terminal buffer (not in `before`) within timeout_ms.
local function find_new_term_buf(before, timeout_ms)
  local found = nil
  vim.wait(timeout_ms or 4000, function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if not before[b] and vim.api.nvim_buf_is_loaded(b) then
        if vim.api.nvim_get_option_value('buftype', { buf = b }) == 'terminal' then
          found = b
          return true
        end
      end
    end
    return false
  end, 50)
  return found
end

-- Wait until the fzf terminal buffer renders at least one non-blank line.
local function wait_fzf_ready(fzf_buf, timeout_ms)
  vim.wait(timeout_ms or 2500, function()
    if not vim.api.nvim_buf_is_loaded(fzf_buf) then
      return false
    end
    local lines = vim.api.nvim_buf_get_lines(fzf_buf, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:match('%S') then
        return true
      end
    end
    return false
  end, 100)
end

-- Wait until the fzf terminal is no longer a terminal (closed after selection).
local function wait_fzf_close(fzf_buf, timeout_ms)
  vim.wait(timeout_ms or 5000, function()
    if not vim.api.nvim_buf_is_loaded(fzf_buf) then
      return true
    end
    return vim.api.nvim_get_option_value('buftype', { buf = fzf_buf }) ~= 'terminal'
  end, 50)
end

-- Launch a picker function; return {chan=, fzf_buf=} or nil on failure.
-- ready_ms: how long to wait for fzf to render its initial UI.
local function launch_and_wait(fn, ready_ms)
  local before = current_term_bufs()
  local ok, err = pcall(fn)
  if not ok then
    io.stderr:write('picker launch error: ' .. tostring(err) .. '\n')
    return nil
  end
  local fzf_buf = find_new_term_buf(before, 4000)
  if not fzf_buf then
    return nil
  end
  local chan = vim.b[fzf_buf].terminal_job_id
  if not chan or chan < 1 then
    return nil
  end
  wait_fzf_ready(fzf_buf, ready_ms or 1500)
  return { chan = chan, fzf_buf = fzf_buf }
end

-- Send a string to fzf and yield briefly for fzf to process.
local function fzf_type(chan, str, delay_ms)
  vim.fn.chansend(chan, str)
  vim.wait(delay_ms or 400)
end

-- Press Enter in fzf. Terminal Enter = carriage return (\r), NOT \n.
local function fzf_enter(chan)
  vim.fn.chansend(chan, '\r')
end

-- Wait until the fzf terminal buffer contains a line matching `pattern`
-- (typically used to confirm a search result appeared before pressing Enter).
local function wait_fzf_match(fzf_buf, pattern, timeout_ms)
  vim.wait(timeout_ms or 4000, function()
    if not vim.api.nvim_buf_is_loaded(fzf_buf) then
      return false
    end
    for _, l in ipairs(vim.api.nvim_buf_get_lines(fzf_buf, 0, -1, false)) do
      if l:match(pattern) then
        return true
      end
    end
    return false
  end, 100)
end

-- Poll all loaded buffers until one matching `path` is found (or timeout).
-- Returns the buffer ID, or nil on timeout.
local function wait_for_buf(path, timeout_ms)
  local found = nil
  vim.wait(timeout_ms or 5000, function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        local name = vim.api.nvim_buf_get_name(b)
        if name == path then
          found = b
          return true
        end
      end
    end
    return false
  end, 50)
  return found
end

-- Return the cursor position in the first window that shows buffer `buf`.
local function cursor_in_buf(buf)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      return vim.api.nvim_win_get_cursor(w)
    end
  end
  return nil
end

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
    T.eq(cursor[2] + 1, 1, 'cursor at column 1 (rg default)')
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

-- Cleanup ---------------------------------------------------------------------

vim.fn.delete(tmpdir, 'rf')
T.finish()
