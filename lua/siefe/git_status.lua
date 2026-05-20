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

  -- Resolve a git-relative path to an absolute path.  `git status --porcelain`
  -- emits paths relative to *git_root*, but open_file() resolves relative paths
  -- against Neovim's cwd (which may be a subdirectory).  This mirrors the
  -- make_absolute() helper in history.lua.
  local function resolve_path(fname)
    if fname ~= '' and fname:sub(1, 1) ~= '/' and git_root ~= '' then
      return git_root .. '/' .. fname
    end
    return fname
  end

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

  -- Streaming source: parse git status --porcelain in Lua.
  -- Each fzf_cb() call feeds one entry directly to fzf-lua.
  -- We do NOT use -z (NUL-separated) because vim.fn.system() does not reliably
  -- preserve NUL bytes in its return value across all Neovim versions.
  -- vim.fn.systemlist() returns one line per entry (LF-separated), which is safe.
  local source = function(fzf_cb)
    local cmd = { 'git', '-C', git_root, 'status', '--porcelain' }
    if kwargs.uno then
      table.insert(cmd, '-uno')
    end
    if rel_paths ~= '' then
      table.insert(cmd, '--')
      for p in rel_paths:gmatch('%S+') do
        table.insert(cmd, p)
      end
    end

    local records = vim.fn.systemlist(cmd)
    for _, rec in ipairs(records) do
      if rec ~= '' then
        local status = rec:sub(1, 2)
        local rest = rec:sub(4) -- skip "XY " prefix
        local x = status:sub(1, 1)
        local y = status:sub(2, 2)
        local c1 = pick_color(x)
        local c2 = pick_color(y)
        if x == 'R' or x == 'C' then
          -- Without -z, rename/copy format is "XY ORIG -> NEW" on one line.
          -- We keep field layout identical to what the action/preview code expects:
          --   parts[1]=status  parts[2]=new  parts[3]=orig  parts[4]=display
          local arrow = rest:find(' -> ', 1, true)
          if arrow then
            local orig = rest:sub(1, arrow - 1)
            local new = rest:sub(arrow + 4) -- skip past the 4-char ' -> ' separator
            fzf_cb(
              status
                .. '//'
                .. new
                .. '//'
                .. orig
                .. ' //'
                .. c1
                .. x
                .. c2
                .. y
                .. c_none
                .. ' '
                .. orig
                .. ' -> '
                .. new
            )
          else
            -- Fallback: git output has no ' -> ' in a rename line (should not happen).
            -- Treat the whole rest as the filename so fzf shows something.
            fzf_cb(status .. '// //' .. rest .. ' //' .. c1 .. x .. c2 .. y .. c_none .. ' ' .. rest)
          end
        else
          fzf_cb(status .. '// //' .. rest .. ' //' .. c1 .. x .. c2 .. y .. c_none .. ' ' .. rest)
        end
      end
    end
    fzf_cb(nil)
  end

  local p0 = 'git diff -- {3}'
  local p1 = 'git diff --staged -- {3}'

  local default_size, other_size = utils.preview_window_size()
  local default_preview = p0

  local header = (kwargs.uno and '-uno ' or '') .. 'git status' .. paths_info

  local gs_km = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    [config.toggle_preview_key] = 'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
    [config.gitstatus_preview_0_key] = 'change-preview(' .. p0 .. ')',
    [config.gitstatus_preview_1_key] = 'change-preview(' .. p1 .. ')',
  })

  -- Parse selected lines into file entries
  local function parse_files(items)
    local filelist = {}
    for _, line in ipairs(items) do
      local parts = vim.split(line, '//', { plain = true })
      if #parts >= 4 then
        -- Wire format (matches the source function above):
        --   Non-rename:  STATUS// //FILENAME //colored-display
        --   Rename/copy: STATUS//NEW//ORIG //colored-display
        -- parts[3] is therefore the FILENAME for non-renames, and the
        -- ORIG (pre-rename) filename for R/C entries.  This is intentional:
        -- preview commands use {3} as the path for `git diff`, and for a
        -- rename the interesting diff is shown against the old path.
        -- vim.trim() removes the trailing space that precedes the '//' delimiter.
        local filename = vim.trim(parts[3])
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
      utils.open_file('edit', resolve_path(filelist[1].filename))
      if config.rg_loclist then
        utils.fill_loc(filelist)
      else
        utils.fill_quickfix(filelist)
      end
    end,
    desc = 'open',
  }

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = {
      fn = function(selected, opts)
        local items = get_items(selected, opts)
        local filelist = parse_files(items)
        for _, f in ipairs(filelist) do
          utils.open_file(c, resolve_path(f.filename))
        end
      end,
      desc = 'open ' .. c,
    }
  end

  actions[config.gitstatus_uno_key] = {
    fn = function(selected, opts)
      kwargs.uno = not kwargs.uno
      M.gitstatus(fullscreen, kwargs)
    end,
    desc = '-uno',
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
    desc = 'add',
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
    desc = 'add -p',
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
    desc = 'restore',
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
    desc = 'restore -p',
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
    desc = 'unstage',
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
    desc = 'unstage -p',
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
    desc = 'stash',
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
    desc = 'stash -p',
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
      ['--layout'] = 'default',
      ['--ansi'] = '',
      ['--multi'] = '',
      ['--print-query'] = '',
      ['--with-nth'] = '4..',
      ['--delimiter'] = '//',
      ['--preview-window'] = default_size,
    },
    keymap = gs_km,
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
