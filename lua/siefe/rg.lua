-- lua/siefe/rg.lua
-- Ripgrep search – main picker
local M = {}

local config = require('siefe.config')
local utils = require('siefe.utils')

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function bool_to_flag(b, flag)
  return b and flag or ''
end

-- Parse an rg2fzf-format entry: `filename\x01line:col:text`
-- rg2fzf uses SOH (\x01) as the unambiguous filename/rest separator — it is
-- invalid in POSIX filenames, so a single find() locates the exact boundary
-- with zero fs_stat calls regardless of colons in the filename or match text.
-- The tail is always `\d+:\d+:text` — rg guarantees numeric line and col
-- fields with `--column --line-number`.
-- ANSI CSI sequences (from rg --color=always) are stripped before parsing.
local function parse_rg2fzf_entry(entry)
  -- Strip ANSI/VT100 CSI sequences: ESC [ <params> <final-byte>
  -- Final bytes are in the range 0x40-0x7E (@A-Z[\]^_`a-z{|}~).
  local clean = entry:gsub('\27%[[\32-\63]*[\64-\126]', '')
  local sep = clean:find('\1', 1, true) -- SOH = \x01
  if not sep then
    return nil
  end
  local filename = clean:sub(1, sep - 1)
  local rest = clean:sub(sep + 1) -- always "line:col:text" from rg2fzf
  local lnum, col, text = rest:match('^(%d+):(%d+):(.*)')
  if not lnum then
    return nil
  end
  return { filename = filename, lnum = tonumber(lnum) or 1, col = tonumber(col) or 1, text = text or '' }
end

-- Open multiple parsed entries in the given window command; populate qf/ll for
-- multi-select.  Used by file-open actions when rg2fzf is active (avoids the
-- fs_stat loop inside fzl_actions / entry_to_file).
local function open_rg2fzf_entries(entries, win_cmd, use_loclist)
  if not entries or #entries == 0 then
    return
  end
  local parsed_list = {}
  for _, e in ipairs(entries) do
    local p = parse_rg2fzf_entry(e)
    if p then
      table.insert(parsed_list, p)
    end
  end
  if #parsed_list == 0 then
    return
  end
  utils.open_file(win_cmd, parsed_list[1].filename, parsed_list[1].lnum, parsed_list[1].col)
  if #parsed_list > 1 then
    local qf = vim.tbl_map(function(p)
      return { filename = p.filename, lnum = p.lnum, col = p.col, text = p.text or '' }
    end, parsed_list)
    if use_loclist then
      utils.fill_loc(qf)
    else
      utils.fill_quickfix(qf)
    end
  end
end

-- Build the rg command format string.
-- Returns a Lua format string where '%s' is the query placeholder.
-- Callers use string.format() to substitute either:
--   '{q}'  — fzf's live-query marker (for fzf_live mode), or
--   a shellescape'd query string (for fzf_exec static mode).
-- When rg2fzf_path is provided, rg is called with --null and the output is
-- piped through rg2fzf, which converts each `file\0line:col:text\n` record to
-- the NUL-terminated `file:line:col:text\0` format required by fzf --read0.
local function build_rg_command(kwargs, rg2fzf_path)
  local logger = utils.bin_path('logger') .. ' ' .. vim.fn.shellescape(utils.log_path()) .. ' '
  local null_flag = rg2fzf_path and '--null ' or ''
  local rg2fzf_pipe = rg2fzf_path and (' | ' .. vim.fn.shellescape(rg2fzf_path)) or ''
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
    .. null_flag
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
    .. rg2fzf_pipe
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

  -- Detect rg2fzf (optional Rust binary that converts rg --null output to
  -- NUL-terminated records for fzf --read0).  If absent, fall back to plain
  -- rg output without --null; search mode then works without --read0.
  local rg2fzf = utils.bin_path('rg2fzf')
  rg2fzf = vim.fn.executable(rg2fzf) == 1 and rg2fzf or nil

  local default_size, other_size = utils.preview_window_size()

  -- Determine mode
  local mode = kwargs.files and 'files' or (kwargs.fzf and 'fzf' or 'rg')

  -- Commands
  local cmd_fmt = build_rg_command(kwargs, rg2fzf)
  local files_cmd = build_files_command(kwargs)

  -- Header
  local name_info = vim.fn.bufname() == '' and '[No Name]'
    or vim.fn.fnameescape(vim.fn.fnamemodify(vim.fn.bufname(), ':t'))
  local paths_info = #kwargs.paths == 0 and '' or ('\npaths: ' .. table.concat(kwargs.paths, ' '))

  -- Active flags (shown only when non-default)
  local flags = ''
  if kwargs.word then
    flags = flags .. ' -w'
  end
  if kwargs.depth1 then
    flags = flags .. ' -d1'
  end
  if kwargs.hidden then
    flags = flags .. ' -.'
  end
  if kwargs.fixed_strings then
    flags = flags .. ' -F'
  end
  if kwargs.max_1 then
    flags = flags .. ' -m1'
  end
  if kwargs.search_zip then
    flags = flags .. ' -z'
  end
  if kwargs.text then
    flags = flags .. ' -a'
  end
  if kwargs.no_ignore == 1 then
    flags = flags .. ' -u'
  elseif kwargs.no_ignore == 2 then
    flags = flags .. ' -uu'
  elseif kwargs.no_ignore == 3 then
    flags = flags .. ' -uuu'
  end
  if kwargs.case_sensitive == 2 then
    flags = flags .. ' -i'
  elseif kwargs.case_sensitive == 0 then
    flags = flags .. ' -s'
  end
  if kwargs.type ~= '' then
    flags = flags .. ' ' .. kwargs.type
  end

  local header = utils.blue(name_info) .. ' ' .. utils.magenta(mode) .. flags .. paths_info

  local rg_km, _rg_cli = utils.make_binds({
    [config.up_key] = 'up',
    [config.down_key] = 'down',
    [config.next_history_key] = 'next-history',
    [config.previous_history_key] = 'previous-history',
    [config.toggle_up_key] = 'toggle+up',
    [config.toggle_down_key] = 'toggle+down',
    [config.toggle_preview_key] = 'change-preview-window(' .. other_size .. '|' .. config.second_preview_size .. '%|)',
  }, {})

  local fzf_opts = {
    ['--history'] = utils.data_path() .. '/rg_fzf_history',
    ['--ansi'] = '',
    ['--multi'] = '',
    ['--print-query'] = '',
    -- Use NUL as the output record separator.  fzf-lua detects --print0 in
    -- fzf.lua (get_EOL("print0")) and splits fzf's output on NUL instead of
    -- newline, so multiline match text or special characters in entries are
    -- never confused with record boundaries.
    ['--print0'] = '',
    -- No --delimiter is set here.  fzf's field-index syntax ({N}) only works
    -- reliably with a delimiter that never appears in filenames; ':' fails when
    -- filenames contain colons.  The builtin previewer calls
    -- path.entry_to_file() on the Lua side, which uses uv.fs_stat() to
    -- progressively extend the filename candidate across each ':' boundary
    -- until an existing file is found — handling colons in both filenames and
    -- match text without any fzf-side field index.
    ['--header'] = header,
    ['--prompt'] = build_prompt(kwargs, mode),
    -- For files mode, '+{}' tells fzf to scroll the preview to the selected
    -- file's position (a no-op for file lists, but harmless).  For search/fzf
    -- modes the builtin previewer scrolls to the matched line via
    -- entry_to_file() — no fzf-side '+{N}' scroll hint is needed or reliable.
    ['--preview-window'] = (mode == 'files') and ('+{},' .. default_size) or default_size,
    -- --read0 tells fzf to split its input stream on NUL bytes (rather than
    -- newlines), which handles paths and match text containing any special
    -- characters including newlines.
    --
    -- Files mode:  rg --null --files emits NUL-terminated paths directly.
    -- Search/fzf:  rg --null | rg2fzf converts each `file\0rest\n` record to
    --              `file:rest\0`, making records NUL-terminated while keeping
    --              the standard `file:line:col:text` format that fzf-lua's
    --              path.entry_to_file() parses.
    -- Fallback:    when rg2fzf is absent, search/fzf mode works without --read0
    --              (rare edge cases like colons in filenames are handled by
    --              fzf-lua's smart parser).
    ['--read0'] = (mode == 'files' or rg2fzf ~= nil) and '' or nil,
  }

  -- ── Helpers for actions ──────────────────────────────────────────────────────

  -- With --print-query, selected[1] is always the current fzf query and
  -- selected[2:] are the actual rg / file entries.
  local function get_query(selected)
    return selected and selected[1] or kwargs.query or ''
  end

  local function get_entries(selected)
    return selected and #selected > 1 and vim.list_slice(selected, 2) or {}
  end

  -- Reopen picker after a toggle, preserving the current query.
  local function reopen(selected, changes)
    kwargs.query = get_query(selected)
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
  -- When rg2fzf is active entries are `filename\x01line:col:text` — parsed
  -- without fs_stat.  Fallback entries are `file:line:col:text` — parsed via
  -- fzl_actions which calls entry_to_file() / fs_stat internally.
  actions['default'] = {
    fn = function(selected, opts)
      local entries = get_entries(selected)
      if #entries == 0 then
        return
      end
      if rg2fzf then
        open_rg2fzf_entries(entries, 'edit', config.rg_loclist)
      else
        fzl_actions.file_edit({ entries[1] }, opts)
        if #entries > 1 then
          if config.rg_loclist then
            fzl_actions.file_sel_to_ll(entries, opts)
          else
            fzl_actions.file_sel_to_qf(entries, opts)
          end
        end
      end
    end,
    header = 'open',
  }

  -- Window open actions.
  -- rg2fzf path: parse \x01 format directly (no fs_stat).
  -- Fallback path: native fzl_actions (uses entry_to_file / fs_stat).
  local function make_open_action(win_cmd, desc)
    return {
      fn = function(selected, opts)
        local entries = get_entries(selected)
        if #entries == 0 then
          return
        end
        if rg2fzf then
          open_rg2fzf_entries(entries, win_cmd, false)
        else
          if win_cmd == 'split' then
            fzl_actions.file_split(entries, opts)
          elseif win_cmd == 'vsplit' then
            fzl_actions.file_vsplit(entries, opts)
          elseif win_cmd == 'tabedit' then
            fzl_actions.file_tabedit(entries, opts)
          end
        end
      end,
      header = desc,
    }
  end

  actions[config.split_key] = make_open_action('split', 'split')
  actions[config.vsplit_key] = make_open_action('vsplit', 'vsplit')
  actions[config.tab_key] = make_open_action('tabedit', 'tab')
  actions[config.vdiffsplit_key] = {
    fn = function(selected, _opts)
      -- fzl_actions has no diffsplit equivalent; keep custom parsing.
      local entries = get_entries(selected)
      if #entries == 0 then
        return
      end
      if rg2fzf then
        local parsed = parse_rg2fzf_entry(entries[1])
        if parsed then
          utils.open_file('vert diffsplit', parsed.filename, parsed.lnum, parsed.col)
        end
      else
        local parsed = utils.parse_rg_line(entries[1])
        if parsed then
          utils.open_file('vert diffsplit', parsed.filename, parsed.lnum, parsed.col)
        end
      end
    end,
    header = 'diff',
  }

  -- Toggle: fzf/rg mode
  actions[config.rg_toggle_fzf_key] = {
    fn = function(selected, _opts)
      if kwargs.files then
        reopen(selected, { files = false })
      else
        reopen(selected, { fzf = not kwargs.fzf })
      end
    end,
    header = 'mode',
  }

  -- Toggle: rg/fzf combined filter
  actions[config.rg_rgfzf_key] = {
    fn = function(selected, _opts)
      reopen(selected, { fzf = not kwargs.fzf })
    end,
    header = 'rg/fzf',
  }

  -- Toggle: files mode
  actions[config.rg_files_key] = {
    fn = function(selected, _opts)
      reopen(selected, { files = not kwargs.files })
    end,
    header = 'files',
  }

  -- Toggle: word boundary (not registered in files mode — ctrl-w must remain
  -- available for Neovim window navigation when fzf is in files mode).
  if mode ~= 'files' then
    actions[config.rg_word_key] = {
      fn = function(selected, _opts)
        reopen(selected, { word = not kwargs.word })
      end,
      header = '-w',
    }
  end

  -- Toggle: depth-1
  actions[config.rg_depth1_key] = {
    fn = function(selected, _opts)
      reopen(selected, { depth1 = not kwargs.depth1 })
    end,
    header = '-d1',
  }

  -- Toggle: case sensitivity (cycles smart → ignore → sensitive → smart)
  actions[config.rg_case_key] = {
    fn = function(selected, _opts)
      reopen(selected, { case_sensitive = (kwargs.case_sensitive + 1) % 3 })
    end,
    header = 'case',
  }

  -- Toggle: hidden files
  actions[config.rg_hidden_key] = {
    fn = function(selected, _opts)
      reopen(selected, { hidden = not kwargs.hidden })
    end,
    header = '-.',
  }

  -- Toggle: no-ignore (cycles 0 → -u → -uu → -uuu → 0)
  actions[config.rg_no_ignore_key] = {
    fn = function(selected, _opts)
      reopen(selected, { no_ignore = (kwargs.no_ignore + 1) % 4 })
    end,
    header = '-u',
  }

  -- Toggle: fixed strings
  actions[config.rg_fixed_strings_key] = {
    fn = function(selected, _opts)
      reopen(selected, { fixed_strings = not kwargs.fixed_strings })
    end,
    header = '-F',
  }

  -- Toggle: max-1
  actions[config.rg_max_1_key] = {
    fn = function(selected, _opts)
      reopen(selected, { max_1 = not kwargs.max_1 })
    end,
    header = '-m1',
  }

  -- Toggle: search compressed files
  actions[config.rg_search_zip_key] = {
    fn = function(selected, _opts)
      reopen(selected, { search_zip = not kwargs.search_zip })
    end,
    header = '-z',
  }

  -- Toggle: treat binary as text
  actions[config.rg_text_key] = {
    fn = function(selected, _opts)
      reopen(selected, { text = not kwargs.text })
    end,
    header = '-a',
  }

  -- Sub-picker: file type filter (-t / -T)
  -- vim.schedule defers until after the current fzf session closes.
  actions[config.rg_type_key] = {
    fn = function(selected, _opts)
      kwargs.query = get_query(selected)
      vim.schedule(function()
        require('siefe.type_select').type_select('rg', fullscreen, dir, kwargs)
      end)
    end,
    header = '-t',
  }

  actions[config.rg_type_not_key] = {
    fn = function(selected, _opts)
      kwargs.query = get_query(selected)
      vim.schedule(function()
        require('siefe.type_select').type_select('rg_not', fullscreen, dir, kwargs)
      end)
    end,
    header = '-T',
  }

  -- Sub-picker: directory selection
  -- vim.schedule defers until after the current fzf session closes.
  actions[config.rg_dir_key] = {
    fn = function(selected, _opts)
      kwargs.query = get_query(selected)
      kwargs.fd_query = ''
      vim.schedule(function()
        local ds = require('siefe.dir_select')
        ds.dir_select(ds.ripgrep_dir_sink, fullscreen, dir, false, false, 'd', false, false, '', kwargs)
      end)
    end,
    header = 'cd',
  }

  -- Toggle: limit search to open buffers
  actions[config.rg_buffers_key] = {
    fn = function(selected, _opts)
      local bufs = vim.tbl_map(
        function(b)
          return vim.fn.fnamemodify(vim.fn.expand(vim.fn.bufname(b)), ':p:~:.')
        end,
        vim.tbl_filter(function(b)
          return vim.fn.buflisted(b) == 1
        end, vim.api.nvim_list_bufs())
      )
      reopen(selected, { paths = vim.deep_equal(kwargs.paths, bufs) and {} or bufs })
    end,
    header = 'buffers',
  }

  -- Yank matched text to default register.
  -- rg2fzf path: parse \x01 format directly.
  -- Fallback path: parse standard file:line:col:text format.
  actions[config.rg_yank_key] = {
    fn = function(selected, _opts)
      local texts = {}
      for _, line in ipairs(get_entries(selected)) do
        local parsed = rg2fzf and parse_rg2fzf_entry(line) or utils.parse_rg_line(line)
        if parsed then
          table.insert(texts, parsed.text)
        end
      end
      utils.yank_to_register(table.concat(texts, '\n'))
    end,
    header = 'yank',
  }

  -- Toggle: recent-files history paths.
  -- May open a different picker (historyoldfiles) so can't use reopen(), but
  -- follows the same get_query() + vim.schedule pattern as all other actions.
  actions[config.rg_history_key] = {
    fn = function(selected, _opts)
      kwargs.query = get_query(selected)
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
    header = 'history',
  }

  -- ── Launch ────────────────────────────────────────────────────────────────────

  local picker_opts = {
    query = kwargs.query,
    cwd = dir,
    winopts = utils.winopts(fullscreen),
    previewer = 'builtin', -- Neovim buffer preview with Treesitter/LSP
    fzf_opts = fzf_opts,
    keymap = rg_km,
    _fzf_cli_args = _rg_cli,
    actions = actions,
  }

  if mode == 'rg' then
    -- fzf_live replaces the manual --disabled + change:reload(cmd) pattern:
    -- it internally adds --disabled (disables fzf fuzzy matching) and a
    -- change:reload bind so the rg command reruns on every keystroke with {q}
    -- expanded to the current query text.
    fzl.fzf_live(string.format(cmd_fmt, '{q}'), picker_opts)
  else
    -- Files mode or fzf-filter-over-rg-results: static source.
    local source = mode == 'files' and files_cmd or string.format(cmd_fmt, vim.fn.shellescape(kwargs.query))
    fzl.fzf_exec(source, picker_opts)
  end
end

-- Test-only exports (not part of the public API).
-- Used by test/test_rg.lua to exercise pure logic without launching fzf.
M._test = {
  parse_rg2fzf_entry = parse_rg2fzf_entry,
  build_rg_command = build_rg_command,
  build_files_command = build_files_command,
  build_prompt = build_prompt,
}

return M
