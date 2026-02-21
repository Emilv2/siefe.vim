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

local ansi_codes = { black=30, red=31, green=32, yellow=33, blue=34, magenta=35, cyan=36 }

function M.csi(color, fg)
  local prefix = fg and '38;' or '48;'
  if color:sub(1,1) == '#' then
    local r = tonumber(color:sub(2,3), 16)
    local g = tonumber(color:sub(4,5), 16)
    local b = tonumber(color:sub(6,7), 16)
    return prefix .. '2;' .. r .. ';' .. g .. ';' .. b
  end
  return prefix .. '5;' .. color
end

function M.get_color(attr, ...)
  local gui = vim.o.termguicolors
  local fam  = gui and 'gui' or 'cterm'
  local pat  = gui and '^#[a-fA-F0-9]+' or '^%d+$'
  for _, group in ipairs({...}) do
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

function M.magenta(str, group) return M.ansi(str, group or '', 'magenta') end
function M.blue(str, group)    return M.ansi(str, group or '', 'blue') end
function M.red(str, group)     return M.ansi(str, group or '', 'red') end
function M.green(str, group)   return M.ansi(str, group or '', 'green') end
function M.yellow(str, group)  return M.ansi(str, group or '', 'yellow') end

-- ── Header helpers ───────────────────────────────────────────────────────────

function M.prettify_help(key)
  return M.magenta(key:upper(), 'Special')
end

