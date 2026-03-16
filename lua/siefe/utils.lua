-- lua/siefe/utils.lua
-- Shared utilities for siefe.vim
local M = {}

-- Compatibility shim for vim.list_slice (Neovim < 0.8)
if not vim.list_slice then
  vim.list_slice = function(t, first, last)
    local result = {}
    for i = (first or 1), (last or #t) do
      result[#result + 1] = t[i]
    end
    return result
  end
end

-- ── ANSI colour helpers ──────────────────────────────────────────────────────

local ansi_codes = { black = 30, red = 31, green = 32, yellow = 33, blue = 34, magenta = 35, cyan = 36 }

function M.csi(color, fg)
  local prefix = fg and '38;' or '48;'
  if color:sub(1, 1) == '#' then
    local r = tonumber(color:sub(2, 3), 16)
    local g = tonumber(color:sub(4, 5), 16)
    local b = tonumber(color:sub(6, 7), 16)
    return prefix .. '2;' .. r .. ';' .. g .. ';' .. b
  end
  return prefix .. '5;' .. color
end

function M.get_color(attr, ...)
  local gui = vim.o.termguicolors
  local fam = gui and 'gui' or 'cterm'
  local pat = gui and '^#[a-fA-F0-9]+' or '^%d+$'
  for _, group in ipairs({ ... }) do
    local code = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(group)), attr, fam)
    if code and code:match(pat) then
      return code
    end
  end
  return ''
end

function M.ansi(str, group, default, bold)
  local fg = M.get_color('fg', group)
  local bg = M.get_color('bg', group)
  local color = (fg == '' and tostring(ansi_codes[default] or ansi_codes.magenta) or M.csi(fg, true))
    .. (bg == '' and '' or ';' .. M.csi(bg, false))
  return string.format('\x1b[%s%sm%s\x1b[m', color, bold and ';1' or '', str)
end

function M.magenta(str, group)
  return M.ansi(str, group or '', 'magenta')
end
function M.blue(str, group)
  return M.ansi(str, group or '', 'blue')
end
function M.red(str, group)
  return M.ansi(str, group or '', 'red')
end
function M.green(str, group)
  return M.ansi(str, group or '', 'green')
end
function M.yellow(str, group)
  return M.ansi(str, group or '', 'yellow')
end

-- ── Header helpers ───────────────────────────────────────────────────────────

function M.prettify_help(key)
  return M.magenta(key:upper(), 'Special')
end

