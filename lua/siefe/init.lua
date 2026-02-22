-- lua/siefe/init.lua
-- Main module: setup(), public API, buffer tracker
local M = {}

-- Buffer access-time tracker: { [bufnr] = timestamp }
M.buffers_tracker = {}

-- Public API (populated after setup)
M.config = nil

-- ── Setup ────────────────────────────────────────────────────────────────────

function M.setup(opts)
  -- Pass the Lua table directly into the config module
  require('siefe.config').setup(opts)
  -- Buffer tracker autocmd is already registered unconditionally by plugin/siefe.lua.
  -- Do NOT re-register it here: calling setup() must not cause BufEnter to fire twice.
end

-- ── Delegate to sub-modules ──────────────────────────────────────────────────

function M.ripgrepfzf(fullscreen, dir, kwargs)
  require('siefe.rg').ripgrepfzf(fullscreen, dir or require('siefe.utils').bufdir(), kwargs or {})
end

function M.gitlogfzf(fullscreen, kwargs)
  require('siefe.git_log').gitlogfzf(fullscreen, kwargs or {})
end

function M.gitstatus(fullscreen, kwargs)
  require('siefe.git_status').gitstatus(fullscreen, kwargs or {})
end

function M.toggle_git_status()
  require('siefe.git_status').toggle_git_status()
end

function M.gitstash(fullscreen, kwargs)
  require('siefe.git_stash').gitstash(fullscreen, kwargs or {})
end

function M.gitbranch(fullscreen)
  require('siefe.git_branch').gitbranch(fullscreen)
end

function M.historyoldfiles(fullscreen, kwargs)
  require('siefe.history').historyoldfiles(fullscreen, kwargs or {})
end

function M.buffers(fullscreen, kwargs)
  require('siefe.buffers').buffers(fullscreen, kwargs or {})
end

function M.marks(fullscreen, kwargs)
  require('siefe.marks').marks(fullscreen, kwargs or {})
end

function M.jumps(fullscreen, kwargs)
  require('siefe.jumps').jumps(fullscreen, kwargs or {})
end

function M.registers(fullscreen, kwargs)
  require('siefe.registers').registers(fullscreen, kwargs or {})
end

function M.maps(fullscreen, query, modes)
  require('siefe.maps').maps(fullscreen, query, modes)
end

function M.mode_select(fullscreen, query)
  require('siefe.maps').mode_select(fullscreen, query)
end

-- Helper used by VimScript compat layer
function M.bufdir()
  return require('siefe.utils').bufdir()
end

function M.visual_selection()
  return require('siefe.utils').visual_selection()
end

function M.visual_line_nu()
  return require('siefe.utils').visual_line_nu()
end

function M.recent_files(dir)
  return require('siefe.utils').recent_files(dir)
end

function M.recent_files_info()
  return require('siefe.utils').recent_files_info()
end

function M.recent_git_files_info()
  return require('siefe.utils').recent_git_files_info()
end

function M.get_git_root()
  return require('siefe.utils').get_git_root()
end

function M.get_git_basename_or_bufdir()
  return require('siefe.utils').get_git_basename_or_bufdir()
end

function M.get_relative_git_or_bufdir(dir, git_dir)
  return require('siefe.utils').get_relative_git_or_bufdir(dir, git_dir)
end

function M.git_file_existed(file)
  return require('siefe.utils').git_file_existed(file)
end

function M.fugitive_strip_header(file)
  return require('siefe.utils').fugitive_strip_header(file)
end

return M
