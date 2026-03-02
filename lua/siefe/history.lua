-- lua/siefe/history.lua
-- File history picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

-- Parse an entry returned by fzf.
--
-- Current format (produced by make_history_entry): fname:lnum:col\x01display
--   entry_to_file() splits on ':' and reads fname:lnum:col from the prefix.
-- Legacy SOH format: fname\x01lnum\x01col\x01display
-- Intermediate tab format (older sessions): lnum\tcol\tfname[\tdisplay]
-- Legacy // formats (from older entries / utils.recent_*_info):
--   lnum//col//fname  (fname may itself contain "//")
--   lnum//fname       (no col)
local function parse_entry(line)
  if line:find('\x01', 1, true) then
    local parts = vim.split(line, '\x01', { plain = true })
    -- Current format: fname:lnum:col\x01display → parts[1]="fname:lnum:col"
    local prefix = parts[1] or ''
    if prefix:find(':', 1, true) then
      local ps = vim.split(prefix, ':', { plain = true })
      -- ps[1]=fname, ps[2]=lnum, ps[3]=col (fname is absolute path, no colons)
      local fname = ps[1] or ''
      local lnum = tonumber(ps[2]) or 0
      local col = tonumber(ps[3]) or 0
      if fname ~= '' then
        return lnum, col, fname
      end
    end
    -- Legacy SOH format: fname\x01lnum\x01col\x01display
    return tonumber(parts[2]) or 0, tonumber(parts[3]) or 0, parts[1] or ''
  end
  if line:find('\t', 1, true) then
    -- Intermediate tab-separated format: lnum\tcol\tfname\tdisplay
    local parts = vim.split(line, '\t', { plain = true })
    return tonumber(parts[1]) or 0, tonumber(parts[2]) or 0, parts[3] or ''
  end
  -- Legacy //-separated format
  local parts = vim.split(line, '//', { plain = true })
  if #parts >= 3 then
    return tonumber(parts[1]) or 0, tonumber(parts[2]) or 0, table.concat(vim.list_slice(parts, 3), '//')
  elseif #parts == 2 then
    return tonumber(parts[1]) or 0, 0, parts[2]
  end
  return 0, 0, line
end

-- Return an absolute path for fname.
-- In project mode, recent_git_files_info() emits paths relative to git_root.
-- The builtin previewer resolves them correctly via cwd=git_root, but
-- utils.open_file() resolves against Neovim's cwd (which may be a subdirectory).
-- This function ensures open_file always receives an absolute path.
local function make_absolute(fname, git_root, project)
  if project and git_root and git_root ~= '' and fname ~= '' and fname:sub(1, 1) ~= '/' then
    return git_root .. '/' .. fname
  end
  return fname
end


-- Format: fname:lnum:col\x01DISPLAY
-- entry_to_file() splits on ':' to extract fname:lnum:col from the prefix;
-- \x01 separates it from the display shown by fzf (--with-nth=2..).
-- DISPLAY = "lnum[:col] fname" (lnum colored green when > 0).
local function make_history_entry(lnum, col, fname)
  local pos = (lnum > 0) and (utils.green(tostring(lnum)) .. (col > 0 and utils.green(':' .. tostring(col)) or ''))
    or ''
  local display = pos ~= '' and (pos .. ' ' .. fname) or fname
  return fname .. ':' .. tostring(lnum) .. ':' .. tostring(col) .. '\x01' .. display
end

