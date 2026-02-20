-- lua/siefe/marks.lua
-- Marks picker
local M = {}

local config = require('siefe.config')
local utils  = require('siefe.utils')

local function readbuf_or_file_line(bufnr, filename, pos)
  local lines = vim.fn.getbufline(bufnr, pos)
  if lines and #lines > 0 then return lines[1] end
  if filename ~= '' and vim.fn.filereadable(vim.fn.expand(vim.fn.fnameescape(filename))) == 1 then
    local content = vim.fn.readfile(vim.fn.expand(vim.fn.fnameescape(filename)), '', pos)
    return #content > 0 and content[#content] or ''
  end
  return ''
end

function M.marks(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then utils.warn('siefe: fzf-lua not found') return end

  kwargs.query = kwargs.query or ''

  local git_dir = utils.get_git_root()

  -- Build source: global marks + buffer marks
  local source = {}

  for _, m in ipairs(vim.fn.getmarklist()) do
    local mark  = m.mark:sub(2)  -- strip leading '
    local file  = m.file or ''
    local lnum  = m.pos[2]
    local col   = m.pos[3]
    local bnr   = m.pos[1]
    local text  = lnum > 0 and readbuf_or_file_line(bnr, file, lnum) or ''
    local rel   = utils.get_relative_git_or_bufdir(file, git_dir ~= '' and git_dir or nil) or file
    local display = rel .. ':' .. utils.blue(text:sub(1, col - 1) or '')
      .. (text:sub(col, col) ~= '' and utils.red(text:sub(col, col)) or '')
      .. utils.blue(text:sub(col + 1) or '')
    table.insert(source, string.format('%s//:///%s//:///%s//:///%s//:///%s//:///%s\t%s\t%s\t%s',
      mark, vim.fn.fnameescape(file), lnum, col, bnr,
      utils.red(mark), lnum, col, display))
  end

  for _, m in ipairs(vim.fn.getmarklist(vim.fn.bufnr())) do
    local mark  = m.mark:sub(2)
    local lnum  = m.pos[2]
    local col   = m.pos[3]
    local bnr   = m.pos[1]
    local line_text = lnum > 0 and (vim.fn.getline(lnum) or '') or ''
    local display = (lnum > 0 and utils.green(line_text:sub(1, lnum - 1)) or '')
      .. utils.red(line_text:sub(lnum, lnum))
      .. utils.green(line_text:sub(lnum + 1))
    table.insert(source, string.format('%s//:///%s//:///%s//:///%s//:///%s//:///%s\t%s\t%s\t%s',
      mark, vim.fn.fnameescape(vim.fn.bufname()), lnum, col, bnr,
      utils.red(mark), lnum, col, display))
  end

  local previews    = utils.make_preview_commands()
  local p0          = previews.marks[1]
  local p1          = previews.marks[2]
  local preview_cmd = previews.marks[(config.marks_default_preview_command or 0) + 1] or p0

  local default_size, other_size = utils.preview_window_size()

  local header = 'm\tl\tc\tfile/text\n' .. utils.common_window_help()

  local binds = {
    'change:first',
    'enter:ignore', 'esc:ignore',
    config.accept_key           .. ':accept',
    config.up_key               .. ':up',
    config.down_key             .. ':down',
    config.toggle_up_key        .. ':toggle+up',
    config.toggle_down_key      .. ':toggle+down',
    config.toggle_preview_key   .. ':change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
    config.marks_preview_key      .. ':change-preview(' .. p0 .. ')',
    config.marks_fast_preview_key .. ':change-preview(' .. p1 .. ')',
  }

  local function parse_mark_line(line)
    -- format: mark//://filename//://lnum//://col//://bufnr//://display\t...
    local parts = vim.split(line, '//://', { plain = true })
    if #parts < 5 then return nil end
    return {
      mark     = parts[1],
      filename = parts[2],
      lnum     = tonumber(parts[3]) or 0,
      col      = tonumber(parts[4]) or 0,
      bufnr    = tonumber(parts[5]) or 0,
    }
  end

  local function get_items(selected, opts)
    if opts and opts.last_query then return selected end
    if selected and #selected > 0 then
      -- Check if first item looks like a mark line
      if not selected[1]:match('//', 1, true) then return vim.list_slice(selected, 2) end
    end
    return selected or {}
  end

  local actions = {}

  actions['default'] = function(selected, opts)
    local items = get_items(selected, opts)
    if #items == 0 then return end
    local filelist = {}
    for _, line in ipairs(items) do
      local m = parse_mark_line(line)
      if m then
        local text = readbuf_or_file_line(m.bufnr, m.filename, m.lnum)
        table.insert(filelist, { type = m.mark, filename = m.filename, lnum = m.lnum, col = m.col, text = text })
      end
    end
    if #filelist == 0 then return end
    local first = filelist[1]
    if first.filename ~= '' then
      utils.open_file('edit', first.filename, first.lnum, first.col)
    end
    if config.marks_loclist then utils.fill_loc(filelist) else utils.fill_quickfix(filelist) end
  end

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = function(selected, opts)
      local items = get_items(selected, opts)
      for _, line in ipairs(items) do
        local m = parse_mark_line(line)
        if m and m.filename ~= '' then
          utils.open_file(c, m.filename, m.lnum, m.col)
        end
      end
    end
  end

  actions[config.marks_delete_key] = function(selected, opts)
    local items = get_items(selected, opts)
    for _, line in ipairs(items) do
      local m = parse_mark_line(line)
      if m then vim.fn.setpos("'" .. m.mark, { 0, 0, 0, 0 }) end
    end
  end

  actions[config.marks_yank_key] = function(selected, opts)
    local items = get_items(selected, opts)
    local texts = {}
    for _, line in ipairs(items) do
      local m = parse_mark_line(line)
      if m then
        table.insert(texts, readbuf_or_file_line(m.bufnr, m.filename, m.lnum))
      end
    end
    utils.yank_to_register(table.concat(texts, '\n'))
  end

  fzf_lua.fzf_exec(source, {
    prompt    = 'Marks> ',
    query     = kwargs.query,
    winopts   = utils.winopts(fullscreen),
    previewer = false,
    preview   = preview_cmd,
    fzf_opts  = {
      ['--tiebreak']       = 'begin',
      ['--ansi']           = '',
      ['--multi']          = '',
      ['--tabstop']        = '4',
      ['--delimiter']      = '//://',
      ['--with-nth']       = '6..',
      ['--preview-window'] = '+{2}-/2,' .. default_size,
      ['--header']         = header,
      ['--bind']           = binds,
    },
    actions = actions,
  })
end

return M