function M.prettify_header(key, text)
  local char = vim.split(key, '-')[#vim.split(key, '-')]
  if char == text:sub(1,1) then
    return M.magenta(key:upper(), 'Special') .. ' ' .. text
  else
    local replaced = text:sub(2):gsub(char, '\x1b[3m' .. char .. '\x1b[m', 1)
    return M.magenta(key:upper(), 'Special') .. ' ' .. text:sub(1,1) .. replaced
  end
end

function M.preview_help(preview_keys)
  local f_keys, non_f = {}, {}
  for _, k in ipairs(preview_keys) do
    if k:sub(1,1):lower() == 'f' then
      table.insert(f_keys, tonumber(k:sub(2)) or 0)
    else
      table.insert(non_f, k)
    end
  end
  table.sort(f_keys)
  if #f_keys == 0 then
    return table.concat(vim.tbl_map(function(k) return ', ' .. k end, non_f), '')
  end
  local result = ''
  local val_start = f_keys[1]
  local last_val  = f_keys[1]
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
  for _, k in ipairs(non_f) do result = result .. ', ' .. k end
  return result
end

-- ── Quickfix / loclist ───────────────────────────────────────────────────────

function M.fill_quickfix(list, cmd)
  if #list > 1 then
    vim.fn.setqflist(list)
    vim.cmd('copen')
    vim.cmd('wincmd p')
    if cmd then vim.cmd(cmd) end
  end
end

function M.fill_loc(list, cmd)
  if #list > 1 then
    vim.fn.setloclist(0, list)
    vim.cmd('lopen')
    vim.cmd('wincmd p')
    if cmd then vim.cmd(cmd) end
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
  vim.api.nvim_echo({{ msg, 'WarningMsg' }}, true, {})
end

-- ── Duplicate key detection ──────────────────────────────────────────────────

function M.detect_dups(lst)
  local dict, dups = {}, {}
  for _, item in ipairs(lst) do
    if dict[item] then table.insert(dups, item) end
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
    if ok then return oil.get_current_dir() or vim.fn.expand('%:p:h') end
  end
  return vim.fn.expand('%:p:h')
end

function M.get_git_root()
  local ok, result = pcall(vim.fn.FugitiveFind, ':/')
  if ok then return result or '' end
  return ''
end

function M.get_git_basename_or_bufdir()
  local root = M.get_git_root()
  if root == '' then return vim.fn.expand('%:p:h') end
  return vim.fn.fnamemodify(root, ':t')
end

function M.get_relative_git_or_bufdir(dir, git_dir)
  local bufdir = M.bufdir()
  if dir == nil then
    -- No argument: return prompt-style relative path for current buffer dir
    local rel = vim.trim(vim.fn.system('git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-prefix'))
    if vim.v.shell_error ~= 0 then return bufdir end
    local base = vim.split(vim.fn.system('basename `git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-toplevel`'), '\n')[1]
    return '#' .. base .. '/' .. rel
  else
    -- With argument: return relative path from git root to dir
    local gd = git_dir or vim.trim(vim.fn.system('git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-toplevel'))
    if vim.v.shell_error ~= 0 then return dir end
    local prefix = M.get_git_basename_or_bufdir() .. '/'
    return prefix .. vim.trim(vim.fn.system('realpath --relative-to=' .. vim.fn.shellescape(gd) .. ' ' .. vim.fn.shellescape(dir)))
  end
end

-- ── Visual selection ─────────────────────────────────────────────────────────

function M.visual_selection()
  local mode = vim.fn.mode()
  local line_start, col_start, line_end, col_end
  if mode == 'v' then
    line_start, col_start = unpack(vim.fn.getpos('v'), 2, 3)
    line_end, col_end     = unpack(vim.fn.getpos('.'), 2, 3)
  else
    line_start, col_start = unpack(vim.fn.getpos("'<"), 2, 3)
    line_end, col_end     = unpack(vim.fn.getpos("'>"), 2, 3)
  end
  -- Normalise so start < end
  if (vim.fn.line2byte(line_start) + col_start) > (vim.fn.line2byte(line_end) + col_end) then
    line_start, col_start, line_end, col_end = line_end, col_end, line_start, col_start
  end
  local lines = vim.fn.getline(line_start, line_end)
  if #lines == 0 then return '' end
  lines[#lines] = lines[#lines]:sub(1, col_end)
  lines[1]      = lines[1]:sub(col_start)
  return table.concat(lines, '\n')
end

function M.visual_line_nu()
  local mode = vim.fn.mode()
  local line_start, line_end
  if mode == 'v' then
    line_start = vim.fn.getpos('v')[2]
    line_end   = vim.fn.getpos('.')[2]
  else
    line_start = vim.fn.getpos("'<")[2]
    line_end   = vim.fn.getpos("'>")[2]
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
    table.insert(items, cur_line .. '//' .. vim.fn.fnamemodify(cur, ':~:.'))
  end

  -- Listed buffers sorted by access time
  for _, b in ipairs(M.buflisted_sorted()) do
    local name = vim.fn.bufname(b)
    if name ~= '' then
      local lnum = (vim.fn.getbufinfo(b)[1] or {}).lnum or 0
      table.insert(items, tostring(lnum) .. '//' .. vim.fn.fnamemodify(vim.fn.expand(name), ':~:.'))
    end
  end

  -- v:oldfiles
  for _, of in ipairs(M.oldfiles()) do
    if vim.fn.filereadable(vim.fn.fnamemodify(vim.fn.expand(of.name), ':p')) == 1 then
      table.insert(items, tostring(of.line) .. '//' .. vim.fn.fnamemodify(vim.fn.expand(of.name), ':~:.'))
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
    table.insert(items, vim.fn.line('.') .. '//' .. real:gsub(git_dir:gsub('[%(%)%.%%%+%-%*%?%[%^%$]', '%%%1') .. '/', '', 1))
  end

  for _, b in ipairs(M.buflisted_sorted()) do
    local name = vim.fn.fnameescape(vim.fn.bufname(b))
    if name ~= '' then
      local full = vim.fn.fnamemodify(vim.fn.expand(name), ':p')
      if full:sub(1, #git_dir) == git_dir then
        local lnum = (vim.fn.getbufinfo(b)[1] or {}).lnum or 0
        table.insert(items, tostring(lnum) .. '//' .. full:sub(#git_dir + 2))
      end
    end
  end

  for _, of in ipairs(M.oldfiles()) do
    local full = vim.fn.fnamemodify(vim.fn.expand(vim.fn.fnameescape(of.name)), ':p')
    if vim.fn.filereadable(full) == 1 and full:sub(1, #git_dir) == git_dir then
      table.insert(items, tostring(of.line) .. '//' .. full:sub(#git_dir + 2))
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
    if cur ~= '' then table.insert(items, vim.fn.fnamemodify(cur, ':~:.')) end
    for _, b in ipairs(M.buflisted_sorted()) do
      local name = vim.fn.bufname(b)
      if name ~= '' then table.insert(items, vim.fn.fnamemodify(vim.fn.expand(name), ':~:.')) end
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
      local real = vim.fn.FugitiveReal and vim.fn.FugitiveReal() or vim.fn.expand('%:p')
      table.insert(items, real:gsub(d:gsub('[%(%)%.%%%+%-%*%?%[%^%$]', '%%%1') .. '/', '', 1))
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
  if file == '' then return false end
  local out = vim.fn.system('git -C `git rev-parse --show-toplevel` log --pretty=format: --name-only --diff-filter=A -- ' .. vim.fn.shellescape(file))
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

-- ── Data path ────────────────────────────────────────────────────────────────

local _data_path = nil
function M.data_path()
  if _data_path == nil then
    local xdg = vim.env.XDG_DATA_HOME
    _data_path = (xdg and xdg ~= '' and xdg or (vim.env.HOME .. '/.local/share')) .. '/siefe.vim'
    vim.fn.mkdir(_data_path, 'p')
  end
  return _data_path
end

-- ── Preview commands ──────────────────────────────────────────────────────────

local _bat_cmd = nil
function M.bat_command()
  if _bat_cmd == nil then
    if vim.fn.executable('batcat') == 1 then
      _bat_cmd = 'batcat'
    elseif vim.fn.executable('bat') == 1 then
      _bat_cmd = 'bat'
    else
      _bat_cmd = ''
    end
  end
  return _bat_cmd
end

local _fd_cmd = nil
function M.fd_command()
  if _fd_cmd == nil then
    local cfg = require('siefe.config')
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
-- builtin previewer and path.entry_to_file() parser.  In search mode, rg2fzf
-- (when present) converts `rg --null` output (`file\0rest\n`) to this format
-- (`file:rest\0`), enabling fzf --read0 without changing the per-field format.
function M.rg_delimiter()
  return ':'
end

-- Build preview commands for rg / files / buffers / marks / jumps / history
function M.make_preview_commands(preview_slot, bat_opts)
  local preview  = M.bin_path('preview')
  local bat      = M.bat_command()
  local bat_args = bat ~= '' and (bat .. ' --color=always --pager=never ' .. (bat_opts or require('siefe.config').bat_options) .. ' -- ') or nil

  -- rg: {1}=file, {2}=line
  local rg_preview  = bat_args and (preview .. ' {1} ' .. bat_args:gsub('--pager=never ', '--pager=never --highlight-line={2} ')) or (preview .. ' {1} cat')
  local rg_fast     = preview .. ' {1} cat | awk \'' .. '{ if (NR == {2}) { printf("\\x1b[7m%s\\n\\x1b[m", $0) } else printf("\\x1b[m%s\\n", $0) }' .. '\''
  local rg_faster   = preview .. ' {1} cat'

  -- files: {} = file
  local files_preview = bat_args and (preview .. ' {} ' .. bat_args) or (preview .. ' {} cat')

  -- history: {1}=line, {2}=file
  local hist_preview  = bat_args and (preview .. ' {2} ' .. bat_args:gsub('--pager=never ', '--pager=never --highlight-line={1} ')) or (preview .. ' {2} cat')
  local hist_fast     = preview .. ' {2} cat | awk \'' .. '{ if (NR == {1}) { printf("\\x1b[7m%s\\n\\x1b[m", $0) } else printf("\\x1b[m%s\\n", $0) }' .. '\''
  local hist_faster   = preview .. ' {2} cat'

  -- buffers: {1}=file, {2}=line
  local buf_preview   = bat_args and (preview .. ' {1} ' .. bat_args:gsub('--pager=never ', '--pager=never --highlight-line={2} ')) or (preview .. ' {1} cat')
  local buf_fast      = preview .. ' {1} cat'

  -- marks: {2}=file, {3}=line
  local marks_preview = bat_args and (preview .. ' {2} ' .. bat_args:gsub('--pager=never ', '--pager=never --highlight-line={3} ')) or (preview .. ' {2} cat')
  local marks_fast    = preview .. ' {2} cat'

  -- jumps: {1}=file, {2}=line
  local jumps_preview = bat_args and (preview .. ' {1} ' .. bat_args:gsub('--pager=never ', '--pager=never --highlight-line={2} ')) or (preview .. ' {1} cat')
  local jumps_fast    = preview .. ' {1} cat'

  return {
    rg      = { rg_preview,    rg_fast,    rg_faster },
    files   = files_preview,
    hist    = { hist_preview,  hist_fast,  hist_faster },
    buffers = { buf_preview,   buf_fast },
    marks   = { marks_preview, marks_fast },
    jumps   = { jumps_preview, jumps_fast },
  }
end

-- ── Misc ─────────────────────────────────────────────────────────────────────

-- Open a file, then move cursor
function M.open_file(cmd, filename, lnum, col)
  local ok, err = pcall(vim.cmd, (cmd or 'edit') .. ' ' .. vim.fn.fnameescape(filename))
  if not ok then M.warn(err) return end
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
      lnum     = tonumber(parts[2]) or 1,
      col      = tonumber(parts[3]) or 1,
      text     = table.concat(vim.list_slice(parts, 4), delim),
    }
  elseif #parts == 1 then
    local content = vim.fn.readfile(parts[1])
    return {
      filename = parts[1],
      lnum     = 1,
      col      = 1,
      text     = #content > 0 and content[1] or '',
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
function M.winopts(fullscreen)
  return { fullscreen = fullscreen or false }
end

return M
