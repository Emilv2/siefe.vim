-- lua/siefe/marks.lua
-- Marks picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

local function readbuf_or_file_line(bufnr, filename, pos)
  local lines = vim.fn.getbufline(bufnr, pos)
  if lines and #lines > 0 then
    return lines[1]
  end
  if filename ~= '' and vim.fn.filereadable(vim.fn.expand(vim.fn.fnameescape(filename))) == 1 then
    local content = vim.fn.readfile(vim.fn.expand(vim.fn.fnameescape(filename)), '', pos)
    return #content > 0 and content[#content] or ''
  end
  return ''
end

function M.marks(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs.query = kwargs.query or ''

  local git_dir = utils.get_git_root()

  -- Build source: global marks + buffer marks
  local source = {}

  for _, m in ipairs(vim.fn.getmarklist()) do
    local mark = m.mark:sub(2) -- strip leading '
    local file = m.file or ''
    local lnum = m.pos[2]
    local col = m.pos[3]
    local bnr = m.pos[1]
    local text = lnum > 0 and readbuf_or_file_line(bnr, file, lnum) or ''
    local rel = utils.get_relative_git_or_bufdir(file, git_dir ~= '' and git_dir or nil) or file
    local display = rel
      .. ':'
      .. utils.blue(text:sub(1, col - 1) or '')
      .. (text:sub(col, col) ~= '' and utils.red(text:sub(col, col)) or '')
      .. utils.blue(text:sub(col + 1) or '')
    table.insert(
      source,
      string.format(
        '%s:%s:%s\x01%s\x01%s\x01%s\t%s\t%s\t%s',
        vim.fn.fnameescape(file),
        lnum,
        col,
        bnr,
        mark,
        utils.red(mark),
        lnum,
        col,
        display
      )
    )
  end

  for _, m in ipairs(vim.fn.getmarklist(vim.fn.bufnr())) do
    local mark = m.mark:sub(2)
    local lnum = m.pos[2]
    local col = m.pos[3]
    local bnr = m.pos[1]
    local line_text = lnum > 0 and (vim.fn.getline(lnum) or '') or ''
    local display = (col > 1 and utils.green(line_text:sub(1, col - 1)) or '')
      .. utils.red(line_text:sub(col, col))
      .. utils.green(line_text:sub(col + 1))
    table.insert(
      source,
      string.format(
        '%s:%s:%s\x01%s\x01%s\x01%s\t%s\t%s\t%s',
        vim.fn.fnameescape(vim.fn.bufname()),
        lnum,
        col,
        bnr,
        mark,
        utils.red(mark),
        lnum,
        col,
        display
      )
    )
  end

  local default_size = utils.preview_window_size()

  local header = 'm\tl\tc\tfile/text'

  local marks_km = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
  })
  -- toggle-preview via keymap.builtin so it correctly controls the fzf-lua
  -- builtin Neovim preview window. Use builtin_toggle_keys() for terminal compat.
  marks_km.builtin = {}
  for _, nk in ipairs(utils.builtin_toggle_keys(config.toggle_preview_key)) do
    marks_km.builtin[nk] = 'toggle-preview'
  end

  local function parse_mark_line(line)
    -- format: fname:lnum:col\x01bufnr\x01mark\x01display...
    -- entry_to_file() reads fname:lnum from the ':' prefix.
    local parts = vim.split(line, '\x01', { plain = true })
    if #parts < 3 then
      return nil
    end
    local ps = vim.split(parts[1], ':', { plain = true })
    return {
      filename = ps[1] or '',
      lnum = tonumber(ps[2]) or 0,
      col = tonumber(ps[3]) or 0,
      bufnr = tonumber(parts[2]) or 0,
      mark = parts[3] or '',
    }
  end

  local function get_items(selected, opts)
    return selected or {}
  end

  local actions = {}

  actions['default'] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local filelist = {}
      for _, line in ipairs(items) do
        local m = parse_mark_line(line)
        if m then
          local text = readbuf_or_file_line(m.bufnr, m.filename, m.lnum)
          table.insert(filelist, { type = m.mark, filename = m.filename, lnum = m.lnum, col = m.col, text = text })
        end
      end
      if #filelist == 0 then
        return
      end
      local first = filelist[1]
      if first.filename ~= '' then
        utils.open_file('edit', first.filename, first.lnum, first.col)
      end
      if config.marks_loclist then
        utils.fill_loc(filelist)
      else
        utils.fill_quickfix(filelist)
      end
    end,
    desc = 'jump',
  }

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = {
      fn = function(selected, opts)
        local items = get_items(selected, opts)
        for _, line in ipairs(items) do
          local m = parse_mark_line(line)
          if m and m.filename ~= '' then
            utils.open_file(c, m.filename, m.lnum, m.col)
          end
        end
      end,
      desc = 'open ' .. c,
    }
  end

  actions[config.marks_delete_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      for _, line in ipairs(items) do
        local m = parse_mark_line(line)
        if m then
          vim.fn.setpos("'" .. m.mark, { 0, 0, 0, 0 })
        end
      end
    end,
    desc = 'delete',
  }

  actions[config.marks_yank_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local texts = {}
      for _, line in ipairs(items) do
        local m = parse_mark_line(line)
        if m then
          table.insert(texts, readbuf_or_file_line(m.bufnr, m.filename, m.lnum))
        end
      end
      utils.yank_to_register(table.concat(texts, '\n'))
    end,
    desc = 'yank',
  }

  fzf_lua.fzf_exec(source, {
    prompt = 'Marks> ',
    query = kwargs.query,
    winopts = utils.winopts(fullscreen),
    previewer = 'builtin',
    fzf_opts = {
      ['--tiebreak'] = 'begin',
      ['--ansi'] = '',
      ['--multi'] = '',
      ['--tabstop'] = '4',
      ['--layout'] = 'default',
      -- Entry: fname:lnum:col\x01bufnr\x01mark\x01display
      -- entry_to_file() reads fname:lnum:col from ':' prefix; fzf shows field 4+ (display).
      ['--delimiter'] = '\x01',
      ['--with-nth'] = '4..',
      ['--preview-window'] = default_size,
    },
    keymap = marks_km,
    actions = actions,
  })
end

return M
