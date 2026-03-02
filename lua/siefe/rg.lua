-- lua/siefe/rg.lua
-- Ripgrep search – main picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function bool_to_flag(b, flag)
  return b and flag or ''
end

-- Build the rg command format string.
-- Returns a Lua format string where '%s' is the query placeholder.
-- Callers use string.format() to substitute either:
--   '{q}'  — fzf's live-query marker (for fzf_live mode), or
--   a shellescape'd query string (for fzf_exec static mode).
local function build_rg_command(kwargs)
  local logger = utils.bin_path('logger') .. ' ' .. vim.fn.shellescape(utils.log_path()) .. ' '
  local case = kwargs.case_sensitive == 1 and '--smart-case '
    or kwargs.case_sensitive == 2 and '--ignore-case '
    or '--case-sensitive '
  local word = bool_to_flag(kwargs.word, '-w ')
  local depth1 = bool_to_flag(kwargs.depth1, '-d1 ')
  local hidden = bool_to_flag(kwargs.hidden, '--hidden ')
  local no_ignore = kwargs.no_ignore == 1 and '-u '
    or kwargs.no_ignore == 2 and '-uu '
    or kwargs.no_ignore == 3 and '-uuu '
    or ''
  local fixed = bool_to_flag(kwargs.fixed_strings, '-F ')
  local max1 = bool_to_flag(kwargs.max_1, '-m1 ')
  local zip = bool_to_flag(kwargs.search_zip, '-z ')
  local text = bool_to_flag(kwargs.text, '--text ')
  local type_flag = kwargs.type or ''

  local paths = ''
  if kwargs.paths and #kwargs.paths > 0 then
    local p = {}
    for _, v in ipairs(kwargs.paths) do
      table.insert(p, vim.fn.shellescape(v))
    end
    paths = ' ' .. table.concat(p, ' ')
  end

  return logger
    .. 'rg '
    .. '--column --auto-hybrid-regex -U --glob \\!.git/objects '
    .. '--line-number --no-heading --color=always '
    .. '--colors "column:fg:green" --with-filename '
    .. case
    .. word
    .. depth1
    .. no_ignore
    .. hidden
    .. fixed
    .. max1
    .. zip
    .. text
    .. type_flag
    .. ' '
    .. '-- %s'
    .. paths
end

local function build_files_command(kwargs)
  local zip = bool_to_flag(kwargs.search_zip, '-z ')
  local text = bool_to_flag(kwargs.text, '--text ')
  local no_ign = kwargs.no_ignore == 1 and '-u '
    or kwargs.no_ignore == 2 and '-uu '
    or kwargs.no_ignore == 3 and '-uuu '
    or ''
  local hidden = bool_to_flag(kwargs.hidden, '--hidden ')
  local depth1 = bool_to_flag(kwargs.depth1, '-d1 ')
  local type_f = kwargs.type or ''

  -- --null outputs NUL-terminated paths (no newline between entries), which
  -- pairs with fzf's --read0 to handle filenames containing any special
  -- characters including colons and spaces.
  return 'rg --null ' .. zip .. text .. no_ign .. hidden .. depth1 .. ' --color=always --files ' .. type_f
end

local function build_prompt(kwargs, mode)
  local case_sym = kwargs.case_sensitive == 1 and '-S ' or kwargs.case_sensitive == 2 and '-i ' or '-s '
  local no_ign = kwargs.no_ignore == 1 and '-u '
    or kwargs.no_ignore == 2 and '-uu '
    or kwargs.no_ignore == 3 and '-uuu '
    or ''
  local word = bool_to_flag(kwargs.word, '-w ')
  local depth1 = bool_to_flag(kwargs.depth1, '-d1 ')
  local hidden = kwargs.hidden and '-. ' or ''
  local fixed = bool_to_flag(kwargs.fixed_strings, '-F ')
  local max1 = bool_to_flag(kwargs.max_1, '-m1 ')
  local zip = bool_to_flag(kwargs.search_zip, '-z ')
  local text = kwargs.text and '-a ' or ''
  local type_p = kwargs.type ~= '' and (kwargs.type .. ' ') or ''
  local base = kwargs.prompt or utils.get_relative_git_or_bufdir()

  if mode == 'files' then
    return no_ign .. depth1 .. hidden .. zip .. text .. type_p .. base .. ' Files> '
  else
    local fzf_rg = kwargs.fzf and 'fzf' or 'rg'
    return word
      .. depth1
      .. no_ign
      .. hidden
      .. case_sym
      .. fixed
      .. max1
      .. zip
      .. text
      .. type_p
      .. base
      .. ' '
      .. fzf_rg
      .. '> '
  end
