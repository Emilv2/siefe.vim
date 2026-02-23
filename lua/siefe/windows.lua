-- lua/siefe/windows.lua
-- Window listing picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

-- Format: bufname//lnum//display
-- Field 1 (bufname) and 2 (lnum) are hidden by --with-nth=3..
-- They are used by the preview command ({1}) and scroll hint (+{2}-/2).
-- The display contains [T{t}:W{w}] so the action can parse back tab/win.
local function format_window(tabnr, winnr, bufnr, cur_tab, cur_win)
  local name = vim.fn.bufname(bufnr)
  local btype = vim.fn.getbufvar(bufnr, '&buftype')
  local modified = vim.fn.getbufvar(bufnr, '&modified') == 1
  local winid = vim.fn.win_getid(winnr, tabnr)
  local wi = vim.fn.getwininfo(winid)
  local lnum = wi and wi[1] and wi[1].topline or 0

  local display_name
  if btype == 'terminal' then
    -- Show terminal buffer with green colour to visually distinguish them
    local tname = name ~= '' and name or '[Terminal]'
    display_name = utils.green(tname, 'String')
  elseif name == '' then
    display_name = utils.yellow('[No Name]', 'Comment')
  else
    display_name = vim.fn.fnamemodify(name, ':p:~:.')
  end

  local is_cur = tabnr == cur_tab and winnr == cur_win
  local flag = is_cur and utils.blue('%', 'Conditional') or ' '
  local mod_flag = modified and utils.red('+', 'Exception') or ''
  local lnum_text = lnum > 0 and ('  line ' .. lnum) or ''
  local tab_text = utils.magenta('T' .. tabnr, 'Number') .. ':' .. utils.blue('W' .. winnr, 'Identifier')
  local preview_name = name ~= '' and name or '[No Name]'

  return string.format(
    '%s//%d//[%s] %s%s%s%s',
    preview_name,
    lnum,
    tab_text,
    flag,
    display_name,
    mod_flag,
    lnum_text
  )
end

local function get_tab_win(line)
  -- Parse [T{t}:W{w}] from the display portion (field 3+)
  local t, w = line:match('%[T(%d+):W(%d+)%]')
  return tonumber(t), tonumber(w)
end

function M.windows(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs = kwargs or {}
  kwargs.query = kwargs.query or ''

  local previews = utils.make_preview_commands()
  local p0 = previews.buffers[1]
  local p1 = previews.buffers[2]
  local default_preview = previews.buffers[(config.buffers_default_preview_command or 0) + 1] or p0

  local default_size, other_size = utils.preview_window_size()

  -- Build source: iterate all tabs × windows in tab order
  local source = {}
  local cur_tab = vim.fn.tabpagenr()
  local cur_win = vim.fn.winnr()
  local tab_count = vim.fn.tabpagenr('$')
  for t = 1, tab_count do
    local bufs = vim.fn.tabpagebuflist(t)
    for w, b in ipairs(bufs) do
      table.insert(source, format_window(t, w, b, cur_tab, cur_win))
    end
  end

  -- Put the current window first so it appears at the bottom (nearest to prompt)
  -- and is pre-selected when the picker opens.
  local header_lines = source[1] and get_tab_win(source[1]) == cur_tab and 1 or 0
  -- reorder: current window first
  local ordered = {}
  local rest = {}
  for _, entry in ipairs(source) do
    local t, w = get_tab_win(entry)
    if t == cur_tab and w == cur_win then
      table.insert(ordered, 1, entry)
    else
      table.insert(rest, entry)
    end
  end
  for _, entry in ipairs(rest) do
    table.insert(ordered, entry)
  end
  header_lines = 1 -- current window is always first entry

  local win_km = utils.make_binds({
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

  local actions = {}

  -- Default: switch to the selected window
  actions['default'] = {
    fn = function(selected, _opts)
      if not selected or #selected == 0 then
        return
      end
      local t, w = get_tab_win(selected[1])
      if t and w then
        vim.cmd(t .. 'tabnext')
        vim.cmd(w .. 'wincmd w')
      end
    end,
    desc = 'switch',
  }

  -- Close the selected window(s)
  actions[config.windows_close_key] = {
    fn = function(selected, _opts)
      if not selected or #selected == 0 then
        return
      end
      -- Close in reverse order to avoid shifting window numbers
      local to_close = {}
      for _, line in ipairs(selected) do
        local t, w = get_tab_win(line)
        if t and w then
          -- Skip current window to avoid accidental self-close
          if t ~= cur_tab or w ~= cur_win then
            table.insert(to_close, { t, w })
          end
        end
      end
      -- Sort descending by tab then win so closing doesn't shift indices
      table.sort(to_close, function(a, b)
        if a[1] ~= b[1] then
          return a[1] > b[1]
        end
        return a[2] > b[2]
      end)
      for _, tw in ipairs(to_close) do
        local winid = vim.fn.win_getid(tw[2], tw[1])
        if winid > 0 then
          vim.api.nvim_win_close(winid, false)
        end
      end
    end,
    desc = 'close window',
  }

  fzf_lua.fzf_exec(ordered, {
    prompt = 'Win> ',
    query = kwargs.query,
    winopts = utils.winopts(fullscreen),
    previewer = false,
    preview = default_preview,
    fzf_opts = {
      ['--multi'] = '',
      ['--tiebreak'] = 'index',
      ['--ansi'] = '',
      ['--delimiter'] = '//',
      ['--with-nth'] = '3..',
      ['--preview-window'] = '+{2}-/2,' .. default_size,
      ['--header-lines'] = tostring(header_lines),
    },
    keymap = win_km,
    actions = actions,
  })
end

return M
