-- lua/siefe/git_log.lua
-- Git log / pickaxe search picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

function M.gitlogfzf(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  -- Defaults
  kwargs.query = kwargs.query or ''
  kwargs.branches = kwargs.branches or ''
  kwargs.notbranches = kwargs.notbranches or ''
  kwargs.authors = kwargs.authors or {}
  kwargs.G = kwargs.G ~= nil and kwargs.G or config.gitlog_default_G
  kwargs.regex = kwargs.regex ~= nil and kwargs.regex or config.gitlog_default_regex
  kwargs.paths = kwargs.paths or {}
  kwargs.follow = kwargs.follow ~= nil and kwargs.follow or config.gitlog_default_follow
  kwargs.ignore_case = kwargs.ignore_case ~= nil and kwargs.ignore_case or config.gitlog_default_ignore_case
  kwargs.type = kwargs.type or {}
  kwargs.line_range = kwargs.line_range or {}
  kwargs.fixup = kwargs.fixup or 0

  -- Strip fugitive headers from paths
  kwargs.paths = vim.tbl_map(utils.fugitive_strip_header, kwargs.paths)

  -- Build flags
  local branches = kwargs.branches == '--all' and '--all ' or (kwargs.branches ~= '' and (kwargs.branches .. ' ') or '')
  local notbranches = kwargs.notbranches ~= '' and (kwargs.notbranches .. ' ') or ''
  local authors = table.concat(
    vim.tbl_map(function(a)
      return '--author=' .. vim.fn.shellescape(a)
    end, kwargs.authors),
    ' '
  )

  local G = kwargs.G and '-G' or '-S'
  local G_prompt = kwargs.G and '-G ' or '-S '
  local regex = (not kwargs.G and kwargs.regex) and '--pickaxe-regex ' or ''
  local ignore_case = kwargs.ignore_case and '--regexp-ignore-case ' or ''
  local ic_sym = kwargs.ignore_case and '-i ' or ''
  local remove_nl = '| sed -z -E "s/\\r?\\n/↵/g"'

  -- Determine whether follow is applicable
  local valid_paths = vim.tbl_filter(function(p)
    return utils.git_file_existed(p) or vim.fn.isdirectory(p) == 1
  end, kwargs.paths)

  local follow = ''
  if #kwargs.paths == 1 and #kwargs.line_range == 0 and #valid_paths == 1 then
    follow = kwargs.follow and '--follow ' or ''
  end

  -- Build paths for git command
  local paths_str
  if #kwargs.type > 0 and #kwargs.paths > 0 then
    local p = {}
    for _, path in ipairs(kwargs.paths) do
      if path:sub(-1) == '/' then
        for _, t in ipairs(kwargs.type) do
          table.insert(p, vim.fn.shellescape(path .. t))
        end
      else
        table.insert(p, vim.fn.shellescape(path))
      end
    end
    paths_str = table.concat(p, ' ')
  elseif #kwargs.type > 0 then
    paths_str = table.concat(vim.tbl_map(vim.fn.shellescape, kwargs.type), ' ')
  else
    paths_str = table.concat(
      vim.tbl_map(function(p)
        return (utils.git_file_existed(p) or vim.fn.isdirectory(p) == 1) and vim.fn.shellescape(p) or nil
      end, kwargs.paths),
      ' '
    )
  end

  -- Query file for preview commands
  local query_file = vim.fn.tempname()
  local format = '--format=%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)%b'
  local git_SG = utils.bin_path('git_SG')
  local git_root_cmd = '`git rev-parse --show-toplevel`'

  local current =
    vim.fn.substitute(vim.fn.fnamemodify(vim.fn.expand('%'), ':p'), (vim.fn.FugitiveFind(':/') or '') .. '/', '', '')
  local orderfile = vim.fn.tempname()
  vim.fn.writefile({ current }, orderfile)

  local suffix = vim.fn.executable('delta') == 1 and ('| delta ' .. config.delta_options) or ''

  -- Build commands
  local cmd_fmt
  local initial_command
  local reload_command
  local line_range_str = ''

  if #kwargs.line_range > 0 then
    line_range_str = '-L' .. kwargs.line_range[1] .. ',' .. kwargs.line_range[2] .. ':'
    initial_command = 'git log --no-patch -z -L'
      .. kwargs.line_range[1]
      .. ','
      .. kwargs.line_range[2]
      .. ':'
      .. paths_str
      .. ' '
      .. branches
      .. notbranches
      .. authors
      .. regex
      .. ignore_case
      .. ' --color=always --abbrev-commit -- '
      .. ' | sed -E -z "s/commit ([0-9a-f]*)([^\\n]*)*.*\\n\\n/\\1\\2 •/" '
      .. ' | sed -E -z "s/[ ][ ]*/ /g"'
      .. remove_nl
    reload_command = ''
    query_file = '/dev/null'
    G_prompt = ''
  else
    cmd_fmt = git_SG
      .. ' -C '
      .. git_root_cmd
      .. ' log '
      .. G
      .. '%s -z '
      .. ' --color=always '
      .. follow
      .. ' '
      .. branches
      .. notbranches
      .. authors
      .. regex
      .. ignore_case

    local write_init = 'echo ' .. vim.fn.shellescape(kwargs.query) .. ' > ' .. query_file .. ' ;'
    local write_reload = 'echo {q} > ' .. query_file .. ' ;'
    local logger = utils.bin_path('logger') .. ' ' .. vim.fn.shellescape(utils.log_path()) .. ' '

    initial_command = logger
      .. write_init
      .. logger
      .. string.format(cmd_fmt, vim.fn.shellescape(kwargs.query))
      .. vim.fn.shellescape(format)
      .. ' -- '
      .. paths_str
      .. remove_nl

    reload_command = logger
      .. write_reload
      .. logger
      .. string.format(cmd_fmt, '{q}')
      .. vim.fn.shellescape(format)
      .. ' -- '
      .. paths_str
      .. remove_nl
  end
  local pa = 'echo -e "\\033[0;35mgit show all\\033[0m" && git -C '
    .. git_root_cmd
    .. ' show --color=always -O'
    .. vim.fn.shellescape(orderfile)
    .. ' {1} '
  local p0 = pa .. ' --patch --stat -- ' .. suffix
  local p1 = pa .. ' --format=format: -- ' .. suffix
  local p2 = 'echo -e "\\033[0;35mgit show matching files\\033[0m" && '
    .. git_SG
    .. ' -C '
    .. git_root_cmd
    .. ' show '
    .. G
    .. '"`cat '
    .. query_file
    .. '`" -O'
    .. vim.fn.shellescape(orderfile)
    .. ' '
    .. regex
    .. '--color=always {1} --format=format: --patch --stat -- '
    .. suffix
  local pickaxe_diff = utils.bin_path('pickaxe-diff')
  local p3
  if vim.fn.executable(pickaxe_diff) == 1 then
    p3 = " bash -c '"
      .. ' echo -e "\\033[0;35mgit show matching hunks\\033[0m" && '
      .. '(export GREPDIFF_REGEX=`cat '
      .. query_file
      .. '`; '
      .. git_SG
      .. ' -C '
      .. git_root_cmd
      .. ' -c diff.external='
      .. pickaxe_diff
      .. ' show {1} -O'
      .. vim.fn.shellescape(orderfile)
      .. ' --ext-diff '
      .. regex
      .. G
      .. '"`cat '
      .. query_file
      .. '`" --format=format: --patch --stat --) \''
      .. suffix
  else
    p3 = 'echo run "make build" to compile siefe.vim binaries'
  end
  local p4 = 'echo -e "\\033[0;35mgit diff\\033[0m" && git -C '
    .. git_root_cmd
    .. ' diff --color=always -O'
    .. vim.fn.shellescape(orderfile)
    .. ' --patch --stat {1} -- '
    .. suffix

  local preview_cmds = { p0, p1, p2, p3, p4 }
  local default_preview = preview_cmds[(config.gitlog_default_preview_command or 0) + 1] or p0

  -- Authors / paths info
  local authors_info = #kwargs.authors == 0 and '' or ('\nauthors: ' .. table.concat(kwargs.authors, ' '))
  local rel_paths = table.concat(
    vim.tbl_map(function(p)
      return utils.get_relative_git_or_bufdir(p)
    end, valid_paths),
    ' '
  )
  local paths_info = rel_paths == '' and '' or ('\npaths: ' .. rel_paths)

  local default_size, other_size = utils.preview_window_size()

  -- Header
  local header = G_prompt
    .. regex
    .. ic_sym
    .. follow
    .. (kwargs.branches ~= '' and 'branches:' .. kwargs.branches .. ' ' or '')
    .. (kwargs.notbranches ~= '' and '^branches:' .. kwargs.notbranches .. ' ' or '')
    .. authors_info
    .. paths_info

  local prompt = branches .. notbranches .. G_prompt .. regex .. ic_sym .. follow .. line_range_str .. 'pickaxe> '

  local gl_binds = {
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+down',
    [config.toggle_down_key] = 'toggle+up',
    [config.toggle_preview_key] = 'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
    [config.gitlog_preview_0_key] = 'change-preview(' .. p0 .. ')',
    [config.gitlog_preview_1_key] = 'change-preview(' .. p1 .. ')',
    [config.gitlog_preview_2_key] = 'change-preview(' .. p2 .. ')',
    [config.gitlog_preview_3_key] = 'change-preview(' .. p3 .. ')',
    [config.gitlog_preview_4_key] = 'change-preview(' .. p4 .. ')',
  }

  if #kwargs.line_range == 0 then
    gl_binds['change'] = 'first+reload(' .. reload_command .. ')'
    gl_binds[config.gitlog_fzf_key] = 'unbind(change,'
      .. config.gitlog_fzf_key
      .. ')+change-prompt(pickaxe/fzf> )+enable-search+rebind('
      .. config.gitlog_s_key
      .. ')'
    gl_binds[config.gitlog_s_key] = 'unbind(change,'
      .. config.gitlog_s_key
      .. ')+change-prompt('
      .. prompt
      .. ')+disable-search+reload('
      .. reload_command
      .. ')+rebind(change,'
      .. config.gitlog_fzf_key
      .. ')'
  else
    gl_binds['change'] = 'first'
  end
  local gl_km = utils.make_binds(gl_binds)

  local fzf_opts = {
    ['--history'] = utils.data_path() .. '/git_fzf_history',
    ['--ansi'] = '',
    ['--read0'] = '',
    ['--print-query'] = '',
    ['--layout'] = 'reverse-list',
    ['--delimiter'] = '•',
    ['--preview-window'] = default_size,
    ['--prompt'] = prompt,
  }

  if kwargs.fixup == 0 then
    fzf_opts['--multi'] = ''
  end

  if #kwargs.line_range == 0 then
    fzf_opts['--disabled'] = ''
    fzf_opts['--query'] = kwargs.query
  end

  -- ── Action helpers ──────────────────────────────────────────────────────────

  local function get_query(selected, opts)
    if opts and opts.last_query then
      return opts.last_query
    end
    if selected and #selected > 0 and not selected[1]:match('•') then
      return selected[1]
    end
    return kwargs.query or ''
  end

  local function get_items(selected, opts)
    if opts and opts.last_query then
      return selected
    end
    if selected and #selected > 0 and not selected[1]:match('•') then
      return vim.list_slice(selected, 2)
    end
    return selected or {}
  end

  local function get_hash(line)
    return vim.split(line, ' ')[1]
  end

  -- ── Actions ─────────────────────────────────────────────────────────────────

  local actions = {}

  actions['default'] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local hash = get_hash(items[1])
      local qf = vim.tbl_map(function(line)
        local h = get_hash(line)
        local msg = table.concat(vim.list_slice(vim.split(line, ' '), 2), ' ')
        return {
          bufnr = vim.fn.bufadd(vim.trim(vim.fn.system('git show -s --format=%H ' .. h))),
          text = msg:sub(1, vim.o.columns - 10),
          module = h,
        }
      end, items)
      vim.cmd('Gedit ' .. hash)
      if config.gitlog_loclist then
        utils.fill_loc(qf)
      else
        utils.fill_quickfix(qf)
      end
    end,
    header = 'open',
  }

  -- Window actions (fugitive)
  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    local fugitive_cmd = config.fugitive_window_actions[c] or c
    actions[k] = {
      fn = function(selected, opts)
        local items = get_items(selected, opts)
        for _, line in ipairs(items) do
          local h = get_hash(line)
          pcall(vim.cmd, 'silent ' .. fugitive_cmd .. ' ' .. h)
          vim.cmd('normal! zvzz')
        end
      end,
      header = 'open ' .. c,
    }
  end

  actions[config.gitlog_sg_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.G = not kwargs.G
      M.gitlogfzf(fullscreen, kwargs)
    end,
    header = 'S/G',
  }

  actions[config.gitlog_ignore_case_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.ignore_case = not kwargs.ignore_case
      M.gitlogfzf(fullscreen, kwargs)
    end,
    header = '-i',
  }

  actions[config.gitlog_pickaxe_regex_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.regex = not kwargs.regex
      M.gitlogfzf(fullscreen, kwargs)
    end,
    header = 'regex',
  }

  actions[config.gitlog_follow_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.follow = not kwargs.follow
      M.gitlogfzf(fullscreen, kwargs)
    end,
    header = 'follow',
  }

  actions[config.gitlog_branch_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      local gb = require('siefe.git_branch')
      gb.branch_select(function(blines)
        if blines[1] == config.abort_key then
          kwargs.branches = ''
        elseif blines[1] == config.branches_all_key then
          kwargs.branches = '--all'
        else
          kwargs.branches = table.concat(
            vim.tbl_map(function(l)
              return vim.trim(vim.split(l, ':')[1])
            end, vim.list_slice(blines, 2)),
            ' '
          )
        end
        M.gitlogfzf(fullscreen, kwargs)
      end, fullscreen, false, false)
    end,
    header = 'branches',
  }

  actions[config.gitlog_not_branch_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      local gb = require('siefe.git_branch')
      gb.branch_select(function(blines)
        if blines[1] == config.abort_key then
          kwargs.notbranches = ''
        else
          kwargs.notbranches = table.concat(
            vim.tbl_map(function(l)
              return '^' .. vim.trim(vim.split(l, ':')[1])
            end, vim.list_slice(blines, 2)),
            ' '
          )
        end
        M.gitlogfzf(fullscreen, kwargs)
      end, fullscreen, true, false)
    end,
    header = '^branches',
  }

  actions[config.gitlog_author_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      local gb = require('siefe.git_branch')
      gb.author_select(function(alines)
        if alines[1] == config.abort_key then
          kwargs.authors = {}
        else
          kwargs.authors = vim.list_slice(alines, 2)
        end
        M.gitlogfzf(fullscreen, kwargs)
      end, fullscreen)
    end,
    header = 'authors',
  }

  actions[config.gitlog_dir_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.fd_query = ''
      local ds = require('siefe.dir_select')
      ds.dir_select(
        ds.gitlog_path_sink,
        fullscreen,
        utils.bufdir(),
        false,
        false,
        '',
        true,
        false,
        utils.get_git_root(),
        kwargs
      )
    end,
    header = 'paths',
  }

  actions[config.gitlog_type_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      local ts = require('siefe.type_select')
      ts.type_select('gitlog', fullscreen, kwargs)
    end,
    header = 'type',
  }

  actions[config.gitlog_switch_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items ~= 1 then
        utils.warn('select exactly 1 commit for switch')
        M.gitlogfzf(fullscreen, kwargs)
        return
      end
      local commit = get_hash(items[1])
      local action = vim.fn.input('create branch? (y/n) ')
      if action == 'y' then
        vim.cmd('Git switch -c ' .. commit)
      elseif action == 'n' then
        vim.cmd('Git switch ' .. commit)
      end
    end,
    header = 'switch',
  }

  actions[config.gitlog_vdiffsplit_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 2 then
        local h1, h2 = get_hash(items[1]), get_hash(items[2])
        pcall(vim.cmd, 'Gedit ' .. h1 .. ':%')
        pcall(vim.cmd, 'Gvdiffsplit ' .. h2 .. ':%')
      elseif #items == 1 then
        local h = get_hash(items[1])
        pcall(vim.cmd, 'Gedit HEAD:%')
        pcall(vim.cmd, 'Gvdiffsplit ' .. h .. ':%')
      end
    end,
    header = 'diff',
  }

  -- Launch
  fzf_lua.fzf_exec(initial_command, {
    prompt = prompt,
    query = kwargs.query,
    cwd = utils.get_git_root(),
    winopts = utils.winopts(fullscreen),
    previewer = false,
    preview = default_preview,
    fzf_opts = fzf_opts,
    keymap = gl_km,
    actions = actions,
  })
end

return M
