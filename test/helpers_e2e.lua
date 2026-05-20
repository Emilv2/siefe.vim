-- test/helpers_e2e.lua
-- Shared chansend / fzf-terminal helpers for end-to-end tests.
-- Used by test_e2e.lua and test_e2e_gitlog.lua.
--
-- How it works:
--   fzf-lua opens fzf in a Neovim terminal buffer.  We find that buffer,
--   grab its channel, and drive fzf with vim.fn.chansend(chan, bytes).
--   IMPORTANT: terminal Enter = carriage return '\r', not '\n'.

local M = {}

-- Return a snapshot of all current terminal buffer IDs.
function M.current_term_bufs()
  local t = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_get_option_value('buftype', { buf = b }) == 'terminal' then
      t[b] = true
    end
  end
  return t
end

-- Find a NEW terminal buffer (not in `before`) within timeout_ms.
function M.find_new_term_buf(before, timeout_ms)
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
function M.wait_fzf_ready(fzf_buf, timeout_ms)
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
function M.wait_fzf_close(fzf_buf, timeout_ms)
  vim.wait(timeout_ms or 5000, function()
    if not vim.api.nvim_buf_is_loaded(fzf_buf) then
      return true
    end
    return vim.api.nvim_get_option_value('buftype', { buf = fzf_buf }) ~= 'terminal'
  end, 50)
end

-- Launch a picker function; return {chan=, fzf_buf=} or nil on failure.
-- ready_ms: how long to wait for fzf to render its initial UI.
function M.launch_and_wait(fn, ready_ms)
  local before = M.current_term_bufs()
  local ok, err = pcall(fn)
  if not ok then
    io.stderr:write('picker launch error: ' .. tostring(err) .. '\n')
    return nil
  end
  local fzf_buf = M.find_new_term_buf(before, 4000)
  if not fzf_buf then
    return nil
  end
  local chan = vim.b[fzf_buf].terminal_job_id
  if not chan or chan < 1 then
    return nil
  end
  M.wait_fzf_ready(fzf_buf, ready_ms or 1500)
  return { chan = chan, fzf_buf = fzf_buf }
end

-- Send a string to fzf and yield briefly for fzf to process.
-- delay_ms is the minimum time to wait after sending (default 400ms covers fzf
-- UI refresh; set to a smaller value and follow with wait_fzf_match for live rg).
function M.fzf_type(chan, str, delay_ms)
  vim.fn.chansend(chan, str)
  vim.wait(delay_ms or 400)
end

-- Press Enter in fzf. Terminal Enter = carriage return (\r), NOT \n.
function M.fzf_enter(chan)
  vim.fn.chansend(chan, '\r')
end

-- Wait until the fzf terminal buffer contains a line matching `pattern`
-- (typically used to confirm a search result appeared before pressing Enter).
function M.wait_fzf_match(fzf_buf, pattern, timeout_ms)
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

-- Return true if the fzf terminal buffer currently contains a line matching `pattern`.
-- Call after wait_fzf_match to confirm content is (or is not) present.
function M.has_pattern(fzf_buf, pattern)
  if not vim.api.nvim_buf_is_loaded(fzf_buf) then
    return false
  end
  for _, l in ipairs(vim.api.nvim_buf_get_lines(fzf_buf, 0, -1, false)) do
    if l:match(pattern) then
      return true
    end
  end
  return false
end

-- Poll all loaded buffers until one matching `path` is found (or timeout).
-- Returns the buffer ID, or nil on timeout.
function M.wait_for_buf(path, timeout_ms)
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
function M.cursor_in_buf(buf)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      return vim.api.nvim_win_get_cursor(w)
    end
  end
  return nil
end

return M
