-- lua/siefe/dir_select.lua
-- Directory selection picker (using fd)
local M = {}

local config = require('siefe.config')
local utils  = require('siefe.utils')

-- callback_fn : function(fullscreen, dir, fd_hidden, fd_no_ignore, fd_depth1, kwargs, selected)
-- The callback receives the selections and decides what to do next.
function M.dir_select(callback_fn, fullscreen, dir, fd_hidden, fd_no_ignore, fd_type, multi, fd_depth1, base_dir, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then utils.warn('siefe: fzf-lua not found') return end

  fd_hidden    = fd_hidden    or false
  fd_no_ignore = fd_no_ignore or false
  fd_depth1    = fd_depth1    or false
  fd_type      = fd_type      or ''
  base_dir     = base_dir     or ''
  kwargs       = kwargs       or {}

  local fd_hidden_flag    = fd_hidden    and '-H ' or ''
  local fd_no_ignore_flag = fd_no_ignore and '-u ' or ''
  local fd_depth1_flag    = fd_depth1    and '-d1 ' or ''
  local fd_type_flag      = fd_type ~= '' and (' --type ' .. fd_type .. ' ') or ''

  local base_dir_flag
  if base_dir ~= '' then
    base_dir_flag = ' --strip-cwd-prefix --base-directory ' .. vim.fn.shellescape(base_dir)
  else
    base_dir_flag = ' --search-path=`realpath --relative-to=. "' .. dir .. '"` --relative-path '
  end

  local project_root_env = config.fd_project_root_env
  local has_project_root = project_root_env ~= ''

  local prompt  = fd_no_ignore_flag .. fd_hidden_flag .. fd_depth1_flag .. 'fd> '
  local fd_cmd  = utils.fd_command()
  local source  = utils.bin_path('logger')
    .. ' ' .. fd_cmd
    .. ' --exclude ".git/" --color=always '
    .. fd_hidden_flag .. fd_no_ignore_flag .. fd_type_flag .. fd_depth1_flag
    .. base_dir_flag

  local header  = vim.fn.getcwd()
    .. '\n' .. utils.prettify_header(config.fd_hidden_key,    'hidden:' .. (fd_hidden and 'off' or 'on'))
    .. ' ╱ ' .. utils.prettify_header(config.fd_no_ignore_key, 'no ignore:' .. (fd_no_ignore and 'off' or 'on'))
    .. ' ╱ ' .. utils.prettify_header(config.fd_git_root_key, '√git')
    .. (has_project_root and (' ╱ ' .. utils.prettify_header(config.fd_project_root_key, '√work')) or '')
    .. ' ╱ ' .. utils.prettify_header(config.abort_key, 'abort')
    .. '\n' .. utils.prettify_header(config.fd_search_git_root_key, 'search √git')
    .. ' ╱ ' .. utils.prettify_header(config.fd_depth1_key, '-d1:' .. (fd_depth1 and 'off' or 'on'))
    .. ' ╱ ' .. utils.prettify_header(config.fd_open_dir_key, 'open dir')
    .. (has_project_root and (' ╱ ' .. utils.prettify_header(config.fd_search_project_root_key, 'search √work')) or '')

  local binds = {
    'change:first',
    config.accept_key           .. ':accept',
    config.up_key               .. ':up',
    config.down_key             .. ':down',
    config.next_history_key     .. ':next-history',
    config.previous_history_key .. ':previous-history',
    config.toggle_up_key        .. ':toggle+up',
    config.toggle_down_key      .. ':toggle+down',
  }

  local multi_opt = multi and { ['--multi'] = '' } or {}

  -- Change to the base directory before opening fd
  vim.cmd('cd ' .. vim.fn.fnameescape(dir))

  local actions = {}

  local function dispatch(sel)
    -- sel[1] = query (print-query), sel[2] = key, sel[3:] = selected paths
    local query = sel[1] or ''
    local key   = sel[2] or ''
    local paths = vim.list_slice(sel, 3)
    kwargs.fd_query = query
    callback_fn(fullscreen, dir, fd_hidden, fd_no_ignore, fd_depth1, kwargs, { query, key, unpack(paths) })
  end

  actions['default'] = function(selected, opts)
    local query = (opts and opts.last_query) or (selected[1] or '')
    local paths = selected
    -- If print-query caused query to be prepended, strip it
    kwargs.fd_query = query
    callback_fn(fullscreen, dir, fd_hidden, fd_no_ignore, fd_depth1, kwargs, vim.list_extend({ query, '' }, paths))
  end

  actions[config.abort_key] = function(selected, opts)
    local query = (opts and opts.last_query) or (selected[1] or '')
    kwargs.fd_query = query
    callback_fn(fullscreen, dir, fd_hidden, fd_no_ignore, fd_depth1, kwargs, { query, config.abort_key })
  end

  actions[config.fd_hidden_key] = function(selected, opts)
    local query = (opts and opts.last_query) or (selected[1] or '')
    kwargs.fd_query = query
    M.dir_select(callback_fn, fullscreen, dir, not fd_hidden, fd_no_ignore, fd_type, multi, fd_depth1, base_dir, kwargs)
  end

  actions[config.fd_no_ignore_key] = function(selected, opts)
    local query = (opts and opts.last_query) or (selected[1] or '')
    kwargs.fd_query = query
    M.dir_select(callback_fn, fullscreen, dir, fd_hidden, not fd_no_ignore, fd_type, multi, fd_depth1, base_dir, kwargs)
  end

  actions[config.fd_depth1_key] = function(selected, opts)
    local query = (opts and opts.last_query) or (selected[1] or '')
    kwargs.fd_query = query
    M.dir_select(callback_fn, fullscreen, dir, fd_hidden, fd_no_ignore, fd_type, multi, not fd_depth1, base_dir, kwargs)
  end

  actions[config.fd_open_dir_key] = function(selected, opts)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir))
  end

  actions[config.fd_git_root_key] = function(selected, opts)
    local query = (opts and opts.last_query) or (selected[1] or '')
    kwargs.fd_query = query
    M.dir_select(callback_fn, fullscreen, utils.get_git_root(), fd_hidden, fd_no_ignore, fd_type, multi, fd_depth1, utils.get_git_root(), kwargs)
  end

  actions[config.fd_search_git_root_key] = function(selected, opts)
    local query = (opts and opts.last_query) or (selected[1] or '')
    kwargs.fd_query = query
    M.dir_select(callback_fn, fullscreen, utils.get_git_root(), fd_hidden, fd_no_ignore, fd_type, multi, fd_depth1, utils.get_git_root(), kwargs)
  end

  if has_project_root then
    actions[config.fd_project_root_key] = function(selected, opts)
      local query = (opts and opts.last_query) or (selected[1] or '')
      kwargs.fd_query = query
      local proot = vim.fn.expand(project_root_env)
      M.dir_select(callback_fn, fullscreen, proot, fd_hidden, fd_no_ignore, fd_type, multi, fd_depth1, proot, kwargs)
    end
    actions[config.fd_search_project_root_key] = function(selected, opts)
      local query = (opts and opts.last_query) or (selected[1] or '')
      kwargs.fd_query = query
      local proot = vim.fn.expand(project_root_env)
      M.dir_select(callback_fn, fullscreen, proot, fd_hidden, fd_no_ignore, fd_type, multi, fd_depth1, proot, kwargs)
    end
  end

  local fzf_opts = vim.tbl_extend('force', {
    ['--history']     = utils.data_path() .. '/git_dir_history',
    ['--ansi']        = '',
    ['--print-query'] = '',
    ['--query']       = kwargs.fd_query or '',
    ['--scheme']      = 'path',
    ['--bind']        = binds,
    ['--header']      = header,
    ['--prompt']      = prompt,
  }, multi_opt)

  fzf_lua.fzf_exec(source, {
    prompt    = prompt,
    query     = kwargs.fd_query or '',
    cwd       = dir,
    winopts   = utils.winopts(fullscreen),
    previewer = false,
    fzf_opts  = fzf_opts,
    actions   = actions,
  })
