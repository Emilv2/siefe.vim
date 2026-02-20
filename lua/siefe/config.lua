-- lua/siefe/config.lua
-- Default configuration and key bindings for siefe.vim
local M = {}

-- Helper: read from vim.g with fallback to default
local function g(name, default)
  local v = vim.g[name]
  if v == nil then return default end
  return v
end

-- Returns the full config table (reads vim.g.* for user overrides)
function M.load()
  local cfg = {}

  -- General behaviour
  cfg.loclist               = g('siefe_loclist', false)
  cfg.rg_loclist            = g('siefe_rg_loclist', cfg.loclist)
  cfg.gitlog_loclist        = g('siefe_gitlog_loclist', cfg.loclist)
  cfg.history_loclist       = g('siefe_history_loclist', cfg.loclist)
  cfg.marks_loclist         = g('siefe_marks_loclist', cfg.loclist)

  cfg.delta_options         = g('siefe_delta_options', '--keep-plus-minus-markers') .. ' ' .. g('siefe_delta_extra_options', '')
  cfg.bat_options           = g('siefe_bat_options', '--style=numbers,changes') .. ' ' .. g('siefe_bat_extra_options', '')

  -- Navigation / accept / help keys (common to all pickers)
  cfg.abort_key             = g('siefe_abort_key', 'esc')
  cfg.next_history_key      = g('siefe_next_history_key', 'ctrl-n')
  cfg.previous_history_key  = g('siefe_previous_history_key', 'ctrl-p')
  cfg.up_key                = g('siefe_up_key', 'ctrl-k')
  cfg.down_key              = g('siefe_down_key', 'ctrl-j')
  cfg.accept_key            = g('siefe_accept_key', 'ctrl-m')
  cfg.toggle_up_key         = g('siefe_toggle_up_key', 'tab')
  cfg.toggle_down_key       = g('siefe_toggle_down_key', 'shift-tab')
  cfg.help_key              = g('siefe_help_key', 'f9')
  cfg.toggle_preview_key    = g('siefe_toggle_preview_key', 'ctrl-/')

  -- Window-open actions
  cfg.split_key             = g('siefe_split_key', 'ctrl-]')
  cfg.vsplit_key            = g('siefe_vsplit_key', 'ctrl-\\')
  cfg.tab_key               = g('siefe_tab_key', 'alt-enter')
  cfg.vdiffsplit_key        = g('siefe_vdiffsplit_key', 'alt-d')

  -- Preview size
  cfg.preview_hide_threshold   = tonumber(g('siefe_preview_hide_threshold', 80))
  cfg.default_preview_size     = tonumber(g('siefe_default_preview_size', 50))
  cfg.second_preview_size      = tonumber(g('siefe_2nd_preview_size', 80))

  -- Ripgrep keys
  cfg.rg_toggle_fzf_key     = g('siefe_rg_toggle_fzf_key', 'ctrl-r')
  cfg.rg_rgfzf_key          = g('siefe_rg_rgfzf_key', 'alt-f')
  cfg.rg_files_key          = g('siefe_rg_files_key', 'ctrl-f')
  cfg.rg_type_key           = g('siefe_rg_type_key', 'ctrl-t')
  cfg.rg_type_not_key       = g('siefe_rg_type_not_key', 'ctrl-^')
  cfg.rg_word_key           = g('siefe_rg_word_key', 'ctrl-w')
  cfg.rg_case_key           = g('siefe_rg_case_key', 'ctrl-s')
  cfg.rg_hidden_key         = g('siefe_rg_hidden_key', 'alt-.')
  cfg.rg_no_ignore_key      = g('siefe_rg_no_ignore_key', 'ctrl-u')
  cfg.rg_fixed_strings_key  = g('siefe_rg_fixed_strings_key', 'ctrl-x')
  cfg.rg_max_1_key          = g('siefe_rg_max_1_key', 'ctrl-a')
  cfg.rg_search_zip_key     = g('siefe_rg_search_zip_key', 'alt-z')
  cfg.rg_text_key           = g('siefe_rg_text_key', 'alt-t')
  cfg.rg_dir_key            = g('siefe_rg_dir_key', 'ctrl-d')
  cfg.rg_buffers_key        = g('siefe_rg_buffers_key', 'ctrl-b')
  cfg.rg_yank_key           = g('siefe_rg_yank_key', 'ctrl-y')
  cfg.rg_history_key        = g('siefe_rg_history_key', 'ctrl-h')
  cfg.rg_depth1_key         = g('siefe_rg_depth1_key', 'ctrl-e')

  cfg.rg_preview_key        = g('siefe_rg_preview_key', 'f1')
  cfg.rg_fast_preview_key   = g('siefe_rg_fast_preview_key', 'f2')
  cfg.rg_faster_preview_key = g('siefe_rg_faster_preview_key', 'f3')

  -- Ripgrep defaults
  cfg.rg_fzf_default            = g('siefe_rg_fzf_default', false)
  cfg.rg_default_preview_command = tonumber(g('siefe_rg_default_preview_command', 0))
  cfg.rg_default_word           = g('siefe_rg_default_word', false)
  cfg.rg_default_depth1         = g('siefe_rg_default_depth1', false)
  cfg.rg_default_case_sensitive = tonumber(g('siefe_rg_default_case_sensitive', 1))
  cfg.rg_default_hidden         = g('siefe_rg_default_hidden', false)
  cfg.rg_default_no_ignore      = tonumber(g('siefe_rg_default_no_ignore', 0))
  cfg.rg_default_fixed_strings  = g('siefe_rg_default_fixed_strings', false)
  cfg.rg_default_max_1          = g('siefe_rg_default_max_1', false)
  cfg.rg_default_search_zip     = g('siefe_rg_default_search_zip', false)
  cfg.rg_default_text           = g('siefe_rg_default_text', false)

  -- History keys
  cfg.history_git_key           = g('siefe_history_git_key', 'ctrl-g')
  cfg.history_buffers_key       = g('siefe_history_buffers_key', 'ctrl-b')
  cfg.history_files_key         = g('siefe_history_files_key', 'ctrl-l')
  cfg.history_rg_key            = g('siefe_history_rg_key', 'ctrl-s')
  cfg.history_delete_key        = g('siefe_history_delete_key', 'del')
  cfg.history_edit_key          = g('siefe_history_edit_key', 'ctrl-e')
  cfg.history_preview_key       = g('siefe_history_preview_key', g('siefe_rg_preview_key', 'f1'))
  cfg.history_fast_preview_key  = g('siefe_history_fast_preview_key', g('siefe_rg_fast_preview_key', 'f2'))
  cfg.history_faster_preview_key= g('siefe_history_faster_preview_key', g('siefe_rg_faster_preview_key', 'f3'))
  cfg.history_default_preview_command = tonumber(g('siefe_history_default_preview_command', g('siefe_rg_default_preview_command', 0)))

  -- Git log keys
  cfg.gitlog_ignore_case_key    = g('siefe_gitlog_ignore_case_key', 'alt-i')
  cfg.gitlog_vdiffsplit_key     = g('siefe_gitlog_vdiffsplit_key', 'ctrl-v')
  cfg.gitlog_type_key           = g('siefe_gitlog_type_key', 'ctrl-t')
  cfg.gitlog_author_key         = g('siefe_gitlog_author_key', 'ctrl-a')
  cfg.gitlog_branch_key         = g('siefe_gitlog_branch_key', 'ctrl-b')
  cfg.gitlog_not_branch_key     = g('siefe_gitlog_not_branch_key', 'ctrl-^')
  cfg.gitlog_sg_key             = g('siefe_gitlog_sg_key', 'ctrl-e')
  cfg.gitlog_fzf_key            = g('siefe_gitlog_fzf_key', 'ctrl-f')
  cfg.gitlog_s_key              = g('siefe_gitlog_s_key', 'ctrl-s')
  cfg.gitlog_pickaxe_regex_key  = g('siefe_gitlog_pickaxe_regex_key', 'ctrl-x')
  cfg.gitlog_dir_key            = g('siefe_gitlog_dir_key', 'ctrl-d')
  cfg.gitlog_follow_key         = g('siefe_gitlog_follow_key', 'ctrl-o')
  cfg.gitlog_switch_key         = g('siefe_gitlog_switch_key', 'ctrl-s')
  cfg.gitlog_preview_0_key      = g('siefe_gitlog_preview_0_key', 'f1')
  cfg.gitlog_preview_1_key      = g('siefe_gitlog_preview_1_key', 'f2')
  cfg.gitlog_preview_2_key      = g('siefe_gitlog_preview_2_key', 'f3')
  cfg.gitlog_preview_3_key      = g('siefe_gitlog_preview_3_key', 'f4')
  cfg.gitlog_preview_4_key      = g('siefe_gitlog_preview_4_key', 'f5')
  cfg.gitlog_default_preview_command = tonumber(g('siefe_gitlog_default_preview_command', 0))
  cfg.gitlog_default_G          = g('siefe_gitlog_default_G', false)
  cfg.gitlog_default_regex      = g('siefe_gitlog_default_regex', false)
  cfg.gitlog_default_follow     = g('siefe_gitlog_default_follow', false)
  cfg.gitlog_default_ignore_case= g('siefe_gitlog_default_ignore_case', false)

  -- Git status keys
  cfg.gitstatus_uno_key           = g('siefe_gitstatus_uno_key', 'ctrl-n')
  cfg.gitstatus_add_key           = g('siefe_gitstatus_add_key', 'ctrl-a')
  cfg.gitstatus_add_patch_key     = g('siefe_gitstatus_add_patch_key', 'alt-a')
  cfg.gitstatus_restore_key       = g('siefe_gitstatus_restore_key', 'ctrl-r')
  cfg.gitstatus_restore_patch_key = g('siefe_gitstatus_restore_patch_key', 'alt-r')
  cfg.gitstatus_unstage_key       = g('siefe_gitstatus_unstage_key', 'ctrl-u')
  cfg.gitstatus_unstage_patch_key = g('siefe_gitstatus_unstage_patch_key', 'alt-u')
  cfg.gitstatus_stash_key         = g('siefe_gitstatus_stash_key', 'ctrl-s')
  cfg.gitstatus_stash_patch_key   = g('siefe_gitstatus_stash_patch_key', 'alt-s')
  cfg.gitstatus_preview_0_key     = g('siefe_gitstatus_preview_0_key', 'f1')
  cfg.gitstatus_preview_1_key     = g('siefe_gitstatus_preview_1_key', 'f2')

  -- Git branch keys
  cfg.gitbranch_preview_0_key   = g('siefe_gitbranch_preview_0_key', 'f1')
  cfg.gitbranch_preview_1_key   = g('siefe_gitbranch_preview_1_key', 'f2')
  cfg.gitbranch_preview_2_key   = g('siefe_gitbranch_preview_2_key', 'f3')
  cfg.gitbranch_preview_3_key   = g('siefe_gitbranch_preview_3_key', 'f4')
  cfg.branches_all_key          = g('siefe_branches_all_key', 'ctrl-a')
  cfg.branches_switch_key       = g('siefe_branches_switch_key', 'ctrl-o')
  cfg.branches_merge_key        = g('siefe_branches_merge_key', 'ctrl-e')
  cfg.branches_rebase_interactive_key = g('siefe_branches_rebase_interactive_key', 'ctrl-r')

  -- Git stash keys
  cfg.stash_apply_key           = g('siefe_stash_apply_key', 'ctrl-a')
  cfg.stash_pop_key             = g('siefe_stash_pop_key', 'ctrl-p')
  cfg.stash_drop_key            = g('siefe_stash_drop_key', 'del')
  cfg.stash_ignore_case_key     = g('siefe_stash_ignore_case_key', 'alt-i')
  cfg.stash_sg_key              = g('siefe_stash_sg_key', 'ctrl-e')
  cfg.stash_fzf_key             = g('siefe_stash_fzf_key', 'ctrl-f')
  cfg.stash_s_key               = g('siefe_stash_s_key', 'ctrl-s')
  cfg.stash_pickaxe_regex_key   = g('siefe_stash_pickaxe_regex_key', 'ctrl-x')
  cfg.stash_preview_0_key       = g('siefe_stash_preview_0_key', 'f1')
  cfg.stash_preview_1_key       = g('siefe_stash_preview_1_key', 'f2')
  cfg.stash_preview_2_key       = g('siefe_stash_preview_2_key', 'f3')
  cfg.stash_preview_3_key       = g('siefe_stash_preview_3_key', 'f4')
  cfg.stash_preview_4_key       = g('siefe_stash_preview_4_key', 'f5')
  cfg.stash_default_preview_command = tonumber(g('siefe_stash_default_preview_command', 0))

  -- Buffer keys
  cfg.buffers_delete_key        = g('siefe_buffers_delete_key', 'del')
  cfg.buffers_git_key           = g('siefe_buffers_git_key', 'ctrl-p')
  cfg.buffers_history_key       = g('siefe_buffers_history_key', 'ctrl-h')
  cfg.buffers_default_preview_command = tonumber(g('siefe_buffers_default_preview_command', g('siefe_rg_default_preview_command', 0)))
  cfg.buffers_preview_key       = g('siefe_buffers_preview_key', g('siefe_rg_preview_key', 'f1'))
  cfg.buffers_fast_preview_key  = g('siefe_buffers_fast_preview_key', g('siefe_rg_fast_preview_key', 'f2'))
  cfg.buffers_jump              = g('siefe_buffers_jump', false)

  -- Mark keys
  cfg.marks_delete_key          = g('siefe_marks_delete_key', 'del')
  cfg.marks_yank_key            = g('siefe_marks_yank_key', 'ctrl-y')
  cfg.marks_default_preview_command = tonumber(g('siefe_marks_default_preview_command', g('siefe_rg_default_preview_command', 0)))
  cfg.marks_preview_key         = g('siefe_marks_preview_key', g('siefe_rg_preview_key', 'f1'))
  cfg.marks_fast_preview_key    = g('siefe_marks_fast_preview_key', g('siefe_rg_fast_preview_key', 'f2'))

  -- Jump keys
  cfg.jumps_yank_key            = g('siefe_jumps_yank_key', 'ctrl-y')
  cfg.jumps_clear_key           = g('siefe_jumps_clear_key', 'del')
  cfg.jumps_preview_key         = g('siefe_jumps_preview_key', g('siefe_rg_preview_key', 'f1'))
  cfg.jumps_fast_preview_key    = g('siefe_jumps_fast_preview_key', g('siefe_rg_fast_preview_key', 'f2'))
  cfg.jumps_default_preview_command = tonumber(g('siefe_jumps_default_preview_command', g('siefe_rg_default_preview_command', 0)))

  -- Register keys
  cfg.registers_paste_key       = g('siefe_registers_paste_key', 'ctrl-p')
  cfg.registers_edit_key        = g('siefe_registers_edit_key', 'ctrl-e')
  cfg.registers_execute_key     = g('siefe_registers_execute_key', 'ctrl-x')
  cfg.registers_clear_key       = g('siefe_registers_clear_key', 'del')

  -- Maps keys
  cfg.maps_open_key             = g('siefe_maps_open_key', 'ctrl-o')
  cfg.maps_modes_key            = g('siefe_maps_modes_key', 'ctrl-d')
  cfg.modes_select_all_key      = g('siefe_modes_select_all_key', 'ctrl-a')

  -- fd / dir select keys
  cfg.fd_hidden_key             = g('siefe_fd_hidden_key', 'ctrl-h')
  cfg.fd_no_ignore_key          = g('siefe_fd_no_ignore_key', 'ctrl-u')
  cfg.fd_git_root_key           = g('siefe_fd_git_root_key', 'ctrl-r')
  cfg.fd_project_root_key       = g('siefe_fd_project_root_key', 'alt-o')
  cfg.fd_search_git_root_key    = g('siefe_fd_search_git_root_key', 'ctrl-s')
  cfg.fd_search_project_root_key= g('siefe_fd_search_project_root_key', 'alt-e')
  cfg.fd_depth1_key             = g('siefe_fd_depth1_key', g('siefe_rg_depth1_key', 'ctrl-e'))
  cfg.fd_open_dir_key           = g('siefe_fd_open_dir_key', 'ctrl-o')
  cfg.fd_project_root_env       = g('siefe_fd_project_root_env', g('siefe_fd_git_root_env', ''))

  -- Window action map
  cfg.common_window_actions = {
    [cfg.vdiffsplit_key] = 'vert diffsplit',
    [cfg.tab_key]        = 'tab split',
    [cfg.split_key]      = 'split',
    [cfg.vsplit_key]     = 'vsplit',
  }
  cfg.fugitive_window_actions = {
    ['tab split']        = 'Gtabedit',
    ['split']            = 'Gsplit',
    ['vsplit']           = 'Gvsplit',
  }

  return cfg
end

-- Singleton config (loaded once)
local _cfg = nil
local mt = {
  __index = function(t, k)
    if _cfg == nil then _cfg = M.load() end
    return _cfg[k]
  end,
  __newindex = function(t, k, v)
    if _cfg == nil then _cfg = M.load() end
    _cfg[k] = v
  end,
}
return setmetatable({}, mt)
