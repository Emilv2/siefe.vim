-- test/test_plugin.lua
-- Tests that source plugin/siefe.lua directly (as Neovim does on startup).
-- Catches load-time bugs like config.options.map_keys (nil-index at line 416)
-- that were invisible to module-level require() tests.
--
-- Run with: nvim --headless -u NONE -l test/test_plugin.lua

-- Absolute path to repo root (so 'source plugin/siefe.lua' resolves correctly
-- regardless of the cwd when the test runner is invoked)
local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(repo_root)

local T = require('test.helpers')

-- Source plugin/siefe.lua and capture any Lua error.
-- Returns nil on success, error string on failure.
local function source_plugin()
  local ok, err = pcall(vim.cmd, 'source ' .. repo_root .. '/plugin/siefe.lua')
  if not ok then
    return err
  end
  return nil
end

-- Reset loaded state so each group can re-source from scratch.
-- Also clears persistent keymaps that may leak from a previous group.
local function reset()
  vim.g.loaded_siefe_lua = nil
  -- Remove default leader mappings that persist across reset() calls
  -- (keymaps are not cleared when package.loaded is cleared).
  leader = vim.g.mapleader or '\\'
  for _, mode in ipairs({ 'n', 'x' }) do
    for _, suffix in ipairs({
      'rg', 'rw', 'rW', 'rl', 'rc',
      'ff', 'fw', 'fW', 'fl',
      'Rg', 'Rw', 'RW', 'Rl', 'Rc',
      'Ff', 'Fw', 'FW', 'Fl',
      'rp', 'Rp',
      'Bg', 'Bw', 'BW', 'Bl',
      'm', 'j', 'hH', 'hh', 'b',
      'gg', 'gs', 'gl', 'gL', 'gw', 'gW',
      'Gl', 'Gw', 'GW',
      'RR', 'M', 'g?', 'gf', 'W',
    }) do
      pcall(vim.keymap.del, mode, leader .. suffix)
    end
  end
  -- Unload all siefe modules so the next source() re-executes them
  for k in pairs(package.loaded) do
    if k:match('^siefe') then
      package.loaded[k] = nil
    end
  end
end

-- ── 1. No error on source ─────────────────────────────────────────────────────

T.group('plugin source: no error with default config', function()
  reset()
  local err = source_plugin()
  T.eq(err, nil, 'plugin/siefe.lua should source without error (err=' .. tostring(err) .. ')')
end)

-- ── 2. <Plug> mappings are created ───────────────────────────────────────────

T.group('plugin source: Plug mappings exist', function()
  reset()
  source_plugin()
  T.eq(vim.fn.hasmapto('<Plug>SiefeRg') == 1 or vim.fn.maparg('<Plug>SiefeRg', 'n') ~= '', true, '<Plug>SiefeRg exists')
  T.eq(
    vim.fn.hasmapto('<Plug>SiefeGitLog') == 1 or vim.fn.maparg('<Plug>SiefeGitLog', 'n') ~= '',
    true,
    '<Plug>SiefeGitLog exists'
  )
end)

-- ── 3. User commands are created ─────────────────────────────────────────────

T.group('plugin source: user commands exist', function()
  reset()
  source_plugin()
  local cmds = vim.api.nvim_get_commands({})
  T.eq(cmds['SiefeRg'] ~= nil, true, 'SiefeRg command exists')
  T.eq(cmds['SiefeGitLog'] ~= nil, true, 'SiefeGitLog command exists')
  T.eq(cmds['SiefeInstall'] ~= nil, true, 'SiefeInstall command exists')
  T.eq(cmds['SiefeBuffers'] ~= nil, true, 'SiefeBuffers command exists')
  T.eq(cmds['SiefeHistory'] ~= nil, true, 'SiefeHistory command exists')
  T.eq(cmds['SiefeWindows'] ~= nil, true, 'SiefeWindows command exists')
end)

-- ── 4. Default key mappings when map_keys = true (default) ───────────────────

T.group('plugin source: default maps present with map_keys=true', function()
  reset()
  source_plugin()
  -- <leader>rg should be mapped by default
  local leader = vim.g.mapleader or '\\'
  local lhs = leader .. 'rg'
  T.eq(vim.fn.maparg(lhs, 'n') ~= '', true, lhs .. ' mapping present with default map_keys')
end)

-- ── 5. No default maps when map_keys = false ─────────────────────────────────

T.group('plugin source: default maps absent with map_keys=false', function()
  reset()
  -- Call setup with map_keys=false BEFORE sourcing plugin
  require('siefe').setup({ map_keys = false })
  source_plugin()
  local leader = vim.g.mapleader or '\\'
  local lhs = leader .. 'rg'
  T.eq(vim.fn.maparg(lhs, 'n'), '', lhs .. ' mapping absent with map_keys=false')
  -- But <Plug> mappings must still exist (the mapping name uses uppercase RG)
  T.eq(vim.fn.maparg('<Plug>SiefeRG', 'n') ~= '', true, '<Plug>SiefeRG still exists with map_keys=false')
end)

-- ── 6. Idempotent: second source does not error ───────────────────────────────

T.group('plugin source: idempotent (second source is a no-op)', function()
  reset()
  source_plugin()
  -- plugin sets vim.g.loaded_siefe_lua = 1; second source returns early
  local err = source_plugin()
  T.eq(err, nil, 'second source should not error')
end)

T.finish()
