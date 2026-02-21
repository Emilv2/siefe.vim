-- lua/siefe/git_branch.lua
-- Git branch picker
local M = {}

local config = require('siefe.config')
local utils  = require('siefe.utils')

local branch_source = "git branch -a --sort='-authordate' --color "
  .. "--format='"
  .. "%(HEAD) %(if:equals=refs/remotes)%(refname:rstrip=-2)%(then)%(color:cyan)%(align:0)%(refname:lstrip=2)%(end)"
  .. "%(else)%(if)%(HEAD)%(then)%(color:reverse yellow)%(align:0)%(refname:lstrip=-1)%(end)"
  .. "%(else)%(color:yellow)%(align:0)%(refname:lstrip=-1)%(end)%(end)%(end)"
  .. "%(color:reset) %(color:red): "
  .. "%(if)%(symref)%(then)%(color:yellow)%(objectname:short)%(color:reset) %(color:red):%(color:reset) %(color:green)-> %(symref:lstrip=-2)"
  .. "%(else)%(color:yellow)%(objectname:short)%(color:reset) "
  .. "%(if)%(upstream)%(then)%(color:red): %(color:reset)%(color:green)[%(upstream:short)"
  .. "%(if)%(upstream:track)%(then):%(color:blue)%(upstream:track,nobracket)%(symref:lstrip=-2)%(color:green)%(end)]%(color:reset) %(end)"
  .. "%(color:red):%(color:reset) %(contents:subject)%(end) • %(color:blue)(%(authordate:short))'"

-- Low-level branch picker; callback receives (lines) where lines[1]=key, lines[2:]=selected
function M.branch_select(callback, fullscreen, is_not, standalone)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then utils.warn('siefe: fzf-lua not found') return end

  local not_prefix = is_not and '^' or ''
  local has_all    = not is_not

  local p0 = 'echo -e "\\033[0;35m"git log {1}"\\033[0m" ; echo {2} -- | xargs git log --color=always --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  local p1 = 'echo -e "\\033[0;35m"git log ..{1} \\(what they have\\)"\\033[0m"; echo ..{2} -- | xargs git log --color=always --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  local p2 = 'echo -e "\\033[0;35m"git log {1}.. \\(what we have\\)"\\033[0m"; echo {2}.. -- | xargs git log --color=always --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  local p3 = 'echo -e "\\033[0;35m"git log {1}... \\(common ancestor\\)"\\033[0m"; echo {2}... -- | xargs git log --color=always --format="%m%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'

  local default_size, other_size = utils.preview_window_size()

  -- Build extra keys/help
  local extra_help = ''
  if standalone then
    extra_help = utils.prettify_header(config.branches_switch_key, 'switch')
      .. ' ╱ ' .. utils.prettify_header(config.branches_merge_key, 'merge')
      .. ' ╱ ' .. utils.prettify_header(config.branches_rebase_interactive_key, 'rebase -i')
  elseif has_all then
    extra_help = ' ╱ ' .. utils.prettify_header(config.branches_all_key, '--all')
  end

  local header = (is_not and '^' or '') .. 'branches'
    .. (standalone and '' or (has_all and ' ╱ --all' or ''))

  local br_km, br_cli = utils.make_binds({
    ['change']                      = 'first',
    [config.up_key]                 = 'up',
    [config.down_key]               = 'down',
    [config.next_history_key]       = 'next-history',
    [config.previous_history_key]   = 'previous-history',
    [config.toggle_up_key]          = 'toggle+up',
    [config.toggle_down_key]        = 'toggle+down',
    [config.toggle_preview_key]     = 'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
  }, {
    config.gitbranch_preview_0_key .. ':change-preview(' .. p0 .. ')',
    config.gitbranch_preview_1_key .. ':change-preview(' .. p1 .. ')',
    config.gitbranch_preview_2_key .. ':change-preview(' .. p2 .. ')',
    config.gitbranch_preview_3_key .. ':change-preview(' .. p3 .. ')',
  })

  local fzf_opts = {
    ['--history']     = utils.data_path() .. '/rg_branch_history',
    ['--ansi']        = '',
    ['--delimiter']   = ':',
    ['--preview-window'] = '~1,' .. default_size,
    ['--header']      = header,
    ['--prompt']      = not_prefix .. 'branches> ',
  }

  if standalone then
    fzf_opts['--print-query'] = ''
  else
    fzf_opts['--multi'] = ''
  end

  local actions = {}

  actions['default'] = { fn = function(selected, opts)
    local items = selected or {}
    if standalone then
      callback({ '', unpack(items) })
    else
      callback({ '', unpack(items) })
    end
  end, header = 'select' }

  actions[config.abort_key] = { fn = function(selected, opts)
    callback({ config.abort_key })
  end, header = 'abort' }

  if has_all and not standalone then
    actions[config.branches_all_key] = { fn = function(selected, opts)
      callback({ config.branches_all_key })
    end, header = '--all' }
  end

  if standalone then
    actions[config.branches_switch_key] = { fn = function(selected, opts)
      callback({ config.branches_switch_key, unpack(selected or {}) })
    end, header = 'switch' }
    actions[config.branches_merge_key] = { fn = function(selected, opts)
      callback({ config.branches_merge_key, unpack(selected or {}) })
    end, header = 'merge' }
    actions[config.branches_rebase_interactive_key] = { fn = function(selected, opts)
      callback({ config.branches_rebase_interactive_key, unpack(selected or {}) })
    end, header = 'rebase -i' }
  end

  fzf_lua.fzf_exec(branch_source, {
    prompt        = not_prefix .. 'branches> ',
    cwd           = utils.get_git_root(),
    winopts       = utils.winopts(fullscreen),
    previewer     = false,
    preview       = p0,
    fzf_opts      = fzf_opts,
    keymap        = br_km,
    _fzf_cli_args = br_cli,
    actions       = actions,
  })
