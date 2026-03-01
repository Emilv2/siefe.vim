-- lua/siefe/git_stash.lua
-- Git stash picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

function M.gitstash(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs.query = kwargs.query or ''
  kwargs.G = kwargs.G ~= nil and kwargs.G or config.gitlog_default_G
  kwargs.regex = kwargs.regex ~= nil and kwargs.regex or config.gitlog_default_regex
  kwargs.ignore_case = kwargs.ignore_case ~= nil and kwargs.ignore_case or config.gitlog_default_ignore_case

  local G = kwargs.G and '-G' or '-S'
  local G_prompt = kwargs.G and '-G ' or '-S '
  local regex = (not kwargs.G and kwargs.regex) and '--pickaxe-regex ' or ''
  local ignore_case = kwargs.ignore_case and '--regexp-ignore-case ' or ''
  local ic_sym = kwargs.ignore_case and '-i ' or ''

  local query_file = vim.fn.tempname()
  local format = '--format=%C(blue)%gd • %C(auto)%h • %s %C(green)%cr %C(reset)'
  local git_stashes = utils.bin_path('git_stashes')
  local git_SG = utils.bin_path('git_SG')
  local logger = utils.bin_path('logger') .. ' ' .. vim.fn.shellescape(utils.log_path()) .. ' '
  local remove_nl = '| sed -z -E "s/\\r?\\n/↵/g"'

  local cmd_fmt = git_stashes .. ' ' .. G .. '%s -z ' .. ' --color=always ' .. ' ' .. regex .. ' ' .. ignore_case

  local write_init = 'echo ' .. vim.fn.shellescape(kwargs.query) .. ' > ' .. query_file .. ' ;'
  local write_reload = 'echo {q} > ' .. query_file .. ' ;'

  local initial_cmd = logger
    .. write_init
    .. logger
    .. string.format(cmd_fmt, vim.fn.shellescape(kwargs.query))
    .. vim.fn.shellescape(format)
    .. remove_nl

  local reload_cmd = logger
    .. write_reload
    .. logger
    .. string.format(cmd_fmt, '{q}')
    .. vim.fn.shellescape(format)
    .. remove_nl

  -- Preview commands as dispatcher/toggle scripts (F7 cycles 4 modes).
  --   0 = all (patch+stat)   1 = matching files   2 = matching hunks   3 = diff
  local current =
    vim.fn.substitute(vim.fn.fnamemodify(vim.fn.expand('%'), ':p'), (vim.fn.FugitiveFind(':/') or '') .. '/', '', '')
  local orderfile = vim.fn.tempname()
  vim.fn.writefile({ current }, orderfile)
  local suffix = vim.fn.executable('delta') == 1 and ('| delta ' .. config.delta_options) or ''
  local git_root_cmd = '`git rev-parse --show-toplevel`'
  local pickaxe_diff = utils.bin_path('pickaxe-diff')
  local mode_file = vim.fn.tempname()
  vim.fn.writefile({ '0' }, mode_file)

  local function write_script(lines)
    local f = vim.fn.tempname()
    vim.fn.writefile(lines, f)
    vim.fn.setfperm(f, 'rwxr-xr-x')
    return f
  end

  local p0_script = write_script({
    '#!/bin/sh',
    'printf "\\033[0;35mgit show all\\033[0m\\n"',
    'git -C "$(git rev-parse --show-toplevel)"'
      .. ' show --color=always -O'
      .. vim.fn.shellescape(orderfile)
      .. ' "$1" --patch --stat --'
      .. (suffix ~= '' and (' ' .. suffix) or ''),
  })

  local p2_script = write_script({
    '#!/bin/sh',
    'printf "\\033[0;35mgit show matching files\\033[0m\\n"',
    'pattern=$(cat ' .. query_file .. ')',
    git_SG
      .. ' -C "$(git rev-parse --show-toplevel)"'
      .. ' show '
      .. G
      .. '"$pattern" -O'
      .. vim.fn.shellescape(orderfile)
      .. ' '
      .. regex
      .. '--color=always "$1" --format=format: --patch --stat --'
      .. (suffix ~= '' and (' ' .. suffix) or ''),
  })

  local p3_script
  if vim.fn.executable(pickaxe_diff) == 1 then
    p3_script = write_script({
      '#!/bin/sh',
      'printf "\\033[0;35mgit show matching hunks\\033[0m\\n"',
      'GREPDIFF_REGEX=$(cat ' .. query_file .. ')',
      'export GREPDIFF_REGEX',
      -- Pass -S or -G mode so pickaxe-diff uses the correct matching semantics.
      'GREPDIFF_MODE=' .. (kwargs.G and 'G' or 'S'),
      'export GREPDIFF_MODE',
      'git -C "$(git rev-parse --show-toplevel)"'
        .. ' -c diff.external='
        .. vim.fn.shellescape(pickaxe_diff)
        .. ' show "$1" -O'
        .. vim.fn.shellescape(orderfile)
        .. ' --ext-diff '
        .. regex
        .. G
        .. '"$GREPDIFF_REGEX"'
        .. ' --format=format: --patch --stat --'
        .. (suffix ~= '' and (' ' .. suffix) or ''),
    })
  else
    p3_script = write_script({
      '#!/bin/sh',
      'echo "run make build to compile siefe.vim Rust binaries"',
    })
  end

  local p4_script = write_script({
    '#!/bin/sh',
    'printf "\\033[0;35mgit diff\\033[0m\\n"',
    'git -C "$(git rev-parse --show-toplevel)"'
      .. ' diff --color=always -O'
      .. vim.fn.shellescape(orderfile)
      .. ' --patch --stat "$1" --'
      .. (suffix ~= '' and (' ' .. suffix) or ''),
  })

  local toggle_script = write_script({
    '#!/bin/sh',
    'mode=$(cat ' .. mode_file .. ' 2>/dev/null || echo 0)',
    'next=$(( (mode + 1) % 4 ))',
    'printf "%s" "$next" > ' .. mode_file,
  })

  local dispatcher_script = write_script({
    '#!/bin/sh',
    'mode=$(cat ' .. mode_file .. ' 2>/dev/null || echo 0)',
    'case $mode in',
    '  0) exec ' .. p0_script .. ' "$1" ;;',
    '  1) exec ' .. p2_script .. ' "$1" ;;',
    '  2) exec ' .. p3_script .. ' "$1" ;;',
    '  3) exec ' .. p4_script .. ' "$1" ;;',
    '  *) exec ' .. p0_script .. ' "$1" ;;',
    'esac',
  })

  local default_preview = dispatcher_script .. ' {1}'

  local default_size, other_size = utils.preview_window_size()
  local prompt = G_prompt .. regex .. ic_sym .. 'stash> '

  local stash_km = utils.make_binds({
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+down',
    [config.toggle_down_key] = 'toggle+up',
    [config.toggle_preview_key] = 'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
    -- F7 cycles through 4 preview modes via execute-silent + refresh-preview.
    [config.stash_preview_cycle_key] = {
      'execute-silent(' .. toggle_script .. ')+refresh-preview',
      desc = 'cycle-preview-mode',
    },
    ['change'] = 'first+reload(' .. reload_cmd .. ')',
    [config.stash_fzf_key] = 'unbind(change,'
      .. config.stash_fzf_key
      .. ')+change-prompt(stash/fzf> )+enable-search+rebind('
      .. config.stash_s_key
      .. ')',
    [config.stash_s_key] = 'unbind(change,'
      .. config.stash_s_key
      .. ')+change-prompt('
      .. prompt
      .. ')+disable-search+reload('
      .. reload_cmd
      .. ')+rebind(change,'
      .. config.stash_fzf_key
      .. ')',
  })

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

  local function get_stash(line)
    return vim.trim(vim.split(line, '•')[1])
  end

  local actions = {}

  actions['default'] = {
    fn = function(selected, opts)
      -- No default action for stash (open Gedit of the stash commit)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local stash = get_stash(items[1])
      pcall(vim.cmd, 'Gedit ' .. stash)
    end,
    desc = 'open',
  }

  actions[config.stash_apply_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      for _, line in ipairs(items) do
        vim.cmd('Git stash apply ' .. get_stash(line))
      end
    end,
    desc = 'apply',
  }

  actions[config.stash_pop_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      for _, line in ipairs(items) do
        vim.cmd('Git stash pop ' .. get_stash(line))
      end
    end,
    desc = 'pop',
  }

  actions[config.stash_drop_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      for _, line in ipairs(items) do
        vim.cmd('Git stash drop ' .. get_stash(line))
      end
    end,
    desc = 'drop',
  }

  actions[config.stash_sg_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.G = not kwargs.G
      M.gitstash(fullscreen, kwargs)
    end,
    desc = 'S/G',
  }

  actions[config.stash_ignore_case_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.ignore_case = not kwargs.ignore_case
      M.gitstash(fullscreen, kwargs)
    end,
    desc = '-i',
  }

  actions[config.stash_pickaxe_regex_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.regex = not kwargs.regex
      M.gitstash(fullscreen, kwargs)
    end,
    desc = 'regex',
  }

  fzf_lua.fzf_exec(initial_cmd, {
    prompt = prompt,
    query = kwargs.query,
    cwd = utils.get_git_root(),
    winopts = utils.winopts(fullscreen),
    previewer = false,
    preview = default_preview,
    fzf_opts = {
      ['--history'] = utils.data_path() .. '/rg_branch_history',
      ['--ansi'] = '',
      ['--multi'] = '',
      ['--read0'] = '',
      ['--print-query'] = '',
      ['--disabled'] = '',
      ['--delimiter'] = '•',
      ['--preview-window'] = default_size,
    },
    keymap = stash_km,
    actions = actions,
  })
end

return M
