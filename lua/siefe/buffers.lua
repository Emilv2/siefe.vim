-- lua/siefe/buffers.lua
-- Buffer listing picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

local function find_open_window(b)
  local tcur = vim.fn.tabpagenr() - 1
  local tcnt = vim.fn.tabpagenr('$')
  for toff = 0, tcnt - 1 do
    local t = (tcur + toff) % tcnt + 1
    local bufs = vim.fn.tabpagebuflist(t)
    for w, wb in ipairs(bufs) do
      if wb == b then
        return t, w
      end
    end
  end
  return 0, 0
end

local function format_buffer(b, git_dir)
  local name = vim.fn.fnameescape(vim.fn.bufname(b))
  local info = vim.fn.getbufinfo(b)[1] or {}
  local line = info.lnum or 0
  name = name == '' and '[No Name]' or vim.fn.fnamemodify(name, ':p:~:.')
  local flag = b == vim.fn.bufnr('') and utils.blue('%', 'Conditional')
    or (b == vim.fn.bufnr('#') and utils.magenta('#', 'Special') or ' ')
  local modified = vim.fn.getbufvar(b, '&modified') == 1 and utils.red('+', 'Exception') or ''
  local modifiable = vim.fn.getbufvar(b, '&modifiable') == 0 and utils.red('-', 'Exception') or ''
  local readonly = vim.fn.getbufvar(b, '&readonly') == 1 and utils.green(' RO', 'Constant') or ''
  local extra = modified .. modifiable
  extra = extra == '' and readonly
    or (utils.red(' [', 'Exception') .. modified .. modifiable .. utils.red('] ', 'Exception') .. readonly)
  local rel_name
  if git_dir ~= '' then
    local full = vim.fn.fnamemodify(vim.fn.expand(vim.fn.fnameescape(vim.fn.bufname(b))), ':p')
    rel_name = utils.green('√') .. '/' .. full:sub(#git_dir + 2)
  else
    rel_name = name
  end
  local line_text = line == 0 and '' or ' line ' .. line
  return vim.trim(
    string.format(
      '%s//%d//[%s] %s\t%s%s\t%s',
      name,
      line,
      utils.yellow(tostring(b), 'Number'),
      flag,
      rel_name,
      extra,
      line_text
    )
  )
end

function M.buffers(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs.query = kwargs.query or ''
  kwargs.project = kwargs.project ~= nil and kwargs.project or false

  local git_dir = utils.get_git_root()
  local git_help = ''
  if git_dir ~= '' then
    local toggle = kwargs.project and 'off' or 'on'
    git_help = ' ╱ ' .. utils.prettify_header(config.buffers_git_key, 'project buffers:' .. toggle)
  end

  local sorted
  if git_dir ~= '' and kwargs.project then
    sorted = vim.tbl_filter(function(b)
      local name = vim.fn.fnamemodify(vim.fn.fnameescape(vim.fn.expand(vim.fn.bufname(b))), ':p')
      return name ~= '' and name:sub(1, #git_dir) == git_dir
    end, utils.buflisted_sorted())
  else
    sorted = utils.buflisted_sorted()
  end

  local project_prefix = (git_dir ~= '' and kwargs.project) and (utils.get_git_basename_or_bufdir() .. ' ') or ''
  local header_lines = (vim.fn.bufnr('') == (sorted[1] or 0)) and 1 or 0
  local tabstop = (math.max((table.unpack or unpack)(#sorted > 0 and sorted or { 0 })) or 0) >= 1000 and 9 or 8

  local previews = utils.make_preview_commands()
  local p0 = previews.buffers[1]
  local p1 = previews.buffers[2]
  local default_preview = previews.buffers[(config.buffers_default_preview_command or 0) + 1] or p0

  local default_size, other_size = utils.preview_window_size()

  local header = (kwargs.project and 'project ' or '') .. 'buffers' .. git_help

  local buf_km = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    [config.toggle_preview_key] = 'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
    [config.buffers_preview_key] = 'change-preview(' .. p0 .. ')',
    [config.buffers_fast_preview_key] = 'change-preview(' .. p1 .. ')',
  })

  -- ── Helpers ─────────────────────────────────────────────────────────────────

  local function get_query(selected, opts)
    if opts and opts.last_query then
      return opts.last_query
    end
    if selected and #selected > 0 and not selected[1]:match('%[%d') then
      return selected[1]
    end
    return kwargs.query or ''
  end

  local function get_items(selected, opts)
    if opts and opts.last_query then
      return selected
    end
    if selected and #selected > 0 and not selected[1]:match('%[%d') then
      return vim.list_slice(selected, 2)
    end
    return selected or {}
  end

  local function get_bufnr(line)
    local m = line:match('%[(%d+)%]')
    return m and tonumber(m) or nil
  end

  -- ── Actions ─────────────────────────────────────────────────────────────────

  local actions = {}

  actions['default'] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local b = get_bufnr(items[1])
      if not b then
        return
      end
      if config.buffers_jump then
        local t, w = find_open_window(b)
        if t > 0 then
          vim.cmd(t .. 'tabnext')
          vim.cmd(w .. 'wincmd w')
          return
        end
      end
      vim.cmd('buffer ' .. b)
    end,
    desc = 'switch',
  }

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = {
      fn = function(selected, opts)
        local items = get_items(selected, opts)
        for _, line in ipairs(items) do
          local b = get_bufnr(line)
          if b then
            vim.cmd('silent ' .. c)
            vim.cmd('silent buffer ' .. b)
            vim.cmd('normal! zvzz')
          end
        end
      end,
      desc = 'open ' .. c,
    }
  end

  actions[config.buffers_delete_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      for _, line in ipairs(items) do
        local b = get_bufnr(line)
        if b then
          local readonly = vim.fn.getbufvar(b, '&readonly') == 1
          local modified = vim.fn.getbufvar(b, '&modified') == 1
          if not modified then
            vim.cmd('bdelete ' .. b)
          elseif modified and not readonly then
            local action =
              vim.fn.input('buffer "' .. vim.fn.bufname(b) .. '" modified. Save, discard or abort? (s/d/a) ')
            if action == 's' then
              local cur = vim.fn.bufnr('%')
              vim.o.lazyredraw = true
              vim.cmd('buffer ' .. b)
              vim.cmd('update')
              vim.cmd('buffer ' .. cur)
              vim.o.lazyredraw = false
            elseif action == 'd' then
              vim.cmd('bdelete! ' .. b)
            end
          elseif modified and readonly then
            local action =
              vim.fn.input('buffer "' .. vim.fn.bufname(b) .. '" modified (readonly). Discard or abort? (d/a) ')
            if action == 'd' then
              vim.cmd('bdelete! ' .. b)
            end
          end
        end
      end
      -- Reopen buffers picker
      kwargs.query = get_query(selected, opts)
      M.buffers(fullscreen, kwargs)
    end,
    desc = 'delete',
  }

  actions[config.buffers_git_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.project = not kwargs.project
      M.buffers(fullscreen, kwargs)
    end,
    desc = 'project',
  }

  actions[config.buffers_history_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      local hist = require('siefe.history')
      hist.historyoldfiles(fullscreen, kwargs)
    end,
    desc = 'history',
  }

  -- Build source
  local source = vim.tbl_map(function(b)
    return format_buffer(b, git_dir)
  end, sorted)

  fzf_lua.fzf_exec(source, {
    prompt = project_prefix .. 'Buf> ',
    query = kwargs.query,
    winopts = utils.winopts(fullscreen),
    previewer = false,
    preview = default_preview,
    fzf_opts = {
      ['--multi'] = '',
      ['--tiebreak'] = 'index',
      ['--ansi'] = '',
      ['--print-query'] = '',
      ['--delimiter'] = '//',
      ['--with-nth'] = '3..',
      ['-n'] = '2,1..2',
      ['--tabstop'] = tostring(tabstop),
      ['--header-lines'] = tostring(header_lines),
      ['--preview-window'] = '+{2}-/2,' .. default_size,
    },
    keymap = buf_km,
    actions = actions,
  })
end

return M
