-- lua/siefe/rg.lua
-- Ripgrep search – main picker
local M = {}

local config = require('siefe.config')
local utils  = require('siefe.utils')

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function bool_to_flag(b, flag) return b and flag or '' end

-- Build the rg command format string (use %s for the query placeholder)
local function build_rg_command(kwargs, dir)
  local logger   = utils.bin_path('logger') .. ' '
  local delim    = utils.rg_field_match_separator()
  local case     = kwargs.case_sensitive == 1 and '--smart-case '
                or kwargs.case_sensitive == 2 and '--ignore-case '
                or '--case-sensitive '
  local word     = bool_to_flag(kwargs.word, '-w ')
  local depth1   = bool_to_flag(kwargs.depth1, '-d1 ')
  local hidden   = bool_to_flag(kwargs.hidden, '--hidden ')
  local no_ignore= kwargs.no_ignore == 1 and '-u '
                or kwargs.no_ignore == 2 and '-uu '
                or kwargs.no_ignore == 3 and '-uuu '
                or ''
  local fixed    = bool_to_flag(kwargs.fixed_strings, '-F ')
  local max1     = bool_to_flag(kwargs.max_1, '-m1 ')
  local zip      = bool_to_flag(kwargs.search_zip, '-z ')
  local text     = bool_to_flag(kwargs.text, '--text ')

  local paths = ''
  if kwargs.paths and #kwargs.paths > 0 then
    local p = {}
    for _, v in ipairs(kwargs.paths) do
      local parts = vim.split(v, '//', { plain = true })
      table.insert(p, vim.fn.shellescape(parts[#parts]))
    end
    paths = ' ' .. table.concat(p, ' ')
  end

  local type_flag = kwargs.type or ''

  return logger
    .. 'rg --column --auto-hybrid-regex -U --glob \\!.git/objects '
    .. '--line-number --no-heading --color=always '
    .. '--colors "column:fg:green" --with-filename '
    .. case
    .. (delim ~= '' and (delim .. ' ') or '')
    .. word .. depth1 .. no_ignore .. hidden .. fixed .. max1 .. zip .. text
    .. type_flag .. ' '
    .. '-- %s'
    .. paths
end

local function build_files_command(kwargs)
  local zip    = bool_to_flag(kwargs.search_zip, '-z ')
  local text   = bool_to_flag(kwargs.text, '--text ')
  local no_ign = kwargs.no_ignore == 1 and '-u '
              or kwargs.no_ignore == 2 and '-uu '
              or kwargs.no_ignore == 3 and '-uuu '
              or ''
  local hidden = bool_to_flag(kwargs.hidden, '--hidden ')
  local depth1 = bool_to_flag(kwargs.depth1, '-d1 ')
  local type_f = kwargs.type or ''

  -- Exclude current buffer from file listing when possible
  local bufname_exclude = ''
  if vim.fn.expand('%:t') ~= '' then
    -- computed dynamically when called
  end

  return 'rg ' .. zip .. text .. no_ign .. hidden .. depth1
    .. ' --color=always --files ' .. type_f
end

local function build_prompt(kwargs, mode)
  local case_sym = kwargs.case_sensitive == 1 and '-S '
                or kwargs.case_sensitive == 2 and '-i '
                or '-s '
  local no_ign   = kwargs.no_ignore == 1 and '-u '
                or kwargs.no_ignore == 2 and '-uu '
                or kwargs.no_ignore == 3 and '-uuu '
                or ''
  local word    = bool_to_flag(kwargs.word, '-w ')
  local depth1  = bool_to_flag(kwargs.depth1, '-d1 ')
  local hidden  = kwargs.hidden and '-. ' or ''
  local fixed   = bool_to_flag(kwargs.fixed_strings, '-F ')
  local max1    = bool_to_flag(kwargs.max_1, '-m1 ')
  local zip     = bool_to_flag(kwargs.search_zip, '-z ')
  local text    = kwargs.text and '-a ' or ''
  local type_p  = kwargs.type ~= '' and (kwargs.type .. ' ') or ''
  local base    = kwargs.prompt or utils.get_relative_git_or_bufdir()

  if mode == 'files' then
    return no_ign .. depth1 .. hidden .. zip .. text .. type_p .. base .. ' Files> '
  elseif mode == 'fzf_rg' then
    return base .. ' rg/fzf> '
  else
    local fzf_rg = kwargs.fzf and 'fzf' or 'rg'
    return word .. depth1 .. no_ign .. hidden .. case_sym .. fixed .. max1 .. zip .. text .. type_p
        .. base .. ' ' .. fzf_rg .. '> '
  end
end

-- ── Main function ─────────────────────────────────────────────────────────────

function M.ripgrepfzf(fullscreen, dir, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then utils.warn('siefe: fzf-lua not found') return end

  if not dir or dir == '' then utils.warn('siefe: dir is empty') return end

  -- Set defaults
  kwargs.query          = kwargs.query          or ''
  kwargs.prompt         = kwargs.prompt         or utils.get_relative_git_or_bufdir()
  kwargs.word           = kwargs.word           ~= nil and kwargs.word or config.rg_default_word
  kwargs.depth1         = kwargs.depth1         ~= nil and kwargs.depth1 or config.rg_default_depth1
  kwargs.case_sensitive = kwargs.case_sensitive ~= nil and kwargs.case_sensitive or config.rg_default_case_sensitive
  kwargs.hidden         = kwargs.hidden         ~= nil and kwargs.hidden or config.rg_default_hidden
  kwargs.no_ignore      = kwargs.no_ignore      ~= nil and kwargs.no_ignore or config.rg_default_no_ignore
  kwargs.fixed_strings  = kwargs.fixed_strings  ~= nil and kwargs.fixed_strings or config.rg_default_fixed_strings
  kwargs.max_1          = kwargs.max_1          ~= nil and kwargs.max_1 or config.rg_default_max_1
  kwargs.search_zip     = kwargs.search_zip     ~= nil and kwargs.search_zip or config.rg_default_search_zip
  kwargs.text           = kwargs.text           ~= nil and kwargs.text or config.rg_default_text
  kwargs.orig_dir       = kwargs.orig_dir       or dir
  kwargs.paths          = kwargs.paths          or {}
  kwargs.type           = kwargs.type           or ''
  kwargs.files          = kwargs.files          ~= nil and kwargs.files or false
  kwargs.fzf            = kwargs.fzf            ~= nil and kwargs.fzf or config.rg_fzf_default
  kwargs.preview        = kwargs.preview        ~= nil and kwargs.preview or config.rg_default_preview_command

  -- Filter empty path entries
  local clean_paths = {}
  for _, p in ipairs(kwargs.paths) do
    if p ~= '' then table.insert(clean_paths, p) end
  end
  kwargs.paths = clean_paths

  -- Preview commands
  local previews = utils.make_preview_commands()
  local bat_opts = config.bat_options

  local default_size, other_size = utils.preview_window_size()

  -- Determine mode
  local mode
  if kwargs.files then
    mode = 'files'
  elseif kwargs.fzf then
    mode = 'fzf'
  else
    mode = 'rg'  -- live rg search (default)
  end

  -- Commands
  local cmd_fmt     = build_rg_command(kwargs, dir)
  local rg_command  = string.format(cmd_fmt, vim.fn.shellescape(kwargs.query))
  local reload_cmd  = string.format(cmd_fmt, '{q}')
  local files_cmd   = build_files_command(kwargs)

  local initial_source
  local preview_cmd
  if mode == 'files' then
    initial_source = files_cmd
    preview_cmd    = previews.files
  else
    initial_source = rg_command
    preview_cmd    = previews.rg[kwargs.preview + 1] or previews.rg[1]
  end

  -- Header info
  local name_info  = vim.fn.bufname() == '' and '[No Name]' or vim.fn.fnameescape(vim.fn.fnamemodify(vim.fn.bufname(), ':t'))
  local paths_info = #kwargs.paths == 0 and '' or ('\npaths: ' .. table.concat(vim.tbl_map(function(p)
    local parts = vim.split(p, '//', { plain = true })
    return parts[#parts]
  end, kwargs.paths), ' '))

  local no_ign_next = kwargs.no_ignore == 0 and '-u'
                   or kwargs.no_ignore == 1 and '-uu'
                   or kwargs.no_ignore == 2 and '-uuu'
                   or 'off'
  local fzf_rg     = kwargs.fzf and 'rg' or 'fzf'
  local rg_fzf_help_line = kwargs.fzf and '' or (' ╱ ' .. utils.prettify_header(config.rg_rgfzf_key, 'rg/fzf'))

  local header = utils.blue(name_info)
    .. '\n' .. utils.prettify_header(config.rg_toggle_fzf_key, fzf_rg)
    .. rg_fzf_help_line
    .. ' ╱ ' .. utils.prettify_header(config.rg_files_key, 'Files')
    .. ' ╱ ' .. utils.prettify_header(config.rg_type_key, '-t')
    .. ' ╱ ' .. utils.prettify_header(config.rg_type_not_key, '-T')
    .. ' ╱ ' .. utils.prettify_header(config.rg_buffers_key, 'Buffers')
    .. ' ╱ ' .. utils.prettify_header(config.rg_no_ignore_key, no_ign_next)
    .. ' ╱ ' .. utils.prettify_header(config.rg_hidden_key, '-.:' .. (kwargs.hidden and 'off' or 'on'))
    .. ' ╱ ' .. utils.prettify_header(config.rg_case_key, kwargs.case_sensitive == 1 and '-s' or kwargs.case_sensitive == 2 and '-i' or '-S')
    .. ' ╱ ' .. utils.prettify_header(config.rg_depth1_key, '-d1:' .. (kwargs.depth1 and 'off' or 'on'))
    .. '\n' .. utils.prettify_header(config.help_key, 'help')
    .. ' ╱ ' .. utils.prettify_header(config.rg_dir_key, 'cd')
    .. ' ╱ ' .. utils.prettify_header(config.rg_yank_key, 'yank')
    .. ' ╱ ' .. utils.prettify_header(config.rg_history_key, 'history')
    .. ' ╱ ' .. utils.prettify_header(config.rg_word_key, '-w:' .. (kwargs.word and 'off' or 'on'))
    .. ' ╱ ' .. utils.prettify_header(config.rg_fixed_strings_key, '-F:' .. (kwargs.fixed_strings and 'off' or 'on'))
    .. ' ╱ ' .. utils.prettify_header(config.rg_max_1_key, '-m1:' .. (kwargs.max_1 and 'off' or 'on'))
    .. ' ╱ ' .. utils.prettify_header(config.rg_search_zip_key, '-z:' .. (kwargs.search_zip and 'off' or 'on'))
    .. ' ╱ ' .. utils.prettify_header(config.rg_text_key, '--text:' .. (kwargs.text and 'off' or 'on'))
    .. ' ╱ ' .. utils.magenta(utils.preview_help({ config.rg_preview_key, config.rg_fast_preview_key, config.rg_faster_preview_key }), 'Special') .. ' change preview'
    .. '\n' .. utils.common_window_help()
    .. paths_info

  -- Build binds
  local p0 = previews.rg[1]
  local p1 = previews.rg[2]
  local p2 = previews.rg[3]
  local fp = previews.files

  local help_text = utils.prettify_help(config.help_key) .. '\t' .. 'show help'
    .. '\n' .. utils.prettify_help(config.rg_toggle_fzf_key) .. '\t' .. 'search with ' .. (kwargs.fzf and 'rg' or 'fzf')
    .. '\n' .. utils.prettify_help(config.rg_files_key) .. '\t' .. 'search files'
    .. '\n' .. utils.prettify_help(config.rg_type_key) .. '\t' .. 'select file type (-t)'
    .. '\n' .. utils.prettify_help(config.rg_type_not_key) .. '\t' .. 'exclude file type (-T)'
    .. '\n' .. utils.prettify_help(config.rg_buffers_key) .. '\t' .. 'toggle limit to open buffers'
    .. '\n' .. utils.prettify_help(config.rg_no_ignore_key) .. '\t' .. 'toggle ignored files'
    .. '\n' .. utils.prettify_help(config.rg_hidden_key) .. '\t' .. 'toggle hidden files'
    .. '\n' .. utils.prettify_help(config.rg_case_key) .. '\t' .. 'toggle case sensitivity'
    .. '\n' .. utils.prettify_help(config.rg_dir_key) .. '\t' .. 'change search directory'
    .. '\n' .. utils.prettify_help(config.rg_yank_key) .. '\t' .. 'yank selected lines'
    .. '\n' .. utils.prettify_help(config.rg_depth1_key) .. '\t' .. 'toggle depth-1 search'
    .. '\n' .. utils.prettify_help(config.rg_word_key) .. '\t' .. 'toggle word boundary'
    .. '\n' .. utils.prettify_help(config.rg_fixed_strings_key) .. '\t' .. 'toggle fixed strings'
    .. '\n' .. utils.prettify_help(config.rg_max_1_key) .. '\t' .. 'toggle max 1 match per file'
    .. '\n' .. utils.prettify_help(config.rg_search_zip_key) .. '\t' .. 'toggle compressed file search'
    .. '\n' .. utils.prettify_help(config.rg_text_key) .. '\t' .. 'toggle binary/text search'

  local binds = {
    'enter:ignore',
    'esc:ignore',
    config.accept_key           .. ':accept',
    config.up_key               .. ':up',
    config.down_key             .. ':down',
    config.next_history_key     .. ':next-history',
    config.previous_history_key .. ':previous-history',
    config.toggle_up_key        .. ':toggle+up',
    config.toggle_down_key      .. ':toggle+down',
    config.rg_preview_key       .. ':change-preview(' .. p0 .. ')',
    config.rg_fast_preview_key  .. ':change-preview(' .. p1 .. ')',
    config.rg_faster_preview_key.. ':change-preview(' .. p2 .. ')',
    config.toggle_preview_key   .. ':change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
    config.help_key             .. ':change-preview(echo -e "' .. help_text .. '")',
  }

  if mode == 'rg' then
    table.insert(binds, 'change:reload(' .. reload_cmd .. ')')
  end

  local fzf_opts = {
    ['--history']         = utils.data_path() .. '/rg_fzf_history',
    ['--ansi']            = '',
    ['--multi']           = '',
    ['--print-query']     = '',
    ['--delimiter']       = mode ~= 'files' and utils.rg_delimiter() or nil,
    ['--header']          = header,
    ['--prompt']          = build_prompt(kwargs, mode),
    ['--preview-window']  = (mode == 'files') and ('+{},' .. default_size) or ('+{2}-/2,' .. default_size),
    ['--bind']            = binds,
  }

  if mode == 'rg' then
    fzf_opts['--disabled'] = ''
  end

  -- ── Action handlers ───────────────────────────────────────────────────────

  local function get_query(selected, opts)
    if opts and opts.last_query then return opts.last_query end
    -- With --print-query, selected[1] may be the query
    -- We try to detect: if selected[1] doesn't look like an rg result, it's the query
    if selected and #selected > 0 then
      local first = selected[1]
      if not first:match(utils.rg_delimiter()) then return first end
    end
    return kwargs.query or ''
  end

  local function get_items(selected, opts)
    if opts and opts.last_query then return selected end
    -- Skip first element (query from --print-query) if it exists and doesn't look like an rg line
    if selected and #selected > 0 then
      local first = selected[1]
      if not first:match(utils.rg_delimiter()) then
        return vim.list_slice(selected, 2)
      end
    end
    return selected or {}
  end

  local function open_items(items, cmd)
    if not items or #items == 0 then return end
    local filelist = {}
    for _, line in ipairs(items) do
      local parsed = utils.parse_rg_line(line)
      if parsed then table.insert(filelist, parsed) end
    end
    if #filelist == 0 then return end
    local first = filelist[1]
    utils.open_file(cmd or 'edit', first.filename, first.lnum, first.col)
    if #filelist > 1 then
      local qf = vim.tbl_map(function(f)
        return { filename = f.filename, lnum = f.lnum, col = f.col, text = f.text }
      end, filelist)
      if config.rg_loclist then utils.fill_loc(qf) else utils.fill_quickfix(qf) end
    end
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
  end

  local actions = {}

  -- Default: open file
  actions['default'] = function(selected, opts)
    local items = get_items(selected, opts)
    open_items(items)
  end

  -- Window actions
  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = function(selected, opts)
      local items = get_items(selected, opts)
      if not items or #items == 0 then return end
      for _, line in ipairs(items) do
        local parsed = utils.parse_rg_line(line)
        if parsed then utils.open_file(c, parsed.filename, parsed.lnum, parsed.col) end
      end
      vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    end
  end

  -- Toggle: fzf/rg mode
  actions[config.rg_toggle_fzf_key] = function(selected, opts)
    local q = get_query(selected, opts)
    kwargs.query = q
    if kwargs.files then
      kwargs.files = false
    else
      kwargs.fzf = not kwargs.fzf
    end
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: rg/fzf filter (alt-f)
  actions[config.rg_rgfzf_key] = function(selected, opts)
    local q = get_query(selected, opts)
    kwargs.query = q
    kwargs.fzf = not kwargs.fzf
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: files mode
  actions[config.rg_files_key] = function(selected, opts)
    local q = get_query(selected, opts)
    kwargs.query = q
    kwargs.files = not kwargs.files
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: word boundary
  actions[config.rg_word_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.word = not kwargs.word
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: depth 1
  actions[config.rg_depth1_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.depth1 = not kwargs.depth1
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: case sensitivity (cycles 0→1→2→0)
  actions[config.rg_case_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.case_sensitive = (kwargs.case_sensitive + 1) % 3
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: hidden files
  actions[config.rg_hidden_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.hidden = not kwargs.hidden
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: no-ignore (cycles 0→1→2→3→0)
  actions[config.rg_no_ignore_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.no_ignore = (kwargs.no_ignore + 1) % 4
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: fixed strings
  actions[config.rg_fixed_strings_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.fixed_strings = not kwargs.fixed_strings
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: max 1
  actions[config.rg_max_1_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.max_1 = not kwargs.max_1
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: search zip
  actions[config.rg_search_zip_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.search_zip = not kwargs.search_zip
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Toggle: text (binary)
  actions[config.rg_text_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.text = not kwargs.text
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Type filter
  actions[config.rg_type_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    local ts = require('siefe.type_select')
    ts.type_select('rg', fullscreen, dir, kwargs)
  end

  actions[config.rg_type_not_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    local ts = require('siefe.type_select')
    ts.type_select('rg_not', fullscreen, dir, kwargs)
  end

  -- Dir select
  actions[config.rg_dir_key] = function(selected, opts)
    kwargs.query    = get_query(selected, opts)
    kwargs.fd_query = ''
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    local ds = require('siefe.dir_select')
    ds.dir_select(ds.ripgrep_dir_sink, fullscreen, dir, false, false, 'd', false, false, '', kwargs)
  end

  -- Buffers filter
  actions[config.rg_buffers_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    local bufs = vim.tbl_map(function(b)
      return vim.fn.fnamemodify(vim.fn.expand(vim.fn.bufname(b)), ':p:~:.')
    end, vim.tbl_filter(function(b) return vim.fn.buflisted(b) == 1 end, vim.api.nvim_list_bufs()))
    if vim.deep_equal(kwargs.paths, bufs) then
      kwargs.paths = {}
    else
      kwargs.paths = bufs
    end
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    M.ripgrepfzf(fullscreen, dir, kwargs)
  end

  -- Yank
  actions[config.rg_yank_key] = function(selected, opts)
    local items = get_items(selected, opts)
    local texts = {}
    for _, line in ipairs(items) do
      local parsed = utils.parse_rg_line(line)
      if parsed then table.insert(texts, parsed.text) end
    end
    utils.yank_to_register(table.concat(texts, '\n'))
  end

  -- History
  actions[config.rg_history_key] = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    vim.cmd('cd ' .. vim.fn.fnameescape(kwargs.orig_dir))
    if kwargs.files then
      local hist = require('siefe.history')
      hist.historyoldfiles(fullscreen, kwargs)
    else
      local git_dir = utils.get_git_root()
      local recent  = utils.recent_files(git_dir ~= '' and git_dir or nil)
      if vim.deep_equal(kwargs.paths, recent) then
        kwargs.paths = {}
        M.ripgrepfzf(fullscreen, kwargs.orig_dir, kwargs)
      else
        kwargs.paths = recent
        M.ripgrepfzf(fullscreen, git_dir ~= '' and git_dir or utils.bufdir(), kwargs)
      end
    end
  end

  -- Launch
  fzf_lua.fzf_exec(initial_source, {
    prompt    = build_prompt(kwargs, mode),
    query     = kwargs.query,
    cwd       = dir,
    winopts   = utils.winopts(fullscreen),
    previewer = false,
    preview   = preview_cmd,
    fzf_opts  = fzf_opts,
    actions   = actions,
  })
end

return M
