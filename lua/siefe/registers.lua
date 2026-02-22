-- lua/siefe/registers.lua
-- Register picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

local function get_all_registers()
  local regnames = {}
  for i = string.byte('a'), string.byte('z') do
    table.insert(regnames, string.char(i))
  end
  for i = string.byte('0'), string.byte('9') do
    table.insert(regnames, string.char(i))
  end
  for _, c in ipairs({ '"', '-', '*', '%', '/', '.', '#', ':' }) do
    table.insert(regnames, c)
  end
  local result = {}
  for _, r in ipairs(regnames) do
    local info = vim.fn.getreginfo(r)
    if info and next(info) ~= nil then
      table.insert(result, { reg = r, info = info })
    end
  end
  return result
end

local function printreg(entry)
  return utils.red('"' .. entry.reg) .. ' ' .. utils.blue(table.concat(entry.info.regcontents or {}, '↵'))
end

-- Save register contents after editing in a temp buffer
local function regsave()
  local file = vim.b.siefe_tempfile
  local reg = vim.b.siefe_reg
  if not file or not reg then
    return
  end
  local contents = vim.fn.readfile(file)
  -- Skip the header comment line (first line)
  contents = vim.list_slice(contents, 2)
  local reg_amode = vim.fn.getregtype(reg)
  vim.fn.setreg(reg, contents, reg_amode)
  vim.fn.delete(file)
end

function M.registers(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs.query = kwargs.query or ''

  local entries = get_all_registers()
  local source = vim.tbl_map(printreg, entries)

  local header = 'registers'

  local function get_reg(line)
    -- Format: red("reg_char") blue("contents")
    -- Strip ANSI: the register char is the 2nd character (after the " sign)
    local stripped = line:gsub('\x1b%[[%d;]*m', '')
    return stripped:sub(2, 2)
  end

  local function get_items(selected, opts)
    if opts and opts.last_query then
      return selected
    end
    if selected and #selected > 0 and not selected[1]:match('"') then
      return vim.list_slice(selected, 2)
    end
    return selected or {}
  end

  local actions = {}

  local regs_km, regs_cli = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
  }, {})

  -- Default: edit register in a split buffer
  actions['default'] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local reg = get_reg(items[1])
      local tempfile = vim.fn.tempname()
      vim.cmd('split ' .. tempfile)
      vim.fn.append(
        0,
        '### Editing register `' .. reg .. '`. Add control characters by preceding them with `ctrl-v` ###'
      )
      vim.cmd('put ' .. reg)
      vim.cmd('2delete _')
      vim.fn.matchaddpos('Error', { 1 })
      vim.b.siefe_reg = reg
      vim.b.siefe_tempfile = tempfile
      vim.api.nvim_create_autocmd('BufWritePost', {
        buffer = vim.api.nvim_get_current_buf(),
        callback = regsave,
        once = false,
        group = vim.api.nvim_create_augroup('siefe_registers', { clear = true }),
      })
    end,
    header = 'edit',
  }

  actions[config.registers_paste_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local reg = get_reg(items[1])
      vim.cmd('put ' .. reg)
    end,
    header = 'paste',
  }

  actions[config.registers_execute_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local reg = get_reg(items[1])
      vim.cmd('normal @' .. reg)
    end,
    header = 'execute',
  }

  actions[config.registers_clear_key] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local reg = get_reg(items[1])
      local reg_amode = vim.fn.getregtype(reg)
      vim.fn.setreg(reg, {}, reg_amode)
    end,
    header = 'clear',
  }

  fzf_lua.fzf_exec(source, {
    prompt = 'Regs> ',
    query = kwargs.query,
    winopts = utils.winopts(fullscreen),
    previewer = false,
    fzf_opts = {
      ['--ansi'] = '',
      ['--sync'] = '',
      ['--delimiter'] = ' ',
    },
    keymap = regs_km,
    _fzf_cli_args = regs_cli,
    actions = actions,
  })
end

return M
