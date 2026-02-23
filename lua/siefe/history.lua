-- lua/siefe/history.lua
-- File history picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

-- Parse an entry returned by fzf.
--
-- New SOH format (produced by make_history_entry): fname\x01lnum\x01col\x01display
--   fname is field 1 so fzf-lua's entry_to_file() can parse it directly.
-- Intermediate tab format (older sessions): lnum\tcol\tfname[\tdisplay]
-- Legacy formats (from older entries / utils.recent_*_info):
--   lnum//col//fname  (fname may itself contain "//")
--   lnum//fname       (no col)
local function parse_entry(line)
  if line:find('\x01', 1, true) then
    -- New SOH-separated format: fname\x01lnum\x01col\x01display
    local parts = vim.split(line, '\x01', { plain = true })
    return tonumber(parts[2]) or 0, tonumber(parts[3]) or 0, parts[1] or ''
  end
  if line:find('\t', 1, true) then
    -- Intermediate tab-separated format: lnum\tcol\tfname\tdisplay
    local parts = vim.split(line, '\t', { plain = true })
    return tonumber(parts[1]) or 0, tonumber(parts[2]) or 0, parts[3] or ''
  end
  -- Legacy //-separated format
  local parts = vim.split(line, '//', { plain = true })
  if #parts >= 3 then
    return tonumber(parts[1]) or 0, tonumber(parts[2]) or 0, table.concat(vim.list_slice(parts, 3), '//')
  elseif #parts == 2 then
    return tonumber(parts[1]) or 0, 0, parts[2]
  end
  return 0, 0, line
end

-- Build a history source entry for fzf --with-nth=4..
-- Format: fname\x01lnum\x01col\x01DISPLAY
-- fname is field 1 so fzf-lua's entry_to_file() (builtin previewer) parses it
-- unambiguously using \x01 as delimiter — no fs_stat calls needed.
-- DISPLAY = "lnum[:col] fname" (lnum colored green when > 0).
local function make_history_entry(lnum, col, fname)
  local pos = (lnum > 0) and (utils.green(tostring(lnum)) .. (col > 0 and utils.green(':' .. tostring(col)) or ''))
    or ''
  local display = pos ~= '' and (pos .. ' ' .. fname) or fname
  return fname .. '\x01' .. tostring(lnum) .. '\x01' .. tostring(col) .. '\x01' .. display
end