end

-- ── Main function ─────────────────────────────────────────────────────────────

function M.ripgrepfzf(fullscreen, dir, kwargs)
  local ok, fzl = pcall(require, 'fzf-lua')
  if not ok then
    utils.warn('siefe: fzf-lua not found')
    return
  end
  local fzl_actions = require('fzf-lua.actions')

  if not dir or dir == '' then
    utils.warn('siefe: dir is empty')
    return
  end

  -- Set defaults
  kwargs.query = kwargs.query or ''
  kwargs.prompt = kwargs.prompt or utils.get_relative_git_or_bufdir()
  kwargs.word = kwargs.word ~= nil and kwargs.word or config.rg_default_word
  kwargs.depth1 = kwargs.depth1 ~= nil and kwargs.depth1 or config.rg_default_depth1
  kwargs.case_sensitive = kwargs.case_sensitive ~= nil and kwargs.case_sensitive or config.rg_default_case_sensitive
  kwargs.hidden = kwargs.hidden ~= nil and kwargs.hidden or config.rg_default_hidden
  kwargs.no_ignore = kwargs.no_ignore ~= nil and kwargs.no_ignore or config.rg_default_no_ignore
  kwargs.fixed_strings = kwargs.fixed_strings ~= nil and kwargs.fixed_strings or config.rg_default_fixed_strings
  kwargs.max_1 = kwargs.max_1 ~= nil and kwargs.max_1 or config.rg_default_max_1
  kwargs.search_zip = kwargs.search_zip ~= nil and kwargs.search_zip or config.rg_default_search_zip
  kwargs.text = kwargs.text ~= nil and kwargs.text or config.rg_default_text
  kwargs.orig_dir = kwargs.orig_dir or dir
  kwargs.paths = kwargs.paths or {}
  kwargs.type = kwargs.type or ''
  kwargs.files = kwargs.files ~= nil and kwargs.files or false
  kwargs.fzf = kwargs.fzf ~= nil and kwargs.fzf or config.rg_fzf_default

  -- Filter empty path entries
  local clean_paths = {}
  for _, p in ipairs(kwargs.paths) do
    if p ~= '' then
      table.insert(clean_paths, p)
    end
  end
  kwargs.paths = clean_paths

  local default_size, other_size = utils.preview_window_size()

  -- Determine mode
  local mode = kwargs.files and 'files' or (kwargs.fzf and 'fzf' or 'rg')

  -- Commands
  local cmd_fmt = build_rg_command(kwargs)
  local files_cmd = build_files_command(kwargs)

  local rg_km = utils.make_binds({
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    -- Wrap complex fzf bind strings as { action, desc = 'short' } so fzf-lua's
    -- F1 help shows the short description instead of the full action string.
    [config.toggle_preview_key] = {
      'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
      desc = 'cycle-preview',
    },
  })

  local fzf_opts = {
    ['--history'] = utils.data_path() .. '/rg_fzf_history',
    ['--ansi'] = '',
    ['--multi'] = '',
    -- Use NUL as the output record separator.  fzf-lua detects --print0 in
    -- fzf.lua (get_EOL("print0")) and splits fzf's output on NUL instead of
    -- newline, so multiline match text or special characters in entries are
    -- never confused with record boundaries.
    ['--print0'] = '',
    ['--prompt'] = build_prompt(kwargs, mode),
    -- For files mode, '+{}' tells fzf to scroll the preview to the selected
    -- file's position (a no-op for file lists, but harmless).  For search/fzf
    -- modes the builtin previewer scrolls to the matched line via
    -- entry_to_file() — no fzf-side '+{N}' scroll hint is needed or reliable.
    ['--preview-window'] = (mode == 'files') and ('+{},' .. default_size) or default_size,
    -- --read0 tells fzf to split its input stream on NUL bytes.
    -- Files mode: rg --null --files emits NUL-terminated paths directly.
    -- Search/fzf: rg emits newline-terminated output; no --read0 needed.
    ['--read0'] = mode == 'files' and '' or nil,
  }

  -- ── Helpers for actions ──────────────────────────────────────────────────────

  -- fzf-lua's fzf_wrap() adds --print-query internally and, before calling our
  -- action, strips selected[1] (the query) and stores it in opts.__call_opts.
  -- So when our fn(selected, opts) is called:
  --   selected[1] = first actual file/rg entry  (NOT the query)
  --   opts.__call_opts.search = current typed query (live/rg mode)
  --   opts.__call_opts.query  = current typed query (exec/files/fzf mode)
  local function get_query(_selected, opts)
    return (opts and opts.__call_opts and (opts.__call_opts.search or opts.__call_opts.query))
      or kwargs.query
      or ''
  end

  local function get_entries(selected)
    return selected or {}
  end

  -- Reopen picker after a toggle, preserving the current query.
  local function reopen(selected, opts, changes)
    kwargs.query = get_query(selected, opts)
    if changes then
      for k, v in pairs(changes) do
        kwargs[k] = v
      end
    end
    vim.schedule(function()
      M.ripgrepfzf(fullscreen, dir, kwargs)
    end)
  end

  -- ── Actions ──────────────────────────────────────────────────────────────────

  local actions = {}

  -- Open: first entry in current window; populate qf/ll for multi-select.
  -- Uses fzl_actions which calls entry_to_file() to handle file:line:col format.
  actions['default'] = {
    fn = function(selected, opts)
      local entries = get_entries(selected)
      if #entries == 0 then
        return
      end
      fzl_actions.file_edit({ entries[1] }, opts)
      if #entries > 1 then
        if config.rg_loclist then
          fzl_actions.file_sel_to_ll(entries, opts)
        else
          fzl_actions.file_sel_to_qf(entries, opts)
        end
      end
    end,
    desc = 'open',
  }

  -- Window open actions using native fzl_actions.
  local function make_open_action(win_cmd, desc)
    return {
      fn = function(selected, opts)
        local entries = get_entries(selected)
        if #entries == 0 then
          return
        end
        if win_cmd == 'split' then
          fzl_actions.file_split(entries, opts)
        elseif win_cmd == 'vsplit' then
          fzl_actions.file_vsplit(entries, opts)
        elseif win_cmd == 'tabedit' then
          fzl_actions.file_tabedit(entries, opts)
        end
      end,
      desc = desc,
    }
  end

  actions[config.split_key] = make_open_action('split', 'split')
  actions[config.vsplit_key] = make_open_action('vsplit', 'vsplit')
  actions[config.tab_key] = make_open_action('tabedit', 'tab')
  actions[config.vdiffsplit_key] = {
    fn = function(selected, _opts)
      local entries = get_entries(selected)
      if #entries == 0 then
        return
      end
      local parsed = utils.parse_rg_line(entries[1])
      if parsed then
        utils.open_file('vert diffsplit', parsed.filename, parsed.lnum, parsed.col)
      end
    end,
    desc = 'diff',
  }

  -- Toggle: fzf/rg mode
  -- header() always returns the current mode so it's always visible in --header.
  actions[config.rg_toggle_fzf_key] = {
    fn = function(selected, opts)
      if kwargs.files then
        reopen(selected, opts, { files = false })
      else
        reopen(selected, opts, { fzf = not kwargs.fzf })
      end
    end,
    desc = 'mode',
    header = function()
      return mode
    end,
  }

  -- Toggle: rg/fzf combined filter
  actions[config.rg_rgfzf_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { fzf = not kwargs.fzf })
    end,
    desc = 'rg/fzf',
    header = function()
      return kwargs.fzf and 'fzf' or nil
    end,
  }

  -- Toggle: files mode
  actions[config.rg_files_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { files = not kwargs.files })
    end,
    desc = 'files',
    header = function()
      return kwargs.files and 'files' or nil
    end,
  }

  -- Toggle: word boundary (not registered in files mode — ctrl-w must remain
  -- available for Neovim window navigation when fzf is in files mode).
  if mode ~= 'files' then
    actions[config.rg_word_key] = {
      fn = function(selected, opts)
        reopen(selected, opts, { word = not kwargs.word })
      end,
      desc = '-w',
      header = function()
        return kwargs.word and '-w' or nil
      end,
    }
  end

  -- Toggle: depth-1
  actions[config.rg_depth1_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { depth1 = not kwargs.depth1 })
    end,
    desc = '-d1',
    header = function()
      return kwargs.depth1 and '-d1' or nil
    end,
  }

  -- Toggle: case sensitivity (cycles smart → ignore → sensitive → smart)
  actions[config.rg_case_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { case_sensitive = (kwargs.case_sensitive + 1) % 3 })
    end,
    desc = 'case',
    header = function()
      if kwargs.case_sensitive == 2 then
        return '-i'
      elseif kwargs.case_sensitive == 0 then
        return '-s'
      end
    end,
  }

  -- Toggle: hidden files
  actions[config.rg_hidden_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { hidden = not kwargs.hidden })
    end,
    desc = '-.',
    header = function()
      return kwargs.hidden and '-.' or nil
    end,
  }

  -- Toggle: no-ignore (cycles 0 → -u → -uu → -uuu → 0)
  actions[config.rg_no_ignore_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { no_ignore = (kwargs.no_ignore + 1) % 4 })
    end,
    desc = '-u',
    header = function()
      return kwargs.no_ignore > 0 and string.rep('-u', kwargs.no_ignore) or nil
    end,
  }

  -- Toggle: fixed strings
  actions[config.rg_fixed_strings_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { fixed_strings = not kwargs.fixed_strings })
    end,
    desc = '-F',
    header = function()
      return kwargs.fixed_strings and '-F' or nil
    end,
  }

  -- Toggle: max-1
  actions[config.rg_max_1_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { max_1 = not kwargs.max_1 })
    end,
    desc = '-m1',
    header = function()
      return kwargs.max_1 and '-m1' or nil
    end,
  }

  -- Toggle: search compressed files
  actions[config.rg_search_zip_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { search_zip = not kwargs.search_zip })
    end,
    desc = '-z',
    header = function()
      return kwargs.search_zip and '-z' or nil
    end,
  }

  -- Toggle: treat binary as text
  actions[config.rg_text_key] = {
    fn = function(selected, opts)
      reopen(selected, opts, { text = not kwargs.text })
    end,
    desc = '-a',
    header = function()
      return kwargs.text and '-a' or nil
    end,
  }

  -- Sub-picker: file type filter (-t / -T)
  -- vim.schedule defers until after the current fzf session closes.
  actions[config.rg_type_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      vim.schedule(function()
        require('siefe.type_select').type_select('rg', fullscreen, dir, kwargs)
      end)
    end,
    desc = '-t',
    header = function()
      return kwargs.type ~= '' and kwargs.type or nil
    end,
  }

  actions[config.rg_type_not_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      vim.schedule(function()
        require('siefe.type_select').type_select('rg_not', fullscreen, dir, kwargs)
      end)
    end,
    desc = '-T',
  }

  -- Sub-picker: directory selection
  -- vim.schedule defers until after the current fzf session closes.
  actions[config.rg_dir_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      kwargs.fd_query = ''
      vim.schedule(function()
        local ds = require('siefe.dir_select')
        ds.dir_select(ds.ripgrep_dir_sink, fullscreen, dir, false, false, 'd', false, false, '', kwargs)
      end)
    end,
    desc = 'cd',
    header = function()
      return #kwargs.paths > 0 and table.concat(kwargs.paths, ' ') or nil
    end,
  }

  -- Toggle: limit search to open buffers
  actions[config.rg_buffers_key] = {
    fn = function(selected, opts)
      local bufs = vim.tbl_map(
        function(b)
          return vim.fn.fnamemodify(vim.fn.expand(vim.fn.bufname(b)), ':p:~:.')
        end,
        vim.tbl_filter(function(b)
          return vim.fn.buflisted(b) == 1
        end, vim.api.nvim_list_bufs())
      )
      reopen(selected, opts, { paths = vim.deep_equal(kwargs.paths, bufs) and {} or bufs })
    end,
    desc = 'buffers',
    header = function()
      local bufs = vim.tbl_map(
        function(b)
          return vim.fn.fnamemodify(vim.fn.expand(vim.fn.bufname(b)), ':p:~:.')
        end,
        vim.tbl_filter(function(b)
          return vim.fn.buflisted(b) == 1
        end, vim.api.nvim_list_bufs())
      )
      return vim.deep_equal(kwargs.paths, bufs) and 'buffers' or nil
    end,
  }

  -- Yank matched text to default register using standard file:line:col:text format.
  actions[config.rg_yank_key] = {
    fn = function(selected, _opts)
      local texts = {}
      for _, line in ipairs(get_entries(selected)) do
        local parsed = utils.parse_rg_line(line)
        if parsed then
          table.insert(texts, parsed.text)
        end
      end
      utils.yank_to_register(table.concat(texts, '\n'))
    end,
    desc = 'yank',
  }

  -- Toggle: recent-files history paths.
  -- May open a different picker (historyoldfiles) so can't use reopen(), but
  -- follows the same get_query() + vim.schedule pattern as all other actions.
  actions[config.rg_history_key] = {
    fn = function(selected, opts)
      kwargs.query = get_query(selected, opts)
      if kwargs.files then
        vim.schedule(function()
          require('siefe.history').historyoldfiles(fullscreen, kwargs)
        end)
      else
        local git_dir = utils.get_git_root()
        local recent = utils.recent_files(git_dir ~= '' and git_dir or nil)
        if vim.deep_equal(kwargs.paths, recent) then
          kwargs.paths = {}
          vim.schedule(function()
            M.ripgrepfzf(fullscreen, kwargs.orig_dir, kwargs)
          end)
        else
          kwargs.paths = recent
          vim.schedule(function()
            M.ripgrepfzf(fullscreen, git_dir ~= '' and git_dir or utils.bufdir(), kwargs)
          end)
        end
      end
    end,
    desc = 'history',
    header = function()
      local git_dir = utils.get_git_root()
      local recent = utils.recent_files(git_dir ~= '' and git_dir or nil)
      return vim.deep_equal(kwargs.paths, recent) and 'history' or nil
    end,
  }

  -- ── Launch ────────────────────────────────────────────────────────────────────

  local picker_opts = {
    query = kwargs.query,
    cwd = dir,
    winopts = utils.winopts(fullscreen),
    previewer = 'builtin', -- Neovim buffer preview with Treesitter/LSP
    fzf_opts = fzf_opts,
    keymap = rg_km,
    actions = actions,
  }

  if mode == 'rg' then
    -- fzf_live replaces the manual --disabled + change:reload(cmd) pattern:
    -- it internally adds --disabled (disables fzf fuzzy matching) and a
    -- change:reload bind so the rg command reruns on every keystroke with {q}
    -- expanded to the current query text.
    -- shellescape() wraps the query in single quotes, neutralising all shell
    -- metacharacters.  The '-- %s' placement after rg's end-of-options marker
    -- also ensures the query can never be mistaken for an rg flag.
    fzl.fzf_live(function(q)
      -- fzf-lua's RPC mechanism passes fzf field expansions as a table, so
      -- {q} arrives as {"query_text"} not as a plain string.  This mirrors
      -- what fzf-lua's own cmd2fnc() does: extract [1] from the table.
      local query = type(q) == 'table' and (q[1] or '') or (q or '')
      return string.format(cmd_fmt, vim.fn.shellescape(query))
    end, picker_opts)
  else
    -- Files mode or fzf-filter-over-rg-results: static source.
    local source = mode == 'files' and files_cmd or string.format(cmd_fmt, vim.fn.shellescape(kwargs.query))
    fzl.fzf_exec(source, picker_opts)
  end
end

-- Test-only exports (not part of the public API).
-- Used by test/test_rg.lua to exercise pure logic without launching fzf.
M._test = {
  build_rg_command = build_rg_command,
  build_files_command = build_files_command,
  build_prompt = build_prompt,
}

return M