end

-- ── Sink helpers for common callers ──────────────────────────────────────────

-- Sink used when dir_select was called from ripgrepfzf
function M.ripgrep_dir_sink(fullscreen, orig_dir, fd_hidden, fd_no_ignore, fd_depth1, kwargs, lines)
  local query   = lines[1] or ''
  local key     = lines[2] or ''
  local new_dir = lines[3] or orig_dir
  kwargs.fd_query = query

  local rg = require('siefe.rg')

  if key == config.abort_key then
    kwargs.prompt = utils.get_relative_git_or_bufdir()
    rg.ripgrepfzf(fullscreen, utils.bufdir(), kwargs)

  elseif key == config.fd_hidden_key then
    M.dir_select(M.ripgrep_dir_sink, fullscreen, orig_dir, not fd_hidden, fd_no_ignore, 'd', false, fd_depth1, '', kwargs)

  elseif key == config.fd_no_ignore_key then
    M.dir_select(M.ripgrep_dir_sink, fullscreen, orig_dir, fd_hidden, not fd_no_ignore, 'd', false, fd_depth1, '', kwargs)

  elseif key == config.fd_depth1_key then
    M.dir_select(M.ripgrep_dir_sink, fullscreen, orig_dir, fd_hidden, fd_no_ignore, 'd', false, not fd_depth1, '', kwargs)

  elseif key == config.fd_open_dir_key then
    vim.cmd('edit ' .. vim.fn.fnameescape(orig_dir))

  elseif key == config.fd_git_root_key then
    kwargs.prompt = utils.get_git_basename_or_bufdir()
    kwargs.paths  = {}
    rg.ripgrepfzf(fullscreen, utils.get_git_root(), kwargs)

  elseif key == config.fd_project_root_key and config.fd_project_root_env ~= '' then
    local proot   = vim.fn.expand(config.fd_project_root_env)
    kwargs.prompt = config.fd_project_root_env
    kwargs.paths  = {}
    rg.ripgrepfzf(fullscreen, proot, kwargs)

  elseif key == config.fd_search_git_root_key then
    M.dir_select(M.ripgrep_dir_sink, fullscreen, utils.get_git_root(), fd_hidden, fd_no_ignore, 'd', false, fd_depth1, '', kwargs)

  elseif key == config.fd_search_project_root_key and config.fd_project_root_env ~= '' then
    local proot = vim.fn.expand(config.fd_project_root_env)
    M.dir_select(M.ripgrep_dir_sink, fullscreen, proot, fd_hidden, fd_no_ignore, 'd', false, fd_depth1, '', kwargs)

  else
    -- accepted a directory
    kwargs.prompt = utils.get_relative_git_or_bufdir(new_dir)
    kwargs.paths  = {}
    local resolved = vim.trim(vim.fn.system('realpath ' .. vim.fn.shellescape(new_dir)))
    rg.ripgrepfzf(fullscreen, resolved, kwargs)
  end
