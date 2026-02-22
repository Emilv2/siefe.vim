-- lua/siefe/type_select.lua
-- Ripgrep type selection picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

-- func     : string – "rg" | "rg_not"  (which action to perform after selection)
-- fullscreen: bool
-- ...: extra args forwarded to the callback (dir, kwargs, …)
function M.type_select(func, fullscreen, ...)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  local extra = { ... }

  local function on_select(selected, _opts)
    if not selected or #selected == 0 then
      return
    end
    -- selected[1] = query (--print-query), rest = chosen types
    local query = selected[1] or ''
    local items = vim.list_slice(selected, 2)

    local type_flag = ''
    if #items > 0 and items[1] ~= config.abort_key then
      local flag = func == 'rg' and '-t' or '-T'
      local types = vim.tbl_map(function(v)
        return flag .. vim.split(v, ':')[1]
      end, items)
      type_flag = table.concat(types, ' ')
    end

    -- Dispatch back to the parent function
    if func == 'rg' or func == 'rg_not' then
      local rg = require('siefe.rg')
      local dir = extra[1]
      local kwargs = extra[2] or {}
      kwargs.type = type_flag
      rg.ripgrepfzf(fullscreen, dir, kwargs)
    elseif func == 'gitlog' then
      local gl = require('siefe.git_log')
      local kwargs = extra[1] or {}
      if #items > 0 and items[1] ~= config.abort_key then
        -- Convert rg type globs into git pathspecs (git understands rg --type-list globs)
        local type_globs = {}
        for _, item in ipairs(items) do
          local type_name = vim.split(item, ':')[1]
          local globs_raw = vim.split((vim.split(item, ':')[2] or ''), ',')
          for _, g in ipairs(globs_raw) do
            table.insert(type_globs, vim.trim(g))
          end
        end
        kwargs.type = type_globs
      else
        kwargs.type = {}
      end
      gl.gitlogfzf(fullscreen, kwargs)
    end
  end

  local ts_km, ts_cli = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
  }, {})

  local default_size, _ = utils.preview_window_size()
  fzf_lua.fzf_exec(
    utils.bin_path('logger') .. ' ' .. vim.fn.shellescape(utils.log_path()) .. ' rg --color=always --type-list',
    {
      prompt = 'Choose type> ',
      winopts = utils.winopts(fullscreen),
      previewer = false,
      fzf_opts = {
        ['--multi'] = '',
        ['--ansi'] = '',
        ['--history'] = utils.data_path() .. '/type_fzf_history',
        ['--header'] = 'file types',
        ['--print-query'] = '',
      },
      keymap = ts_km,
      _fzf_cli_args = ts_cli,
      actions = {
        ['default'] = { fn = on_select, header = 'select' },
        [config.abort_key] = {
          fn = function(selected, opts)
            on_select({ '', config.abort_key }, opts)
          end,
          header = 'abort',
        },
      },
    }
  )
end

return M