function M.historyoldfiles(fullscreen, kwargs)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end

  kwargs.query = kwargs.query or ''
  kwargs.project = kwargs.project ~= nil and kwargs.project or false

  local bufdir = utils.bufdir()
  local git_root = vim.trim(vim.fn.system('git -C ' .. vim.fn.shellescape(bufdir) .. ' rev-parse --show-toplevel'))
  local in_git = vim.v.shell_error == 0
  local git_help = ''

  if in_git then
    local toggle = kwargs.project and 'off' or 'on'
    git_help = ' ╱ ' .. utils.prettify_header(config.history_git_key, 'project history:' .. toggle)
  end

  -- Detect shada2fzf binary (used only for non-project mode to stream MRU positions)
  local shada2fzf_bin = utils.bin_path('shada2fzf')
  local has_shada2fzf = (not kwargs.project) and vim.fn.executable(shada2fzf_bin) == 1

  local source
  local project_prefix = ''
  if kwargs.project and in_git then
    source = vim.tbl_map(function(e)
      local lnum, col, fname = parse_entry(e)
      return make_history_entry(lnum, col, fname)
    end, utils.recent_git_files_info())
    project_prefix = utils.get_git_basename_or_bufdir() .. ' '
  elseif has_shada2fzf then
    -- Streaming source: emit current buffer + listed buffers immediately, then
    -- pipe shada2fzf for all historically-visited files with saved positions.
    -- Uses a coroutine so fzf sees entries as they arrive (responsive on large
    -- shada files) and no filereadable() NFS calls are made for old files.
    source = (function()
      -- Build the prefix entries (current buf + listed buffers) synchronously
      local prefix = {}
      local visited = {}

      local cur = vim.fn.expand('%')
      if cur ~= '' then
        local fname = vim.fn.fnamemodify(cur, ':~:.')
        local lnum = vim.fn.line('.')
        table.insert(prefix, make_history_entry(lnum, 0, fname))
        visited[fname] = true
      end
      for _, b in ipairs(utils.buflisted_sorted()) do
        local name = vim.fn.bufname(b)
        if name ~= '' then
          local fname = vim.fn.fnamemodify(vim.fn.expand(name), ':~:.')
          if not visited[fname] then
            local lnum = (vim.fn.getbufinfo(b)[1] or {}).lnum or 0
            table.insert(prefix, make_history_entry(lnum, 0, fname))
            visited[fname] = true
          end
        end
      end

      local shada_path = utils.shada_path()
      local s2f = shada2fzf_bin
      local vis = visited -- capture for the coroutine closure

      return function(fzf_cb)
        -- Emit current buf + listed buffers immediately
        for _, e in ipairs(prefix) do
          fzf_cb(e)
        end

        -- Stream shada2fzf output: `line//col//filename\n`
        -- shada2fzf has already sorted by timestamp desc (MRU order) and
        -- deduplicated, so we just skip files already in the prefix list.
        -- Note: filenames containing '//' are handled correctly — parse_entry
        -- uses table.concat(parts[3..], '//') to reconstruct them faithfully.
        -- io.popen is used for broad Neovim version compatibility; vim.system
        -- (0.10+) could replace this if a minimum version requirement is set.
        local f = io.popen(vim.fn.shellescape(s2f) .. ' ' .. vim.fn.shellescape(shada_path))
        if f then
          for line in f:lines() do
            -- Extract the filename (third //-field) and convert to 4-field display format
            local parts = vim.split(line, '//', { plain = true })
            local fname = #parts >= 3 and table.concat(vim.list_slice(parts, 3), '//') or nil
            if fname and fname ~= '' and not vis[fname] then
              local lnum = tonumber(parts[1]) or 0
              local col = tonumber(parts[2]) or 0
              fzf_cb(make_history_entry(lnum, col, fname))
              vis[fname] = true
            end
          end
          f:close()
        end

        fzf_cb(nil) -- signal EOF to fzf-lua
      end
    end)()
  else
    source = vim.tbl_map(function(e)
      local lnum, col, fname = parse_entry(e)
      return make_history_entry(lnum, col, fname)
    end, utils.recent_files_info())
  end

  local default_size, other_size = utils.preview_window_size()

  local hist_km = utils.make_binds({
    ['change'] = 'first',
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    [config.toggle_preview_key] = {
      'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
      desc = 'cycle-preview',
    },
  })

  -- Shows current buffer at top as a "header line"
  local header_lines = (vim.fn.expand('%') ~= '') and 1 or 0

  local fzf_opts = {
    ['--history'] = utils.data_path() .. '/rg_history_history',
    ['--ansi'] = '',
    ['--multi'] = '',
    -- Entry format: fname\x01lnum\x01col\x01display
    -- \x01 delimiter lets entry_to_file() parse fname without fs_stat.
    ['--with-nth'] = '4..',
    ['--delimiter'] = '\x01',
    ['--preview-window'] = default_size,
    ['--header-lines'] = tostring(header_lines),
    ['--prompt'] = project_prefix .. 'Hist> ',
  }

  -- ── Helpers ─────────────────────────────────────────────────────────────────

  local function get_query(selected, opts)
    return (opts and opts.last_query) or kwargs.query or ''
  end

  local function get_items(selected, opts)
    return selected or {}
  end

  -- ── Actions ─────────────────────────────────────────────────────────────────

  local actions = {}

  actions['default'] = {
    fn = function(selected, opts)
      local items = get_items(selected, opts)
      if #items == 0 then
        return
      end
      local lnum, col, filename = parse_entry(items[1])
      utils.open_file('edit', filename, lnum > 0 and lnum or nil, col > 0 and col or nil)
      if #items > 1 then
        local qf = vim.tbl_map(function(l)
          local _, _, fname = parse_entry(l)
          return { filename = fname }
        end, items)
        if config.history_loclist then
          utils.fill_loc(qf)
        else
          utils.fill_quickfix(qf)
        end
      end
    end,
    desc = 'open',
  }

  for key, cmd in pairs(config.common_window_actions) do
    local k, c = key, cmd
    actions[k] = {
      fn = function(selected, opts)
        local items = get_items(selected, opts)
        for _, line in ipairs(items) do
          local lnum, col, filename = parse_entry(line)
          utils.open_file(c, filename, lnum > 0 and lnum or nil, col > 0 and col or nil)
        end
      end,
      desc = 'open ' .. c,
    }
  end

  actions[config.history_git_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.project = not kwargs.project
      M.historyoldfiles(fullscreen, kwargs)
    end,
    desc = 'project',
  }

  actions[config.history_buffers_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      local bufs = require('siefe.buffers')
      bufs.buffers(fullscreen, kwargs)
    end,
    desc = 'buffers',
  }

  actions[config.history_files_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.prompt = utils.get_relative_git_or_bufdir()
      kwargs.files = true
      local rg = require('siefe.rg')
      rg.ripgrepfzf(fullscreen, utils.bufdir(), kwargs)
    end,
    desc = 'files',
  }

  actions[config.history_rg_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.prompt = utils.get_relative_git_or_bufdir()
      -- Compute recent plain file paths (same as rg.lua's rg_history_key action).
      -- `source` here is a display-entry list or coroutine — not suitable as rg paths.
      local git_root = utils.get_git_root()
      kwargs.paths = utils.recent_files(git_root ~= '' and git_root or nil)
      kwargs.files = false
      local rg = require('siefe.rg')
      rg.ripgrepfzf(fullscreen, utils.bufdir(), kwargs)
    end,
    desc = 'rg',
  }

  -- Launch
  local launch_opts = {
    prompt = project_prefix .. 'Hist> ',
    query = kwargs.query,
    winopts = utils.winopts(fullscreen),
    previewer = 'builtin',
    fzf_opts = fzf_opts,
    keymap = hist_km,
    actions = actions,
  }
  if kwargs.project and in_git then
    launch_opts.cwd = git_root
  end

  fzf_lua.fzf_exec(source, launch_opts)
end

-- Test-only exports (not part of the public API).
-- Used by test/test_history.lua to exercise pure logic without launching fzf.
M._test = {
  parse_entry = parse_entry,
  make_history_entry = make_history_entry,
}

return M
