-- lua/siefe/jumps.lua
-- Jump list picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

local function readbuf_or_file_line(bnr, filename, pos)
  local lines = vim.fn.getbufline(bnr, pos)
  if lines and #lines > 0 then
    return lines[1]
  end
  if filename ~= '' and vim.fn.filereadable(vim.fn.expand(vim.fn.fnameescape(filename))) == 1 then
    local content = vim.fn.readfile(vim.fn.expand(vim.fn.fnameescape(filename)), '', pos)
    return #content > 0 and content[#content] or ''
  end
  return ''
end

local function printjump(git_dir, current, jump_max, lnum_max_len, index, jump)
  if jump.bufnr == -1 then
    return ' \x01 \x01 \x010\x01'
  end
  local bufname = vim.fn.bufname(jump.bufnr) or ''
  local rel_offset = index - current
  local text
  if vim.fn.bufnr() == jump.bufnr then
    local line = vim.fn.join(vim.fn.getbufline(jump.bufnr, jump.lnum))
    text = (jump.col > 0 and utils.green(line:sub(1, jump.col)) or '')
      .. utils.red(line:sub(jump.col + 1, jump.col + 1))
      .. utils.green(line:sub(jump.col + 2))
  else
    local line = readbuf_or_file_line(jump.bufnr, bufname, jump.lnum)
    local rel = utils.get_relative_git_or_bufdir(bufname, git_dir ~= '' and git_dir or nil) or bufname
    text = rel
      .. ': '
      .. (jump.col > 0 and utils.blue(line:sub(1, jump.col)) or '')
      .. utils.red(line:sub(jump.col + 1, jump.col + 1))
      .. utils.blue(line:sub(jump.col + 2))
  end
  return bufname
    .. '\x01' .. (jump.lnum or 0)
    .. '\x01' .. (jump.col or 0)
    .. '\x01' .. rel_offset
    .. '\x01' .. math.abs(rel_offset)
    .. string.rep(' ', jump_max - #tostring(math.abs(rel_offset)) + 1)
    .. (jump.lnum or 0)
    .. string.rep(' ', lnum_max_len - #tostring(jump.lnum or 0) + 1)
    .. text
end

function M.jumps(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs.query = kwargs.query or ''

  local git_dir = utils.get_git_root()
  local jumplist, current = unpack(vim.fn.getjumplist())
  jumplist = jumplist or {}
  current = current or 0

  local jump_max = #tostring(math.abs(#jumplist - 2 * current))
  local lnum_max = 0
  for _, j in ipairs(jumplist) do
    if (j.lnum or 0) > lnum_max then
      lnum_max = j.lnum or 0
    end
  end
  local lnum_max_len = #tostring(lnum_max)

  if current >= #jumplist then
    table.insert(jumplist, { lnum = 0, bufnr = -1, col = 0 })
  end

  local source = {}
  for i, jump in ipairs(jumplist) do
    table.insert(source, printjump(git_dir, current, jump_max, lnum_max_len, i - 1, jump))
  end

  local default_size, other_size = utils.preview_window_size()

  local header = 'jumps  current:' .. current

  local jumps_km = utils.make_binds({
    ['change'] = 'first',
    ['start'] = 'pos:' .. (#jumplist - current),
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    [config.toggle_preview_key] = {
      'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
      desc = 'cycle-preview',
    },
  })

  local function parse_jump_line(line)
    -- format: fname\x01lnum\x01col\x01rel_offset\x01display
    local parts = vim.split(line, '\x01', { plain = true })
    if #parts < 4 then
      return nil
    end
    return {
      filename = parts[1],
      lnum = tonumber(parts[2]) or 0,
      col = tonumber(parts[3]) or 0,
      index = tonumber(parts[4]) or 0,
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
      local j = parse_jump_line(items[1])
      if not j then
        return
      end
      if j.index < 0 then
        vim.cmd('normal! ' .. -j.index .. '\x0F') -- Ctrl-O
      else
        vim.cmd('normal! ' .. j.index .. '\x09') -- Ctrl-I
      end
    end,
    desc = 'jump',
  }

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = {
      fn = function(selected, opts)
        local items = get_items(selected, opts)
        if #items == 0 then
          return
        end
        local j = parse_jump_line(items[1])
        if j and j.filename ~= '' then
          utils.open_file(c, j.filename, j.lnum, j.col)
        end
      end,
      desc = 'open ' .. c,
    }
  end

  actions[config.jumps_clear_key] = {
    fn = function(selected, opts)
      vim.cmd('clearjumps')
    end,
    desc = 'clear',
  }

  actions[config.jumps_yank_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      local texts = {}
      for _, line in ipairs(items) do
        local j = parse_jump_line(line)
        if j then
          -- Display text is field 5 (after 4 \x01 separators)
          local parts = vim.split(line, '\x01', { plain = true })
          if #parts >= 5 then
            table.insert(texts, parts[5])
          end
        end
      end
      utils.yank_to_register(table.concat(texts, '\n'))
    end,
    desc = 'yank',
  }

  fzf_lua.fzf_exec(source, {
    prompt = 'Jumps> ',
    query = kwargs.query,
    winopts = utils.winopts(fullscreen),
    previewer = 'builtin',
    fzf_opts = {
      ['--ansi'] = '',
      ['--tac'] = '',
      ['--sync'] = '',
      ['--cycle'] = '',
      ['--scroll-off'] = '999',
      -- Entry: fname\x01lnum\x01col\x01rel_offset\x01display
      -- \x01 delimiter lets entry_to_file() parse fname without fs_stat.
      ['--delimiter'] = '\x01',
      ['--with-nth'] = '5..',
      ['--preview-window'] = default_size,
    },
    keymap = jumps_km,
    actions = actions,
  })
end

return M
