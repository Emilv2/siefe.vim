-- lua/siefe/history.lua
-- File history picker
local M = {}

local config = require('siefe.config')
local utils  = require('siefe.utils')

function M.historyoldfiles(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then utils.warn('siefe: fzf-lua not found') return end

  kwargs.query   = kwargs.query   or ''
  kwargs.project = kwargs.project ~= nil and kwargs.project or false
  kwargs.preview = kwargs.preview ~= nil and kwargs.preview or config.history_default_preview_command

  local bufdir   = utils.bufdir()
  local git_root = vim.trim(vim.fn.system('git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-toplevel'))
  local in_git   = vim.v.shell_error == 0

  local git_expect = ''
  local git_help   = ''
  if in_git then
    local toggle = kwargs.project and 'off' or 'on'
    git_expect = config.history_git_key .. ','
    git_help   = ' ╱ ' .. utils.prettify_header(config.history_git_key, 'project history:' .. toggle)
  end

  local source
  local project_prefix = ''
  if kwargs.project and in_git then
    source         = utils.recent_git_files_info()
    project_prefix = utils.get_git_basename_or_bufdir() .. ' '
  else
    source = utils.recent_files_info()
  end

  local previews    = utils.make_preview_commands()
  local p0          = previews.hist[1]
  local p1          = previews.hist[2]
  local p2          = previews.hist[3]
  local preview_cmd = previews.hist[(kwargs.preview or 0) + 1] or p0

  local default_size, other_size = utils.preview_window_size()

  local header = utils.prettify_header(config.history_files_key, 'rg files')
    .. ' ╱ ' .. utils.prettify_header(config.history_rg_key, 'rg')
    .. ' ╱ ' .. utils.prettify_header(config.history_buffers_key, 'buf')
    .. git_help
    .. ' ╱ ' .. utils.magenta(utils.preview_help({ config.history_preview_key, config.history_fast_preview_key, config.history_faster_preview_key }), 'Special') .. ' change preview'
    .. '\n' .. utils.common_window_help()

  local binds = {
    'change:first',
    'enter:ignore',
    'esc:ignore',
    config.accept_key           .. ':accept',
    config.up_key               .. ':up',
    config.down_key             .. ':down',
    config.next_history_key     .. ':next-history',
    config.previous_history_key .. ':previous-history',
    config.toggle_up_key        .. ':toggle+up',
    config.toggle_down_key      .. ':toggle+down',
    config.toggle_preview_key   .. ':change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
    config.history_preview_key       .. ':change-preview(' .. p0 .. ')',
    config.history_fast_preview_key  .. ':change-preview(' .. p1 .. ')',
    config.history_faster_preview_key.. ':change-preview(' .. p2 .. ')',
  }

  -- Shows current buffer at top as a "header line"
  local header_lines = (vim.fn.expand('%') ~= '') and 1 or 0

  local fzf_opts = {
    ['--history']     = utils.data_path() .. '/rg_history_history',
    ['--ansi']        = '',
    ['--multi']       = '',
    ['--print-query'] = '',
    ['--with-nth']    = '2..',
    ['--delimiter']   = '//',
    ['--preview-window'] = '+{1}-/2,' .. default_size,
    ['--header-lines'] = tostring(header_lines),
    ['--header']      = header,
    ['--prompt']      = project_prefix .. 'Hist> ',
    ['--bind']        = binds,
  }

  -- ── Helpers ─────────────────────────────────────────────────────────────────

  local function get_query(selected, opts)
    if opts and opts.last_query then return opts.last_query end
    if selected and #selected > 0 and not selected[1]:match('//') then return selected[1] end
    return kwargs.query or ''
  end

  local function get_items(selected, opts)
    if opts and opts.last_query then return selected end
    if selected and #selected > 0 and not selected[1]:match('//') then
      return vim.list_slice(selected, 2)
    end
    return selected or {}
  end

  local function filename_from_line(line)
    local parts = vim.split(line, '//', { plain = true })
    return #parts >= 2 and parts[2] or line
  end

  -- ── Actions ─────────────────────────────────────────────────────────────────

  local actions = {}

  actions['default'] = function(selected, opts)
    local items = get_items(selected, opts)
    if #items == 0 then return end
    local filename = filename_from_line(items[1])
    utils.open_file('edit', filename)
    if #items > 1 then
      local qf = vim.tbl_map(function(l)
        return { filename = filename_from_line(l) }
      end, items)
      if config.history_loclist then utils.fill_loc(qf) else utils.fill_quickfix(qf) end
    end
  end

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = function(selected, opts)
      local items = get_items(selected, opts)
      for _, line in ipairs(items) do
        utils.open_file(c, filename_from_line(line))
      end
    end
  end

  actions[config.history_git_key] = function(selected, opts)
    kwargs.query   = get_query(selected, opts)
    kwargs.project = not kwargs.project
    M.historyoldfiles(fullscreen, kwargs)
  end

  actions[config.history_buffers_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    local bufs = require('siefe.buffers')
    bufs.buffers(fullscreen, kwargs)
  end

  actions[config.history_files_key] = function(selected, opts)
    kwargs.query  = get_query(selected, opts)
    kwargs.prompt = utils.get_relative_git_or_bufdir()
    kwargs.files  = true
    local rg = require('siefe.rg')
    rg.ripgrepfzf(fullscreen, utils.bufdir(), kwargs)
  end

  actions[config.history_rg_key] = function(selected, opts)
    kwargs.query  = get_query(selected, opts)
    kwargs.prompt = utils.get_relative_git_or_bufdir()
    kwargs.paths  = source
    kwargs.files  = false
    local rg = require('siefe.rg')
    rg.ripgrepfzf(fullscreen, utils.bufdir(), kwargs)
  end

  -- Launch
  local launch_opts = {
    prompt    = project_prefix .. 'Hist> ',
    query     = kwargs.query,
    winopts   = utils.winopts(fullscreen),
    previewer = false,
    preview   = preview_cmd,
    fzf_opts  = fzf_opts,
    actions   = actions,
  }
  if kwargs.project and in_git then
    launch_opts.cwd = git_root
  end

  fzf_lua.fzf_exec(source, launch_opts)
end

return M
