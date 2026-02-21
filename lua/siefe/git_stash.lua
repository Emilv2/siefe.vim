-- lua/siefe/git_stash.lua
-- Git stash picker
local M = {}

local config = require('siefe.config')
local utils  = require('siefe.utils')

function M.gitstash(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then utils.warn('siefe: fzf-lua not found') return end

  kwargs.query       = kwargs.query       or ''
  kwargs.G           = kwargs.G           ~= nil and kwargs.G or config.gitlog_default_G
  kwargs.regex       = kwargs.regex       ~= nil and kwargs.regex or config.gitlog_default_regex
  kwargs.ignore_case = kwargs.ignore_case ~= nil and kwargs.ignore_case or config.gitlog_default_ignore_case

  local G            = kwargs.G and '-G' or '-S'
  local G_prompt     = kwargs.G and '-G ' or '-S '
  local regex        = (not kwargs.G and kwargs.regex) and '--pickaxe-regex ' or ''
  local ignore_case  = kwargs.ignore_case and '--regexp-ignore-case ' or ''
  local ic_sym       = kwargs.ignore_case and '-i ' or ''

  local query_file   = vim.fn.tempname()
  local format       = '--format=%C(blue)%gd • %C(auto)%h • %s %C(green)%cr %C(reset)'
  local git_stashes  = utils.bin_path('git_stashes')
  local git_SG       = utils.bin_path('git_SG')
  local logger       = utils.bin_path('logger') .. ' ' .. vim.fn.shellescape(utils.log_path()) .. ' '
  local remove_nl    = '| sed -z -E "s/\\r?\\n/↵/g"'

  local cmd_fmt = git_stashes
    .. ' ' .. G .. '%s -z '
    .. ' --color=always '
    .. ' ' .. regex
    .. ' ' .. ignore_case

  local write_init   = 'echo ' .. vim.fn.shellescape(kwargs.query) .. ' > ' .. query_file .. ' ;'
  local write_reload = 'echo {q} > ' .. query_file .. ' ;'

  local initial_cmd = logger .. write_init .. logger
    .. string.format(cmd_fmt, vim.fn.shellescape(kwargs.query))
    .. vim.fn.shellescape(format) .. remove_nl

  local reload_cmd = logger .. write_reload .. logger
    .. string.format(cmd_fmt, '{q}')
    .. vim.fn.shellescape(format) .. remove_nl

  -- Preview commands
  local current   = vim.fn.substitute(vim.fn.fnamemodify(vim.fn.expand('%'), ':p'), (vim.fn.FugitiveFind(':/') or '') .. '/', '', '')
  local orderfile = vim.fn.tempname()
  vim.fn.writefile({ current }, orderfile)
  local suffix    = vim.fn.executable('delta') == 1 and ('| delta ' .. config.delta_options) or ''
  local git_root_cmd = '`git rev-parse --show-toplevel`'

  local pa = 'echo -e "\\033[0;35mgit show all\\033[0m" && git -C ' .. git_root_cmd
    .. ' show --color=always -O' .. vim.fn.shellescape(orderfile) .. ' {1} '
  local p0 = pa .. ' --patch --stat -- ' .. suffix
  local p1 = pa .. ' --format=format: --patch -- ' .. suffix
  local p2 = 'echo -e "\\033[0;35mgit show matching files\\033[0m" && '
    .. git_SG .. ' -C ' .. git_root_cmd .. ' show ' .. G .. '"`cat ' .. query_file .. '`" -O' .. vim.fn.shellescape(orderfile)
    .. ' ' .. regex .. '--color=always {1} --format=format: --patch --stat -- ' .. suffix
  local pickaxe_diff = utils.bin_path('pickaxe-diff')
  local p3
  if vim.fn.executable(pickaxe_diff) == 1 then
    p3 = ' bash -c \''
      .. ' echo -e "\\033[0;35mgit show matching hunks\\033[0m" && '
      .. '(export GREPDIFF_REGEX=`cat ' .. query_file .. '`; '
      .. 'git -C ' .. git_root_cmd .. ' -c diff.external=' .. pickaxe_diff
      .. ' show {1} -O' .. vim.fn.shellescape(orderfile) .. ' --ext-diff ' .. regex .. G
      .. '"`cat ' .. query_file .. '`" --format=format: --patch --stat --) \''
      .. suffix
  else
    p3 = 'echo run "make build" to compile siefe.vim binaries'
  end
  local p4 = 'echo -e "\\033[0;35mgit diff\\033[0m" && git -C ' .. git_root_cmd
    .. ' diff --color=always -O' .. vim.fn.shellescape(orderfile) .. ' --patch --stat {1} -- ' .. suffix

  local preview_cmds   = { p0, p1, p2, p3, p4 }
  local default_preview = preview_cmds[(config.stash_default_preview_command or 0) + 1] or p0

  local default_size, other_size = utils.preview_window_size()
  local prompt = G_prompt .. regex .. ic_sym .. 'stash> '

  local header = G_prompt .. regex .. ic_sym .. 'stash'

  local stash_km, stash_cli = utils.make_binds({
    [config.up_key]                 = 'up',
    [config.down_key]               = 'down',
    [config.next_history_key]       = 'next-history',
    [config.previous_history_key]   = 'previous-history',
    [config.toggle_up_key]          = 'toggle+down',
    [config.toggle_down_key]        = 'toggle+up',
    [config.toggle_preview_key]     = 'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
  }, {
    config.stash_preview_0_key  .. ':change-preview(' .. p0 .. ')',
    config.stash_preview_1_key  .. ':change-preview(' .. p1 .. ')',
    config.stash_preview_2_key  .. ':change-preview(' .. p2 .. ')',
    config.stash_preview_3_key  .. ':change-preview(' .. p3 .. ')',
    config.stash_preview_4_key  .. ':change-preview(' .. p4 .. ')',
    'change:first+reload(' .. reload_cmd .. ')',
    config.stash_fzf_key .. ':unbind(change,' .. config.stash_fzf_key .. ')+change-prompt(stash/fzf> )+enable-search+rebind(' .. config.stash_s_key .. ')',
    config.stash_s_key .. ':unbind(change,' .. config.stash_s_key .. ')+change-prompt(' .. prompt .. ')+disable-search+reload(' .. reload_cmd .. ')+rebind(change,' .. config.stash_fzf_key .. ')',
  })

  local function get_query(selected, opts)
    if opts and opts.last_query then return opts.last_query end
    if selected and #selected > 0 and not selected[1]:match('•') then return selected[1] end
    return kwargs.query or ''
  end

  local function get_items(selected, opts)
    if opts and opts.last_query then return selected end
    if selected and #selected > 0 and not selected[1]:match('•') then
      return vim.list_slice(selected, 2)
    end
    return selected or {}
  end

  local function get_stash(line)
    return vim.trim(vim.split(line, '•')[1])
  end

  local actions = {}

  actions['default'] = { fn = function(selected, opts)
    -- No default action for stash (open Gedit of the stash commit)
    local items = get_items(selected, opts)
    if #items == 0 then return end
    local stash = get_stash(items[1])
    pcall(vim.cmd, 'Gedit ' .. stash)
  end, header = 'open' }

  actions[config.stash_apply_key] = { fn = function(selected, opts)
    local items = get_items(selected, opts)
    for _, line in ipairs(items) do
      vim.cmd('Git stash apply ' .. get_stash(line))
    end
  end, header = 'apply' }

  actions[config.stash_pop_key] = { fn = function(selected, opts)
    local items = get_items(selected, opts)
    for _, line in ipairs(items) do
      vim.cmd('Git stash pop ' .. get_stash(line))
    end
  end, header = 'pop' }

  actions[config.stash_drop_key] = { fn = function(selected, opts)
    local items = get_items(selected, opts)
    for _, line in ipairs(items) do
      vim.cmd('Git stash drop ' .. get_stash(line))
    end
  end, header = 'drop' }

  actions[config.stash_sg_key] = { fn = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.G = not kwargs.G
    M.gitstash(fullscreen, kwargs)
  end, header = 'S/G' }

  actions[config.stash_ignore_case_key] = { fn = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.ignore_case = not kwargs.ignore_case
    M.gitstash(fullscreen, kwargs)
  end, header = '-i' }

  actions[config.stash_pickaxe_regex_key] = { fn = function(selected, opts)
    kwargs.query = get_query(selected, opts)
    kwargs.regex = not kwargs.regex
    M.gitstash(fullscreen, kwargs)
  end, header = 'regex' }

  fzf_lua.fzf_exec(initial_cmd, {
    prompt        = prompt,
    query         = kwargs.query,
    cwd           = utils.get_git_root(),
    winopts       = utils.winopts(fullscreen),
    previewer     = false,
    preview       = default_preview,
    fzf_opts      = {
      ['--history']        = utils.data_path() .. '/rg_branch_history',
      ['--ansi']           = '',
      ['--multi']          = '',
      ['--read0']          = '',
      ['--print-query']    = '',
      ['--disabled']       = '',
      ['--layout']         = 'reverse-list',
      ['--delimiter']      = '•',
      ['--preview-window'] = default_size,
      ['--header']         = header,
    },
    keymap        = stash_km,
    _fzf_cli_args = stash_cli,
    actions = actions,
  })
end

return M