end

-- Sink used when dir_select was called from gitlogfzf
function M.gitlog_path_sink(fullscreen, orig_dir, fd_hidden, fd_no_ignore, fd_depth1, kwargs, lines)
  local key   = lines[2] or ''
  kwargs.fd_query = lines[1] or ''

  local gl = require('siefe.git_log')

  if key == config.abort_key then
    kwargs.paths = {}
    gl.gitlogfzf(fullscreen, kwargs)

  elseif key == config.fd_hidden_key then
    M.dir_select(M.gitlog_path_sink, fullscreen, utils.bufdir(), not fd_hidden, fd_no_ignore, '', true, fd_depth1, utils.bufdir(), kwargs)

  elseif key == config.fd_no_ignore_key then
    M.dir_select(M.gitlog_path_sink, fullscreen, utils.bufdir(), fd_hidden, not fd_no_ignore, '', true, fd_depth1, utils.bufdir(), kwargs)

  elseif key == config.fd_depth1_key then
    M.dir_select(M.gitlog_path_sink, fullscreen, utils.bufdir(), fd_hidden, fd_no_ignore, '', true, not fd_depth1, utils.get_git_root(), kwargs)

  elseif key == config.fd_search_git_root_key then
    M.dir_select(M.gitlog_path_sink, fullscreen, utils.bufdir(), fd_hidden, fd_no_ignore, '', true, fd_depth1, utils.get_git_root(), kwargs)

  else
    kwargs.paths = vim.list_slice(lines, 3)
    gl.gitlogfzf(fullscreen, kwargs)
  end
end

return M