function M.prettify_header(key, text)
  local char = vim.split(key, '-')[#vim.split(key, '-')]
  if char == text:sub(1, 1) then
    return M.magenta(key:upper(), 'Special') .. ' ' .. text
  else
    local replaced = text:sub(2):gsub(char, '\x1b[3m' .. char .. '\x1b[m', 1)
    return M.magenta(key:upper(), 'Special') .. ' ' .. text:sub(1, 1) .. replaced
  end
end

function M.preview_help(preview_keys)
  local f_keys, non_f = {}, {}
  for _, k in ipairs(preview_keys) do
    if k:sub(1, 1):lower() == 'f' then
      table.insert(f_keys, tonumber(k:sub(2)) or 0)
    else
      table.insert(non_f, k)
    end
  end
  table.sort(f_keys)
  if #f_keys == 0 then
    return table.concat(
      vim.tbl_map(function(k)
        return ', ' .. k
      end, non_f),
      ''
    )
  end
  local result = ''
  local val_start = f_keys[1]
  local last_val = f_keys[1]
  for i = 2, #f_keys do
    local val = f_keys[i]
    if val ~= last_val + 1 then
      if val_start ~= last_val then
        result = result .. 'f' .. val_start .. '-' .. last_val .. ', '
      else
        result = result .. 'f' .. last_val .. ', '
      end
      val_start = val
    end
    last_val = val
  end
  result = result .. 'f' .. val_start .. '-' .. last_val
  for _, k in ipairs(non_f) do
    result = result .. ', ' .. k
  end
  return result
end

-- ── Quickfix / loclist ───────────────────────────────────────────────────────

function M.fill_quickfix(list, cmd)
  if #list > 1 then
    vim.fn.setqflist(list)
    vim.cmd('copen')
    vim.cmd('wincmd p')
    if cmd then
      vim.cmd(cmd)
    end
  end
end

function M.fill_loc(list, cmd)
  if #list > 1 then
    vim.fn.setloclist(0, list)
    vim.cmd('lopen')
    vim.cmd('wincmd p')
    if cmd then
      vim.cmd(cmd)
    end
  end
end

-- ── Yank ────────────────────────────────────────────────────────────────────

function M.yank_to_register(data)
  vim.fn.setreg('"', data)
  pcall(vim.fn.setreg, '*', data)
  pcall(vim.fn.setreg, '+', data)
end

-- ── Warning ──────────────────────────────────────────────────────────────────

function M.warn(msg)
  vim.api.nvim_echo({ { msg, 'WarningMsg' } }, true, {})
end

-- ── Duplicate key detection ──────────────────────────────────────────────────

function M.detect_dups(lst)
  local dict, dups = {}, {}
  for _, item in ipairs(lst) do
    if dict[item] then
      table.insert(dups, item)
    end
    dict[item] = true
  end
  return table.concat(dups, ' ')
end

-- ── Buffer helpers ───────────────────────────────────────────────────────────

function M.bufdir()
  if vim.bo.filetype == 'git' then
    return vim.fn.FugitiveFind(':/')
  elseif vim.bo.filetype == 'oil' then
    local ok, oil = pcall(require, 'oil')
    if ok then
      return oil.get_current_dir() or vim.fn.expand('%:p:h')
    end
  end
  return vim.fn.expand('%:p:h')
end

function M.get_git_root()
  local ok, result = pcall(vim.fn.FugitiveFind, ':/')
  if ok then
    return result or ''
  end
  return ''
end

function M.get_git_basename_or_bufdir()
  local root = M.get_git_root()
  if root == '' then
    return vim.fn.expand('%:p:h')
  end
  return vim.fn.fnamemodify(root, ':t')
end

function M.get_relative_git_or_bufdir(dir, git_dir)
  local bufdir = M.bufdir()
  if dir == nil then
    -- No argument: return prompt-style relative path for current buffer dir
    local rel = vim.trim(vim.fn.system('git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-prefix'))
    if vim.v.shell_error ~= 0 then
      return bufdir
    end
    local base = vim.split(
      vim.fn.system('basename `git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-toplevel`'),
      '\n'
    )[1]
    return '#' .. base .. '/' .. rel
  else
    -- With argument: return relative path from git root to dir
    local gd = git_dir
      or vim.trim(vim.fn.system('git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-toplevel'))
    if vim.v.shell_error ~= 0 then
      return dir
    end
    local prefix = M.get_git_basename_or_bufdir() .. '/'
    return prefix
      .. vim.trim(vim.fn.system('realpath --relative-to=' .. vim.fn.shellescape(gd) .. ' ' .. vim.fn.shellescape(dir)))
  end
end

-- ── Visual selection ─────────────────────────────────────────────────────────

function M.visual_selection()
  local mode = vim.fn.mode()
  local line_start, col_start, line_end, col_end
  if mode == 'v' then
    line_start, col_start = unpack(vim.fn.getpos('v'), 2, 3)
    line_end, col_end = unpack(vim.fn.getpos('.'), 2, 3)
  else
    line_start, col_start = unpack(vim.fn.getpos("'<"), 2, 3)
    line_end, col_end = unpack(vim.fn.getpos("'>"), 2, 3)
  end
  -- Normalise so start < end
  if (vim.fn.line2byte(line_start) + col_start) > (vim.fn.line2byte(line_end) + col_end) then
    line_start, col_start, line_end, col_end = line_end, col_end, line_start, col_start
  end
  local lines = vim.fn.getline(line_start, line_end)
  if #lines == 0 then
    return ''
  end
  lines[#lines] = lines[#lines]:sub(1, col_end)
  lines[1] = lines[1]:sub(col_start)
  return table.concat(lines, '\n')
end

function M.visual_line_nu()
  local mode = vim.fn.mode()
  local line_start, line_end
  if mode == 'v' then
    line_start = vim.fn.getpos('v')[2]
    line_end = vim.fn.getpos('.')[2]
  else
    line_start = vim.fn.getpos("'<")[2]
    line_end = vim.fn.getpos("'>")[2]
  end
  local t = { line_start, line_end }
  table.sort(t)
  return t
end

-- ── Buffer listing ───────────────────────────────────────────────────────────

-- Returns list of bufnrs sorted by most recently accessed (uses siefe buffer tracker)
function M.buflisted_sorted()
  local tracker = require('siefe').buffers_tracker or {}
  local listed = vim.tbl_filter(function(b)
    return vim.fn.buflisted(b) == 1 and vim.bo[b].filetype ~= 'qf'
  end, vim.api.nvim_list_bufs())
  table.sort(listed, function(a, b)
    local ta = tracker[a] or a
    local tb = tracker[b] or b
    local term_a = vim.bo[a].buftype == 'terminal'
    local term_b = vim.bo[b].buftype == 'terminal'
    if term_a ~= term_b then
      return not term_a -- non-terminals before terminals
    end
    return ta > tb
  end)
  return listed
end

-- ── Recent file helpers ──────────────────────────────────────────────────────

function M.oldfiles()
  -- In Neovim, use v:oldfiles
  local result = {}
  for _, name in ipairs(vim.v.oldfiles or {}) do
    table.insert(result, { name = name, line = 0, column = 0 })
  end
  return result
end

-- deduplicate a list of "prefix//value" strings, keeping first occurrence
local function uniq_with_prefix(lst, prefix)
  local visited, ret = {}, {}
  for _, l in ipairs(lst) do
    local f
    if prefix == '' then
      f = l
    else
      local parts = vim.split(l, prefix, { plain = true })
      f = #parts == 1 and parts[1] or table.concat(vim.list_slice(parts, 2), prefix)
    end
    if f and f ~= '' and not visited[f] then
      table.insert(ret, l)
      visited[f] = true
    end
  end
  return ret
end

function M.recent_files_info()
  local cur = vim.fn.expand('%')
  local cur_line = vim.fn.line('.')
  local items = {}

  -- Current buffer
  if cur ~= '' then
    table.insert(items, cur_line .. '//0//' .. vim.fn.fnamemodify(cur, ':~:.'))
  end

  -- Listed buffers sorted by access time
  for _, b in ipairs(M.buflisted_sorted()) do
    local name = vim.fn.bufname(b)
    if name ~= '' then
      local lnum = (vim.fn.getbufinfo(b)[1] or {}).lnum or 0
      table.insert(items, tostring(lnum) .. '//0//' .. vim.fn.fnamemodify(vim.fn.expand(name), ':~:.'))
    end
  end

  -- v:oldfiles (line=0, col=0 — v:oldfiles carries no position info)
  for _, of in ipairs(M.oldfiles()) do
    if vim.fn.filereadable(vim.fn.fnamemodify(vim.fn.expand(of.name), ':p')) == 1 then
      table.insert(items, '0//0//' .. vim.fn.fnamemodify(vim.fn.expand(of.name), ':~:.'))
    end
  end

  return uniq_with_prefix(items, '//')
end

function M.recent_git_files_info()
  local git_dir = M.get_git_root()
  if git_dir == '' then
    M.warn('not in a git dir')
    return {}
  end

  local items = {}
  local cur = vim.fn.expand('%')
  if cur ~= '' then
    local real = vim.fn.FugitiveReal and vim.fn.FugitiveReal() or vim.fn.expand('%:p')
    table.insert(
      items,
      vim.fn.line('.') .. '//0//' .. real:gsub(git_dir:gsub('[%(%)%.%%%+%-%*%?%[%^%$]', '%%%1') .. '/', '', 1)
    )
  end

  for _, b in ipairs(M.buflisted_sorted()) do
    local name = vim.fn.fnameescape(vim.fn.bufname(b))
    if name ~= '' then
      local full = vim.fn.fnamemodify(vim.fn.expand(name), ':p')
      if full:sub(1, #git_dir) == git_dir then
        local lnum = (vim.fn.getbufinfo(b)[1] or {}).lnum or 0
        table.insert(items, tostring(lnum) .. '//0//' .. full:sub(#git_dir + 2))
      end
    end
  end

  for _, of in ipairs(M.oldfiles()) do
    local full = vim.fn.fnamemodify(vim.fn.expand(vim.fn.fnameescape(of.name)), ':p')
    if vim.fn.filereadable(full) == 1 and full:sub(1, #git_dir) == git_dir then
      -- line=0, col=0: v:oldfiles carries no position info
      table.insert(items, '0//0//' .. full:sub(#git_dir + 2))
    end
  end

  return uniq_with_prefix(items, '//')
end

function M.recent_files(dir)
  local git_dir = M.get_git_root()
  local d = dir or git_dir
  local items = {}

  if d == '' then
    -- All files, relative to cwd
    local cur = vim.fn.expand('%')
    if cur ~= '' then
      table.insert(items, vim.fn.fnamemodify(cur, ':~:.'))
    end
    for _, b in ipairs(M.buflisted_sorted()) do
      local name = vim.fn.bufname(b)
      if name ~= '' then
        table.insert(items, vim.fn.fnamemodify(vim.fn.expand(name), ':~:.'))
      end
    end
    for _, of in ipairs(M.oldfiles()) do
      if vim.fn.filereadable(vim.fn.fnamemodify(vim.fn.expand(of.name), ':p')) == 1 then
        table.insert(items, vim.fn.fnamemodify(vim.fn.expand(of.name), ':~:.'))
      end
    end
    return uniq_with_prefix(items, '')
  else
    -- Files within d
    local cur = vim.fn.expand('%')
    if cur ~= '' then
      local real = vim.fn.expand('%:p')
      if vim.fn.exists('*FugitiveReal') == 1 then
        local r = vim.fn.FugitiveReal(real)
        -- FugitiveReal returns a string normally, but {path, lnum} on fugitive:// buffers
        real = (type(r) == 'table' and r[1]) or (type(r) == 'string' and r ~= '' and r) or real
      end
      -- Strip d/ prefix to get a relative path; fall back to the full path
      table.insert(items, real:sub(1, #d + 1) == d .. '/' and real:sub(#d + 2) or real)
    end
    for _, b in ipairs(M.buflisted_sorted()) do
      local name = vim.fn.fnameescape(vim.fn.bufname(b))
      if name ~= '' then
        local full = vim.fn.fnamemodify(vim.fn.expand(name), ':p')
        if full:sub(1, #d) == d then
          table.insert(items, full:sub(#d + 2))
        end
      end
    end
    for _, of in ipairs(M.oldfiles()) do
      local full = vim.fn.fnamemodify(vim.fn.expand(vim.fn.fnameescape(of.name)), ':p')
      if vim.fn.filereadable(full) == 1 and full:sub(1, #d) == d then
        table.insert(items, full:sub(#d + 2))
      end
    end
    return uniq_with_prefix(items, '')
  end
end

-- ── Git helpers ──────────────────────────────────────────────────────────────

function M.git_file_existed(file)
  if file == '' then
    return false
  end
  local out = vim.fn.system(
    'git -C `git rev-parse --show-toplevel` log --pretty=format: --name-only --diff-filter=A -- '
      .. vim.fn.shellescape(file)
  )
  return out ~= '' and vim.v.shell_error == 0
end

function M.fugitive_strip_header(file)
  local parts = vim.split(file, '//', { plain = true })
  if #parts > 0 and parts[1]:sub(1, 8) == 'fugitive' then
    local last = parts[#parts]
    if #last > 40 then
      return M.get_git_root() .. '/' .. last:sub(42)
    else
      return file
    end
  end
  return file
end

-- ── Bin path ─────────────────────────────────────────────────────────────────

local _bin_dir = nil
function M.bin_dir()
  if _bin_dir == nil then
    local src = debug.getinfo(1, 'S').source:sub(2)
    _bin_dir = vim.fn.fnamemodify(src, ':h:h:h') .. '/bin/'
  end
  return _bin_dir
end

function M.bin_path(name)
  return M.bin_dir() .. name
end

local _data_path = nil
function M.data_path()
  if _data_path == nil then
    local xdg = vim.env.XDG_DATA_HOME
    _data_path = (xdg and xdg ~= '' and xdg or (vim.env.HOME .. '/.local/share')) .. '/siefe.vim'
    vim.fn.mkdir(_data_path, 'p')
  end
  return _data_path
end

-- Return the path to the siefe error log (used as $1 when invoking bin/logger).
function M.log_path()
  return M.data_path() .. '/siefe.log'
end

-- Build keymap.fzf from a flat table of fzf key/action pairs.
-- All bind types (simple navigation, change-preview, reload, unbind, etc.)
-- are placed directly in keymap.fzf; fzf-lua's create_fzf_binds handles them.
--
-- binds: { [key] = 'fzf-action', ... }
function M.make_binds(binds)
  return { fzf = binds or {} }
end

-- Convert an fzf key notation string (e.g. 'ctrl-/', 'alt-p', 'f4') to Neovim
-- key notation (e.g. '<C-/>', '<A-p>', '<f4>').  This is required when a key
-- needs to be registered as a Neovim terminal-mode keymap (keymap.builtin) via
-- vim.keymap.set("t", key, ...).  fzf notation does not use angle-bracket
-- wrapping, so the literal string 'ctrl-/' would map the characters c,t,r,l,-,/
-- rather than the Ctrl+/ keystroke.
function M.fzf_key_to_nvim(key)
  local conv = { ctrl = 'C', alt = 'A', shift = 'S' }
  key = key:lower()
  for fzf_mod, nvim_mod in pairs(conv) do
    -- Replace 'ctrl-' → 'C-', 'alt-' → 'A-', 'shift-' → 'S-'.
    -- Anchoring on the trailing dash avoids partial matches (e.g. 'alternative').
    key = key:gsub(fzf_mod .. '%-', nvim_mod .. '-')
  end
  return '<' .. key .. '>'
end

-- ── Preview commands ──────────────────────────────────────────────────────────

local _fd_cmd = nil
function M.fd_command()
  if _fd_cmd == nil then
    local blue_dotdot = '"\x1b[34m..\x1b[0m"'
    if vim.fn.executable('fdfind') == 1 then
      _fd_cmd = 'echo -e ' .. blue_dotdot .. '; fdfind'
    elseif vim.fn.executable('fd') == 1 then
      _fd_cmd = 'echo -e ' .. blue_dotdot .. '; fd'
    else
      _fd_cmd = ''
    end
  end
  return _fd_cmd
end

-- Always use ':' — the standard rg field separator understood by fzf-lua's
-- builtin previewer and path.entry_to_file() parser.
function M.rg_delimiter()
  return ':'
end

-- ── Misc ─────────────────────────────────────────────────────────────────────

-- Open a file, then move cursor
function M.open_file(cmd, filename, lnum, col)
  local ok, err = pcall(vim.cmd, (cmd or 'edit') .. ' ' .. vim.fn.fnameescape(filename))
  if not ok then
    M.warn(err)
    return
  end
  if lnum and lnum > 0 then
    vim.fn.cursor(lnum, col or 1)
    vim.cmd('normal! zvzz')
  end
end

-- Parse a rg-format selected line using the current delimiter
function M.parse_rg_line(line)
  local delim = M.rg_delimiter()
  local parts = vim.split(line, delim, { plain = true })
  if #parts >= 4 then
    return {
      filename = parts[1],
      lnum = tonumber(parts[2]) or 1,
      col = tonumber(parts[3]) or 1,
      text = table.concat(vim.list_slice(parts, 4), delim),
    }
  end
  return nil
end

-- Compute fzf preview window size string
function M.preview_window_size()
  local cfg = require('siefe.config')
  if vim.o.columns < cfg.preview_hide_threshold then
    return '0%', cfg.default_preview_size .. '%'
  else
    return cfg.default_preview_size .. '%', 'hidden'
  end
end

-- Common window action header text
function M.common_window_help()
  local cfg = require('siefe.config')
  local parts = {}
  for key, action in pairs(cfg.common_window_actions) do
    if key ~= '' then
      table.insert(parts, M.prettify_help(key) .. ' ' .. action)
    end
  end
  return table.concat(parts, ' ╱ ')
end

-- Escape a string for safe use in fzf bind actions (inside parentheses syntax)
function M.fzf_escape(s)
  -- No escaping needed inside () bind syntax in fzf >= 0.36
  return s
end

-- Build the winopts table for fzf-lua
-- Non-fullscreen: bottom-anchored window (height = win_height fraction, full width).
--   row=1.0 in fzf-lua positions the bottom edge at the screen bottom.
-- Fullscreen: uses the entire terminal.
function M.winopts(fullscreen)
  if fullscreen then
    return { fullscreen = true }
  end
  local cfg = require('siefe.config')
  return {
    height = cfg.win_height,
    width  = 1.0,
    row    = 1.0, -- anchor to bottom of screen
    col    = 0,   -- leftmost column; irrelevant for full-width, but explicit
  }
end

return M