end

-- Author picker
function M.author_select(callback, fullscreen)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then utils.warn('siefe: fzf-lua not found') return end

  local source = "git log --format='%aN <%aE>' | awk '!x[$0]++'"

  local au_km, au_cli = utils.make_binds({
    ['change']                      = 'first',
    [config.up_key]                 = 'up',
    [config.down_key]               = 'down',
    [config.next_history_key]       = 'next-history',
    [config.previous_history_key]   = 'previous-history',
    [config.toggle_up_key]          = 'toggle+up',
    [config.toggle_down_key]        = 'toggle+down',
  }, {})

  local actions = {}
  actions['default'] = { fn = function(selected, opts)
    callback({ '', unpack(selected or {}) })
  end, header = 'select' }
  actions[config.abort_key] = { fn = function(selected, opts)
    callback({ config.abort_key })
  end, header = 'abort' }

  fzf_lua.fzf_exec(source, {
    prompt        = 'authors> ',
    cwd           = utils.get_git_root(),
    winopts       = utils.winopts(fullscreen),
    previewer     = false,
    fzf_opts      = {
      ['--history']     = utils.data_path() .. '/rg_author_history',
      ['--multi']       = '',
      ['--ansi']        = '',
      ['--header']      = utils.prettify_header(config.abort_key, 'abort'),
    },
    keymap        = au_km,
    _fzf_cli_args = au_cli,
    actions = actions,
  })
end

-- Public: open standalone branch picker
function M.gitbranch(fullscreen)
  M.branch_select(function(lines)
    local key    = lines[1] or ''
    local branch = #lines >= 2 and vim.trim(vim.split(lines[2] or '', ':')[1]) or ''

    if key == config.branches_switch_key and branch ~= '' then
      vim.cmd('Git switch ' .. branch)
      -- Handle errors (simplified – show result)
      local result = vim.fn.FugitiveResult and vim.fn.FugitiveResult() or { exit_status = 0 }
      if (result.exit_status or 0) ~= 0 then
        local action = vim.fn.input(table.concat(vim.fn.readfile(result.file or ''), '\n') .. ' Error. Stash, open fugitive or abort? (s/f/a) ')
        if action == 's' then
          vim.cmd('Git stash')
          vim.cmd('Git switch ' .. branch)
        elseif action == 'f' then
          vim.cmd('Git')
        end
      end

    elseif key == config.branches_rebase_interactive_key and branch ~= '' then
      vim.cmd('Git rebase -i ' .. branch)

    elseif key == config.branches_merge_key and branch ~= '' then
      vim.cmd('Git merge ' .. branch)
    end
  end, fullscreen, false, true)
end

return M
