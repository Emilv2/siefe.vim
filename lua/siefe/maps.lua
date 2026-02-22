-- lua/siefe/maps.lua
-- Keymapping picker and mode selector
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

local function highlight_keys(str)
  -- Yellow for <Key>, Blue for <Plug>
  str = str:gsub('<[^ >]+>', function(m)
    if m == '<Plug>' then
      return utils.blue('<Plug>', 'SpecialKey')
    end
    return utils.yellow(m, 'Special')
  end)
  return str
end

function M.mode_select(fullscreen, query)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  local mode_source = {
    utils.red('n') .. ' # Normal',
    utils.red('v') .. ' # Visual and Select',
    utils.red('s') .. ' # Select',
    utils.red('x') .. ' # Visual',
    utils.red('o') .. ' # Operator-pending',
    utils.red('i') .. ' # Insert',
    utils.red('l') .. ' # Insert, Command-line, Lang-Arg',
    utils.red('c') .. ' # Command-line',
    utils.red('t') .. ' # Terminal-Job',
  }

  local ms_km = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    [config.modes_select_all_key] = 'select-all',
  })

  local actions = {}
  actions['default'] = {
    fn = function(selected, opts)
      -- selected contains chosen mode lines
      local modes = vim.tbl_map(function(l)
        return vim.trim(l:gsub('\x1b%[[%d;]*m', ''):sub(1, 1))
      end, selected or {})
      M.maps(fullscreen, query, modes)
    end,
    desc = 'maps',
  }

  fzf_lua.fzf_exec(mode_source, {
    prompt = 'mode> ',
    winopts = utils.winopts(fullscreen),
    previewer = false,
    fzf_opts = {
      ['--history'] = utils.data_path() .. '/git_dir_history',
      ['--ansi'] = '',
      ['--multi'] = '',
    },
    keymap = ms_km,
    actions = actions,
  })
end

function M.maps(fullscreen, query, modes)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  query = query or ''
  modes = modes or { 'n' }

  local maplist = vim.fn.maplist()
  local filtered = vim.tbl_filter(function(m)
    return vim.tbl_contains(modes, m.mode)
  end, maplist)

  local max_len = 0
  for _, m in ipairs(filtered) do
    if #(m.lhs or '') > max_len then
      max_len = #(m.lhs or '')
    end
  end

  local ordinary = vim.tbl_filter(function(m)
    return (m.sid or 0) >= 0
  end, filtered)
  local special = vim.tbl_filter(function(m)
    return (m.sid or 0) < 0
  end, filtered)

  local lines = {}

  for _, m in ipairs(ordinary) do
    local info = (vim.fn.getscriptinfo({ sid = m.sid }) or {})[1] or {}
    local file = info.name or ''
    local fname = vim.fn.fnamemodify(file, ':t')
    local line = highlight_keys(
      m.mode
        .. '•'
        .. file
        .. '•'
        .. (m.lnum or 0)
        .. '•'
        .. (m.mode or '')
        .. '•'
        .. (m.lhs or '')
        .. '•'
        .. utils.red(m.mode or '')
        .. ' '
        .. (m.lhs or '')
        .. string.rep(' ', max_len - #(m.lhs or '') + 1)
        .. (m.rhs or '')
        .. '\t'
        .. utils.blue(fname .. ':' .. (m.lnum or 0))
    )
    table.insert(lines, line)
  end

  for _, m in ipairs(special) do
    local desc = m.desc or ''
    local line = highlight_keys(
      m.mode
        .. '•'
        .. desc
        .. '•'
        .. (m.lnum or 0)
        .. '•'
        .. (m.mode or '')
        .. '•'
        .. (m.lhs or '')
        .. '•'
        .. utils.red(m.mode or '')
        .. ' '
        .. (m.lhs or '')
        .. string.rep(' ', max_len - #(m.lhs or '') + 1)
        .. (m.rhs or '')
        .. '\t'
        .. utils.blue(desc .. ':' .. (m.lnum or 0))
    )
    table.insert(lines, line)
  end

  table.sort(lines)

  local header = 'maps (' .. table.concat(modes, '/') .. ')'

  local function get_query(selected, opts)
    if opts and opts.last_query then
      return opts.last_query
    end
    if selected and #selected > 0 and not selected[1]:match('•') then
      return selected[1]
    end
    return query
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

  local function parse_map_line(line)
    -- format: mode•file•lnum•mode•lhs•display\tfile_info
    local stripped = line:gsub('\x1b%[[%d;]*m', '')
    local parts = vim.split(stripped:match('^([^\t]*)'), '•', { plain = true })
    if #parts < 5 then
      return nil
    end
    return {
      mode = parts[1],
      file = parts[2],
      lnum = tonumber(parts[3]) or 0,
      lhs = parts[5],
    }
  end

  local maps_km = utils.make_binds({
    [config.up_key] = 'up',
    [config.down_key] = 'down',
  })

  local actions = {}

  -- Default: execute the mapping
  actions['default'] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local m = parse_map_line(items[1])
      if not m then
        return
      end
      vim.schedule(function()
        local map_gv = m.mode == 'x' and 'gv' or ''
        local map_cnt = vim.v.count == 0 and '' or tostring(vim.v.count)
        local map_reg = vim.v.register == '' and '' or ('"' .. vim.v.register)
        local map_op = m.mode == 'o' and vim.v.operator or ''
        vim.api.nvim_feedkeys(map_gv .. map_cnt .. map_reg, 'n', false)
        local lhs = m.lhs:gsub('<[^ >]+>', function(key)
          return vim.api.nvim_replace_termcodes(key, true, false, true)
        end)
        vim.api.nvim_feedkeys(map_op .. lhs, '', false)
      end)
    end,
    desc = 'execute',
  }

  actions[config.maps_open_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local m = parse_map_line(items[1])
      if m and m.file ~= '' then
        utils.open_file('edit', m.file, m.lnum)
      end
    end,
    desc = 'open',
  }

  actions[config.maps_modes_key] = {
    fn = function(selected, opts)
      local q = get_query(selected, opts)
      M.mode_select(fullscreen, q)
    end,
    desc = 'modes',
  }

  fzf_lua.fzf_exec(lines, {
    prompt = 'Maps (' .. table.concat(modes, '/') .. ')> ',
    query = query,
    winopts = utils.winopts(fullscreen),
    previewer = false,
    fzf_opts = {
      ['--ansi'] = '',
      ['--print-query'] = '',
      ['--delimiter'] = '•',
      ['--with-nth'] = '5..',
    },
    keymap = maps_km,
    actions = actions,
  })
end

return M
