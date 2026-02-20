-- test/test_config.lua – tests for lua/siefe/config.lua
-- Run with: nvim --headless -u NONE -l test/test_config.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

local T = require('test.helpers')

-- Reset config state between test groups so each starts from defaults
local function reset()
  package.loaded['siefe.config'] = nil
end

-- ── Defaults ─────────────────────────────────────────────────────────────────

T.group('defaults', function()
  reset()
  local cfg = require('siefe.config')

  T.eq(cfg.abort_key,             'esc',         'abort_key')
  T.eq(cfg.accept_key,            'ctrl-m',      'accept_key')
  T.eq(cfg.toggle_preview_key,    'ctrl-/',      'toggle_preview_key')
  T.eq(cfg.split_key,             'ctrl-]',      'split_key')
  T.eq(cfg.vsplit_key,            'ctrl-\\',     'vsplit_key')
  T.eq(cfg.tab_key,               'alt-enter',   'tab_key')

  T.eq(cfg.loclist,               false,         'loclist')
  T.eq(cfg.rg_loclist,            false,         'rg_loclist')
  T.eq(cfg.gitlog_loclist,        false,         'gitlog_loclist')
  T.eq(cfg.history_loclist,       false,         'history_loclist')
  T.eq(cfg.marks_loclist,         false,         'marks_loclist')

  T.eq(cfg.delta_options,         '--keep-plus-minus-markers', 'delta_options')
  T.eq(cfg.bat_options,           '--style=numbers,changes',   'bat_options')

  T.eq(cfg.preview_hide_threshold,  80,  'preview_hide_threshold')
  T.eq(cfg.default_preview_size,    50,  'default_preview_size')
  T.eq(cfg.second_preview_size,     80,  'second_preview_size')

  T.eq(cfg.rg_fzf_default,           false, 'rg_fzf_default')
  T.eq(cfg.rg_default_preview_command, 0,   'rg_default_preview_command')
  T.eq(cfg.rg_default_case_sensitive,  1,   'rg_default_case_sensitive')
  T.eq(cfg.rg_default_hidden,         false, 'rg_default_hidden')
  T.eq(cfg.rg_default_no_ignore,       0,   'rg_default_no_ignore')
  T.eq(cfg.rg_default_fixed_strings,  false, 'rg_default_fixed_strings')
  T.eq(cfg.buffers_jump,              false, 'buffers_jump')
end)

-- ── Derived defaults: keys inherited from rg_* ───────────────────────────────

T.group('derived defaults', function()
  reset()
  local cfg = require('siefe.config')

  -- preview keys derive from rg_*
  T.eq(cfg.history_preview_key,      cfg.rg_preview_key,      'history_preview_key')
  T.eq(cfg.history_fast_preview_key, cfg.rg_fast_preview_key, 'history_fast_preview_key')
  T.eq(cfg.buffers_preview_key,      cfg.rg_preview_key,      'buffers_preview_key')
  T.eq(cfg.marks_preview_key,        cfg.rg_preview_key,      'marks_preview_key')
  T.eq(cfg.jumps_preview_key,        cfg.rg_preview_key,      'jumps_preview_key')
  T.eq(cfg.fd_depth1_key,            cfg.rg_depth1_key,       'fd_depth1_key')

  -- default_preview_command derives from rg_*
  T.eq(cfg.history_default_preview_command, cfg.rg_default_preview_command,
    'history_default_preview_command')
  T.eq(cfg.buffers_default_preview_command, cfg.rg_default_preview_command,
    'buffers_default_preview_command')
end)

-- ── setup() overrides ────────────────────────────────────────────────────────

T.group('setup() overrides', function()
  reset()
  local cfg = require('siefe.config')

  cfg.setup({ rg_loclist = true, abort_key = 'ctrl-c' })
  T.eq(cfg.rg_loclist, true,     'override rg_loclist')
  T.eq(cfg.abort_key,  'ctrl-c', 'override abort_key')
  -- untouched defaults remain
  T.eq(cfg.loclist,    false,    'loclist unchanged')
  T.eq(cfg.accept_key, 'ctrl-m', 'accept_key unchanged')
end)

-- ── setup() rebuilds window-action maps ──────────────────────────────────────

T.group('setup() window action maps', function()
  reset()
  local cfg = require('siefe.config')

  -- Default maps exist
  T.ok(cfg.common_window_actions['alt-d']    == 'vert diffsplit', 'vdiffsplit default')
  T.ok(cfg.common_window_actions['ctrl-]']   == 'split',          'split default')
  T.ok(cfg.common_window_actions['ctrl-\\']  == 'vsplit',         'vsplit default')
  T.ok(cfg.common_window_actions['alt-enter'] == 'tab split',     'tabedit default')

  -- Overriding a key rebuilds the map
  cfg.setup({ split_key = 'ctrl-g' })
  T.ok(cfg.common_window_actions['ctrl-g'] == 'split', 'split key override rebuilds map')
  T.ok(cfg.common_window_actions['ctrl-]'] == nil,     'old split key removed from map')
end)

-- ── setup() idempotent with empty opts ───────────────────────────────────────

T.group('setup() empty opts', function()
  reset()
  local cfg = require('siefe.config')
  cfg.setup()
  T.eq(cfg.abort_key, 'esc', 'abort_key still default after empty setup()')
  cfg.setup({})
  T.eq(cfg.abort_key, 'esc', 'abort_key still default after setup({})')
end)

T.finish()