function M.historyoldfiles(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs.query = kwargs.query or ''
  kwargs.project = kwargs.project ~= nil and kwargs.project or false

  local bufdir = utils.bufdir()
  local git_root = vim.trim(vim.fn.system('git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-toplevel'))
  local in_git = vim.v.shell_error == 0
  local git_help = ''

  if in_git then
    local toggle = kwargs.project and 'off' or 'on'
    git_help = ' ╱ ' .. utils.prettify_header(config.history_git_key, 'project history:' .. toggle)
  end

  local source
  local project_prefix = ''
  if kwargs.project and in_git then
    source = vim.tbl_map(function(e)
      local lnum, col, fname = parse_entry(e)
      return make_history_entry(lnum, col, fname)
    end, utils.recent_git_files_info())
    project_prefix = utils.get_git_basename_or_bufdir() .. ' '
  else
    -- Use v:oldfiles (no line/col position info) prefixed with the current
    -- buffer and listed buffers for immediate MRU access.
    source = vim.tbl_map(function(e)
      local lnum, col, fname = parse_entry(e)
      return make_history_entry(lnum, col, fname)
    end, utils.recent_files_info())
  end

  local default_size, other_size = utils.preview_window_size()

  local hist_km = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    [config.toggle_preview_key] = {
      'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
      desc = 'cycle-preview',
    },
  })

  -- Shows current buffer at top as a "header line"
  local header_lines = (vim.fn.expand('%') ~= '') and 1 or 0

  local fzf_opts = {
    ['--history'] = utils.data_path() .. '/rg_history_history',
    ['--ansi'] = '',
    ['--multi'] = '',
    -- Entry format: fname:lnum:col\x01display
    -- entry_to_file() reads fname:lnum:col from ':' prefix; fzf shows field 2+ (display).
    ['--with-nth'] = '2..',
    ['--delimiter'] = '\x01',
    ['--preview-window'] = default_size,
    ['--header-lines'] = tostring(header_lines),
    ['--prompt'] = project_prefix .. 'Hist> ',
  }

  -- ── Helpers ─────────────────────────────────────────────────────────────────

  local function get_query(selected, opts)
    return (opts and opts.last_query) or kwargs.query or ''
  end

  local function get_items(selected, opts)
    return selected or {}
  end

  -- Resolve fname to absolute via git_root when in project mode.
  local function resolve(fname)
    return make_absolute(fname, git_root, kwargs.project and in_git)
  end

  -- ── Actions ─────────────────────────────────────────────────────────────────

  local actions = {}

  actions['default'] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local lnum, col, filename = parse_entry(items[1])
      utils.open_file('edit', resolve(filename), lnum > 0 and lnum or nil, col > 0 and col or nil)
      if #items > 1 then
        local qf = vim.tbl_map(function(l)
          local _, _, fname = parse_entry(l)
          return { filename = resolve(fname) }
        end, items)
        if config.history_loclist then
          utils.fill_loc(qf)
        else
          utils.fill_quickfix(qf)
        end
      end
    end,
    desc = 'open',
  }

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = {
      fn = function(selected, opts)
        local items = get_items(selected, opts)
        for _, line in ipairs(items) do
          local lnum, col, filename = parse_entry(line)
          utils.open_file(c, resolve(filename), lnum > 0 and lnum or nil, col > 0 and col or nil)
        end
      end,
      desc = 'open ' .. c,
    }
  end

  actions[config.history_git_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.project = not kwargs.project
      M.historyoldfiles(fullscreen, kwargs)
    end,
    desc = 'project',
  }

  actions[config.history_buffers_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      local bufs = require('siefe.buffers')
      bufs.buffers(fullscreen, kwargs)
    end,
    desc = 'buffers',
  }

  actions[config.history_files_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.prompt = utils.get_relative_git_or_bufdir()
      kwargs.files = true
      local rg = require('siefe.rg')
      rg.ripgrepfzf(fullscreen, utils.bufdir(), kwargs)
    end,
    desc = 'files',
  }

  actions[config.history_rg_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.prompt = utils.get_relative_git_or_bufdir()
      -- Compute recent plain file paths (same as rg.lua's rg_history_key action).
      -- `source` here is a display-entry list or coroutine — not suitable as rg paths.
      local git_root = utils.get_git_root()
      kwargs.paths = utils.recent_files(git_root ~= '' and git_root or nil)
      kwargs.files = false
      local rg = require('siefe.rg')
      rg.ripgrepfzf(fullscreen, utils.bufdir(), kwargs)
    end,
    desc = 'rg',
  }

  -- Launch
  local launch_opts = {
    prompt = project_prefix .. 'Hist> ',
    query = kwargs.query,
    winopts = utils.winopts(fullscreen),
    previewer = 'builtin',
    fzf_opts = fzf_opts,
    keymap = hist_km,
    actions = actions,
  }
  if kwargs.project and in_git then
    launch_opts.cwd = git_root
  end

  fzf_lua.fzf_exec(source, launch_opts)
end

-- Test-only exports (not part of the public API).
-- Used by test/test_history.lua to exercise pure logic without launching fzf.
M._test = {
  parse_entry = parse_entry,
  make_history_entry = make_history_entry,
  make_absolute = make_absolute,
}

return M
