-- lua/siefe/config.lua
-- Default configuration and key bindings for siefe.vim
local M = {}

-- Pure Lua defaults — no vim.g reads
local function make_defaults()
  local d = {}

  -- General behaviour
  d.map_keys = true -- set to false to disable all default <leader> mappings
  d.loclist = false
  d.rg_loclist = false
  d.gitlog_loclist = false
  d.history_loclist = false
  d.marks_loclist = false

  d.delta_options = '--keep-plus-minus-markers'

  -- Navigation / accept / help keys (common to all pickers)
  d.abort_key = 'esc'
  d.next_history_key = 'ctrl-n'
  d.previous_history_key = 'ctrl-p'
  d.up_key = 'ctrl-k'
  d.down_key = 'ctrl-j'
  d.accept_key = 'ctrl-m'
  d.toggle_up_key = 'tab'
  d.toggle_down_key = 'shift-tab'
  d.toggle_preview_key = 'ctrl-/' -- fzf-lua F1 is the built-in help key

  -- Window-open actions
  d.split_key = 'ctrl-]'
  d.vsplit_key = 'ctrl-\\'
  d.tab_key = 'alt-enter'
  d.vdiffsplit_key = 'alt-d'

  -- Window layout
  d.win_height = 0.40 -- height as fraction of screen (0.0–1.0) for non-fullscreen pickers

  -- Preview size
  d.preview_hide_threshold = 80
  d.default_preview_size = 50
  d.second_preview_size = 80

  -- Ripgrep keys
  d.rg_toggle_fzf_key = 'ctrl-r'
  d.rg_rgfzf_key = 'alt-f'
  d.rg_files_key = 'ctrl-f'
  d.rg_type_key = 'ctrl-t'
  d.rg_type_not_key = 'ctrl-^'
  d.rg_word_key = 'ctrl-w'
  d.rg_case_key = 'ctrl-s'
  d.rg_hidden_key = 'alt-.'
  d.rg_no_ignore_key = 'ctrl-u'
  d.rg_fixed_strings_key = 'ctrl-x'
  d.rg_max_1_key = 'ctrl-a'
  d.rg_search_zip_key = 'alt-z'
  d.rg_text_key = 'alt-t'
  d.rg_dir_key = 'ctrl-d'
  d.rg_buffers_key = 'ctrl-b'
  d.rg_yank_key = 'ctrl-y'
  d.rg_history_key = 'ctrl-h'
  d.rg_depth1_key = 'ctrl-e'
  -- Ripgrep defaults
  d.rg_fzf_default = false
  d.rg_default_word = false
  d.rg_default_depth1 = false
  d.rg_default_case_sensitive = 1
  d.rg_default_hidden = false
  d.rg_default_no_ignore = 0
  d.rg_default_fixed_strings = false
  d.rg_default_max_1 = false
  d.rg_default_search_zip = false
  d.rg_default_text = false

  -- History keys
  d.history_git_key = 'ctrl-g'
  d.history_buffers_key = 'ctrl-b'
  d.history_files_key = 'ctrl-l'
  d.history_rg_key = 'ctrl-s'
  d.history_delete_key = 'del'
  d.history_edit_key = 'ctrl-e'

  -- Git log keys
  d.gitlog_ignore_case_key = 'alt-i'
  d.gitlog_vdiffsplit_key = 'ctrl-v'
  d.gitlog_type_key = 'ctrl-t'
  d.gitlog_author_key = 'ctrl-a'
  d.gitlog_branch_key = 'ctrl-b'
  d.gitlog_not_branch_key = 'ctrl-^'
  d.gitlog_sg_key = 'ctrl-e'
  d.gitlog_fzf_key = 'ctrl-f'
  d.gitlog_s_key = 'ctrl-s'
  d.gitlog_pickaxe_regex_key = 'ctrl-x'
  d.gitlog_dir_key = 'ctrl-d'
  d.gitlog_follow_key = 'ctrl-o'
  d.gitlog_switch_key = 'ctrl-s'
  d.gitlog_preview_cycle_key = 'f7'
  d.gitlog_default_G = false
  d.gitlog_default_regex = false
  d.gitlog_default_follow = false
  d.gitlog_default_ignore_case = false

  -- Git status keys
  d.gitstatus_uno_key = 'ctrl-n'
  d.gitstatus_add_key = 'ctrl-a'
  d.gitstatus_add_patch_key = 'alt-a'
  d.gitstatus_restore_key = 'ctrl-r'
  d.gitstatus_restore_patch_key = 'alt-r'
  d.gitstatus_unstage_key = 'ctrl-u'
  d.gitstatus_unstage_patch_key = 'alt-u'
  d.gitstatus_stash_key = 'ctrl-s'
  d.gitstatus_stash_patch_key = 'alt-s'
  d.gitstatus_preview_0_key = 'f1'
  d.gitstatus_preview_1_key = 'f2'

  -- Git branch keys
  d.gitbranch_preview_0_key = 'f1'
  d.gitbranch_preview_1_key = 'f2'
  d.gitbranch_preview_2_key = 'f7'
  d.gitbranch_preview_3_key = 'f8'
  d.branches_all_key = 'ctrl-a'
  d.branches_switch_key = 'ctrl-o'
  d.branches_merge_key = 'ctrl-e'
  d.branches_rebase_interactive_key = 'ctrl-r'

  -- Git stash keys
  d.stash_apply_key = 'ctrl-a'
  d.stash_pop_key = 'ctrl-p'
  d.stash_drop_key = 'del'
  d.stash_ignore_case_key = 'alt-i'
  d.stash_sg_key = 'ctrl-e'
  d.stash_fzf_key = 'ctrl-f'
  d.stash_s_key = 'ctrl-s'
  d.stash_pickaxe_regex_key = 'ctrl-x'
  d.stash_preview_cycle_key = 'f7'

  -- Window keys
  d.windows_close_key = 'del'

  -- Buffer keys
  d.buffers_delete_key = 'del'
  d.buffers_git_key = 'ctrl-p'
  d.buffers_history_key = 'ctrl-h'
  d.buffers_jump = false

  -- Mark keys
  d.marks_delete_key = 'del'
  d.marks_yank_key = 'ctrl-y'

  -- Jump keys
  d.jumps_yank_key = 'ctrl-y'
  d.jumps_clear_key = 'del'

  -- Register keys
  d.registers_paste_key = 'ctrl-p'
  d.registers_edit_key = 'ctrl-e'
  d.registers_execute_key = 'ctrl-x'
  d.registers_clear_key = 'del'

  -- Maps keys
  d.maps_open_key = 'ctrl-o'
  d.maps_modes_key = 'ctrl-d'
  d.modes_select_all_key = 'ctrl-a'

  -- fd / dir select keys
  d.fd_hidden_key = 'ctrl-h'
  d.fd_no_ignore_key = 'ctrl-u'
  d.fd_git_root_key = 'ctrl-r'
  d.fd_project_root_key = 'alt-o'
  d.fd_search_git_root_key = 'ctrl-s'
  d.fd_search_project_root_key = 'alt-e'
  d.fd_depth1_key = d.rg_depth1_key
  d.fd_open_dir_key = 'ctrl-o'
  d.fd_project_root_env = ''

  -- Window action maps (built from key fields above)
  d.common_window_actions = {
    [d.vdiffsplit_key] = 'vert diffsplit',
    [d.tab_key] = 'tab split',
    [d.split_key] = 'split',
    [d.vsplit_key] = 'vsplit',
  }
  d.fugitive_window_actions = {
    ['tab split'] = 'Gtabedit',
    ['split'] = 'Gsplit',
    ['vsplit'] = 'Gvsplit',
  }

  return d
end

-- Active config (nil until setup() or first access)
local _cfg = nil

-- Merge user opts over defaults and rebuild derived tables
function M.setup(opts)
  _cfg = vim.tbl_deep_extend('force', make_defaults(), opts or {})
  -- Rebuild window-action maps in case the user overrode any key fields
  _cfg.common_window_actions = {
    [_cfg.vdiffsplit_key] = 'vert diffsplit',
    [_cfg.tab_key] = 'tab split',
    [_cfg.split_key] = 'split',
    [_cfg.vsplit_key] = 'vsplit',
  }
  _cfg.fugitive_window_actions = {
    ['tab split'] = 'Gtabedit',
    ['split'] = 'Gsplit',
    ['vsplit'] = 'Gvsplit',
  }
end

-- Proxy: lazily initialise from defaults if setup() was never called
return setmetatable(M, {
  __index = function(_, k)
    if k == 'setup' then
      return M.setup
    end
    if _cfg == nil then
      M.setup()
    end
    return _cfg[k]
  end,
  __newindex = function(_, k, v)
    if _cfg == nil then
      M.setup()
    end
    _cfg[k] = v
  end,
})
