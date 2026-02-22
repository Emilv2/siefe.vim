-- lua/siefe/git_status.lua
-- Git status picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

function M.gitstatus(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs.query = kwargs.query or ''
  kwargs.paths = kwargs.paths or {}
  kwargs.uno = kwargs.uno ~= nil and kwargs.uno or false

  local uno_flag = kwargs.uno and ' -uno ' or ''
  local rel_paths = table.concat(
    vim.tbl_map(
      function(p)
        return utils.get_relative_git_or_bufdir(p)
      end,
      vim.tbl_filter(function(p)
        return vim.fn.filereadable(p) == 1 or vim.fn.isdirectory(p) == 1
      end, kwargs.paths)
    ),
    ' '
  )
  local paths_info = rel_paths == '' and '' or ('\npaths: ' .. rel_paths)

  local git_root = utils.get_git_root()

  -- Get git colours once (these are raw ANSI escape sequences)
  local c_added = vim.fn.system({ 'git', 'config', '--get-color', 'color.status.added', 'yellow' })
  local c_changed = vim.fn.system({ 'git', 'config', '--get-color', 'color.status.changed', 'green' })
  local c_untracked = vim.fn.system({ 'git', 'config', '--get-color', 'color.status.untracked', 'yellow' })
  local c_unmerged = vim.fn.system({ 'git', 'config', '--get-color', 'color.status.unmerged', 'red' })
  local c_none = '\x1b[m'

  local function pick_color(ch)
    if ch == 'A' then
      return c_added
    elseif ch == 'U' then
      return c_unmerged
    elseif ch == '?' then
      return c_untracked
    elseif ch == ' ' then
      return c_none
    else
      return c_changed
    end
  end

  -- Streaming source: parse git status --porcelain -z in Lua.
  -- Each fzf_cb() call feeds one NUL-free entry directly to fzf-lua,
  -- so --read0 is not needed and no bin/git_status subprocess is required.
  local source = function(fzf_cb)
    local cmd = { 'git', '-C', git_root, 'status', '--porcelain', '-z' }
    if kwargs.uno then
      table.insert(cmd, '-uno')
    end
    if rel_paths ~= '' then
      table.insert(cmd, '--')
      for p in rel_paths:gmatch('%S+') do
        table.insert(cmd, p)
      end
    end

    local output = vim.fn.system(cmd)
    local records = vim.split(output, '\0', { plain = true })
    local i = 1
    while i <= #records do
      local rec = records[i]
      if rec ~= '' then
        local status = rec:sub(1, 2)
        local filename = rec:sub(4)
        local x = status:sub(1, 1)
        local y = status:sub(2, 2)
        local c1 = pick_color(x)
        local c2 = pick_color(y)
        if x == 'R' or x == 'C' then
          -- Next NUL-delimited record is the old filename (rename source)
          local prev = records[i + 1] or ''
          fzf_cb(
            status
              .. '//'
              .. filename
              .. '//'
              .. prev
              .. ' //'
              .. c1
              .. x
              .. c2
              .. y
              .. c_none
              .. ' '
              .. filename
              .. ' -> '
              .. prev
          )
          i = i + 2
        else
          fzf_cb(status .. '// //' .. filename .. ' //' .. c1 .. x .. c2 .. y .. c_none .. ' ' .. filename)
          i = i + 1
        end
      else
        i = i + 1
      end
    end
    fzf_cb(nil)
  end

  local p0 = 'git diff -- {3}'
  local p1 = 'git diff --staged -- {3}'

  local default_size, other_size = utils.preview_window_size()
  local default_preview = ({ p0, p1 })[config.gitlog_default_preview_command + 1] or p0

  local header = (kwargs.uno and '-uno ' or '') .. 'git status' .. paths_info

  local gs_km, gs_cli = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    [config.toggle_preview_key] = 'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
  }, {
    config.gitstatus_preview_0_key .. ':change-preview(' .. p0 .. ')',
    config.gitstatus_preview_1_key .. ':change-preview(' .. p1 .. ')',
  })

  -- Parse selected lines into file entries
  local function parse_files(items)
    local filelist = {}
    for _, line in ipairs(items) do
      local parts = vim.split(line, '//', { plain = true })
      if #parts >= 4 then
        -- Wire format (matches the source coroutine above):
        --   Non-rename:  STATUS// //FILENAME //colored-display
        --   Rename/copy: STATUS//NEW//OLD //colored-display
        -- parts[3] is therefore the NEW filename for non-renames, and the
        -- OLD (pre-rename) filename for R/C entries.  This is intentional:
        -- preview commands use {3} as the path for `git diff`, and for a
        -- rename the interesting diff is shown against the old path.
        local filename = parts[3]:gsub('%z$', '') -- strip accidental trailing null
        table.insert(filelist, { filename = filename, text = parts[1] })
      end
    end
    return filelist
  end

  local function get_items(selected, opts)
    if opts and opts.last_query then
      return selected
    end
    if selected and #selected > 0 and not selected[1]:match('//') then
      return vim.list_slice(selected, 2)
    end
    return selected or {}
  end

  local actions = {}

  actions['default'] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      utils.open_file('edit', filelist[1].filename)
      if config.rg_loclist then
        utils.fill_loc(filelist)
      else
        utils.fill_quickfix(filelist)
      end
    end,
    header = 'open',
  }

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = {
      fn = function(selected, opts)
        local items = get_items(selected, opts)
        local filelist = parse_files(items)
        for _, f in ipairs(filelist) do
          utils.open_file(c, f.filename)
        end
      end,
      header = 'open ' .. c,
    }
  end

  actions[config.gitstatus_uno_key] = {
    fn = function(selected, opts)
      kwargs.uno = not kwargs.uno
      M.gitstatus(fullscreen, kwargs)
    end,
    header = '-uno',
  }

  actions[config.gitstatus_add_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      local files = table.concat(
        vim.tbl_map(function(f)
          return vim.fn.shellescape(f.filename)
        end, filelist),
        ' '
      )
      vim.cmd('Git add -- ' .. files)
    end,
    header = 'add',
  }

  actions[config.gitstatus_add_patch_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      local files = table.concat(
        vim.tbl_map(function(f)
          return vim.fn.shellescape(f.filename)
        end, filelist),
        ' '
      )
      vim.cmd('Git add --patch -- ' .. files)
    end,
    header = 'add -p',
  }

  actions[config.gitstatus_restore_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      local files = table.concat(
        vim.tbl_map(function(f)
          return vim.fn.shellescape(f.filename)
        end, filelist),
        ' '
      )
      vim.cmd('Git restore -- ' .. files)
    end,
    header = 'restore',
  }

  actions[config.gitstatus_restore_patch_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      local files = table.concat(
        vim.tbl_map(function(f)
          return vim.fn.shellescape(f.filename)
        end, filelist),
        ' '
      )
      vim.cmd('Git restore --patch -- ' .. files)
    end,
    header = 'restore -p',
  }

  actions[config.gitstatus_unstage_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      local files = table.concat(
        vim.tbl_map(function(f)
          return vim.fn.shellescape(f.filename)
        end, filelist),
        ' '
      )
      vim.cmd('Git reset HEAD -- ' .. files)
    end,
    header = 'unstage',
  }

  actions[config.gitstatus_unstage_patch_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      local files = table.concat(
        vim.tbl_map(function(f)
          return vim.fn.shellescape(f.filename)
        end, filelist),
        ' '
      )
      vim.cmd('Git reset HEAD --patch -- ' .. files)
    end,
    header = 'unstage -p',
  }

  actions[config.gitstatus_stash_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      local files = table.concat(
        vim.tbl_map(function(f)
          return vim.fn.shellescape(f.filename)
        end, filelist),
        ' '
      )
      vim.cmd('Git stash -- ' .. files)
    end,
    header = 'stash',
  }

  actions[config.gitstatus_stash_patch_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local filelist = parse_files(items)
      if #filelist == 0 then
        return
      end
      local files = table.concat(
        vim.tbl_map(function(f)
          return vim.fn.shellescape(f.filename)
        end, filelist),
        ' '
      )
      vim.cmd('Git stash --patch -- ' .. files)
    end,
    header = 'stash -p',
  }

  fzf_lua.fzf_exec(source, {
    prompt = (kwargs.uno and '-uno ' or '') .. 'git status> ',
    query = kwargs.query,
    cwd = utils.get_git_root(),
    winopts = utils.winopts(fullscreen),
    previewer = false,
    preview = default_preview,
    fzf_opts = {
      ['--history'] = utils.data_path() .. '/git_status_history',
      ['--ansi'] = '',
      ['--multi'] = '',
      ['--print-query'] = '',
      ['--with-nth'] = '4..',
      ['--delimiter'] = '//',
      ['--preview-window'] = default_size,
      ['--header'] = header,
    },
    keymap = gs_km,
    _fzf_cli_args = gs_cli,
    actions = actions,
  })
end

-- Toggle git status window (fugitive)
function M.toggle_git_status()
  local closed = false
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].filetype == 'fugitive' then
      vim.cmd('bdelete ' .. b)
      closed = true
    end
  end
  if not closed then
    vim.cmd('keepalt Git')
  end
end

return M
