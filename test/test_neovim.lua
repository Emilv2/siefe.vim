-- test/test_neovim.lua – Real Neovim integration tests.
-- Unlike the pure-Lua test files, these tests exercise siefe functions that
-- require actual Neovim state: buffers, cursor positions, registers, quickfix.
-- Run with: nvim --headless -u NONE -l test/test_neovim.lua
--
-- Inspired by nvim-autopairs test_utils.lua:
--   https://github.com/windwp/nvim-autopairs/blob/master/tests/test_utils.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

package.loaded['siefe.config'] = nil

local T = require('test.helpers')
local utils = require('siefe.utils')
local history_m = require('siefe.history')

-- ── Test-file helpers ─────────────────────────────────────────────────────────

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, 'p')

--- Create a temp file with the given lines; return its absolute path.
local function make_file(name, lines)
  local path = tmpdir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

--- Reset current window to a fresh unnamed scratch buffer.
local function reset_buf()
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
end

-- ── open_file ─────────────────────────────────────────────────────────────────

T.group('open_file: opens file in current buffer', function()
  local path = make_file('open_basic.txt', { 'line one', 'line two', 'line three', 'line four', 'line five' })
  utils.open_file('edit', path, 0, 0)
  T.eq(vim.fn.expand('%:p'), path, 'buffer is the test file')
  T.eq(vim.api.nvim_win_get_cursor(0)[1], 1, 'cursor at line 1 when lnum=0')
end)

T.group('open_file: jumps to requested line and column', function()
  local path = make_file('open_jump.txt', { 'line one', 'line two', 'line three', 'line four', 'line five' })
  utils.open_file('edit', path, 3, 4)
  T.eq(vim.fn.expand('%:p'), path, 'buffer is the test file')
  local cur = vim.api.nvim_win_get_cursor(0)
  -- nvim_win_get_cursor returns {row (1-indexed), col (0-indexed)}
  T.eq(cur[1], 3, 'cursor at line 3')
  T.eq(cur[2] + 1, 4, 'cursor at col 4 (1-indexed)')
end)

T.group('open_file: split opens a new window', function()
  local path = make_file('open_split.txt', { 'hello split' })
  reset_buf()
  local win_count_before = #vim.api.nvim_list_wins()
  utils.open_file('split', path, 0, 0)
  T.ok(#vim.api.nvim_list_wins() > win_count_before, 'a new window was created')
  T.eq(vim.fn.expand('%:p'), path, 'new window shows the file')
  vim.cmd('only!') -- close extra windows
end)

-- ── yank_to_register ──────────────────────────────────────────────────────────

T.group('yank_to_register: unnamed register', function()
  utils.yank_to_register('hello siefe')
  T.eq(vim.fn.getreg('"'), 'hello siefe', 'unnamed register has the yanked text')
end)

T.group('yank_to_register: multiline text', function()
  utils.yank_to_register('line1\nline2\nline3')
  T.eq(vim.fn.getreg('"'), 'line1\nline2\nline3', 'multiline text preserved')
end)

-- ── fill_quickfix ─────────────────────────────────────────────────────────────

T.group('fill_quickfix: single entry is ignored (< 2 guard)', function()
  vim.fn.setqflist({}) -- clear any prior entries
  local path = make_file('qf_single.txt', { 'aaa' })
  utils.fill_quickfix({ { filename = path, lnum = 1, col = 1, text = 'aaa' } })
  T.eq(#vim.fn.getqflist(), 0, 'qflist unchanged for a single entry')
end)

T.group('fill_quickfix: multi entries populate qflist', function()
  vim.fn.setqflist({}) -- clear
  local path = make_file('qf_multi.txt', { 'aaa', 'bbb', 'ccc' })
  utils.fill_quickfix({
    { filename = path, lnum = 1, col = 1, text = 'aaa' },
    { filename = path, lnum = 2, col = 1, text = 'bbb' },
    { filename = path, lnum = 3, col = 1, text = 'ccc' },
  })
  local qf = vim.fn.getqflist()
  T.eq(#qf, 3, 'qflist has 3 entries')
  T.eq(qf[1].lnum, 1, 'entry 1 lnum')
  T.eq(qf[2].lnum, 2, 'entry 2 lnum')
  T.eq(qf[3].lnum, 3, 'entry 3 lnum')
end)

-- ── visual_selection via feedkeys ─────────────────────────────────────────────
-- Uses nvim-autopairs pattern: feed with 'x' mode (synchronous),
-- then read back the visual marks '< and '> after <Esc>.

T.group('visual_selection: charwise forward select 5 chars', function()
  reset_buf()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'line two' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  -- Enter visual, move right 4 times (selects h-e-l-l-o), leave visual
  T.feed('v4l<Esc>')
  local sel = utils.visual_selection()
  T.eq(sel, 'hello', 'selects first 5 chars')
end)

T.group('visual_selection: single char', function()
  reset_buf()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'xyz' })
  vim.api.nvim_win_set_cursor(0, { 1, 1 }) -- on 'y'
  T.feed('v<Esc>') -- select just 'y'
  local sel = utils.visual_selection()
  T.eq(sel, 'y', 'single char selection')
end)

T.group('visual_selection: multiline selection contains newline', function()
  reset_buf()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'foo bar' })
  vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- on 'w' of 'world'
  -- Select to end of line 1, then one line down, to start
  T.feed('vjO<Esc>') -- 'v' visual, 'j' down, 'O' go to other corner (start), '<Esc>'
  local sel = utils.visual_selection()
  T.ok(type(sel) == 'string', 'returns a string')
  T.ok(#sel > 0, 'selection is non-empty')
end)

-- ── buflisted_sorted: MRU ordering ───────────────────────────────────────────

T.group('buflisted_sorted: manual tracker gives MRU order', function()
  local path1 = make_file('mru1.txt', { 'file1' })
  local path2 = make_file('mru2.txt', { 'file2' })
  local path3 = make_file('mru3.txt', { 'file3' })
  vim.cmd('edit ' .. vim.fn.fnameescape(path1))
  local buf1 = vim.api.nvim_get_current_buf()
  vim.cmd('edit ' .. vim.fn.fnameescape(path2))
  local buf2 = vim.api.nvim_get_current_buf()
  vim.cmd('edit ' .. vim.fn.fnameescape(path3))
  local buf3 = vim.api.nvim_get_current_buf()

  -- Simulate the BufEnter tracker: buf2 is most recently accessed
  local siefe = require('siefe')
  siefe.buffers_tracker[buf1] = 100
  siefe.buffers_tracker[buf3] = 200
  siefe.buffers_tracker[buf2] = 300 -- most recent

  local sorted = utils.buflisted_sorted()
  -- Find positions of each buffer in sorted result
  local idx = {}
  for i, b in ipairs(sorted) do
    if b == buf1 then
      idx[1] = i
    end
    if b == buf2 then
      idx[2] = i
    end
    if b == buf3 then
      idx[3] = i
    end
  end
  T.ok(idx[1] and idx[2] and idx[3], 'all 3 buffers in sorted list')
  T.ok(idx[2] < idx[3], 'buf2 (timestamp=300) before buf3 (timestamp=200)')
  T.ok(idx[3] < idx[1], 'buf3 (timestamp=200) before buf1 (timestamp=100)')
end)

T.group('buflisted_sorted: terminal buffers sort last', function()
  local path = make_file('regular2.txt', { 'hello' })
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local file_buf = vim.api.nvim_get_current_buf()

  -- Open a real terminal buffer (:term ls); skip if terminal is unavailable
  -- (e.g. no PTY in some CI environments).
  local term_ok = pcall(vim.cmd, 'term ls')
  if not term_ok then
    T.ok(true, 'skip: terminal unavailable in this environment')
    return
  end
  local term_buf = vim.api.nvim_get_current_buf()
  T.ok(vim.bo[term_buf].buftype == 'terminal', 'term buffer has buftype=terminal')

  -- Give term_buf a newer timestamp so without the terminal sort it would come first
  local siefe = require('siefe')
  siefe.buffers_tracker[file_buf] = 100
  siefe.buffers_tracker[term_buf] = 999 -- newest, but terminal → should be last

  local sorted = utils.buflisted_sorted()
  local file_idx, term_idx
  for i, b in ipairs(sorted) do
    if b == file_buf then
      file_idx = i
    end
    if b == term_buf then
      term_idx = i
    end
  end
  T.ok(file_idx ~= nil, 'regular buffer in list')
  T.ok(term_idx ~= nil, 'terminal buffer in list')
  T.ok(file_idx < term_idx, 'regular file buffer appears before terminal buffer')
  vim.cmd('only!') -- close terminal window
end)

-- ── recent_files_info: current buffer in list ─────────────────────────────────

T.group('recent_files_info: current buffer appears in the list', function()
  local path = make_file('recent_test.txt', { 'hello' })
  utils.open_file('edit', path, 0, 0)
  local items = utils.recent_files_info()
  local found = false
  local short = vim.fn.fnamemodify(path, ':~:.')
  for _, item in ipairs(items) do
    if item:find(short, 1, true) then
      found = true
      break
    end
  end
  T.ok(found, 'current buffer path appears in recent_files_info()')
end)

T.group('recent_files_info: records current line number', function()
  local path = make_file('lnum_test.txt', { 'a', 'b', 'c', 'd', 'e' })
  utils.open_file('edit', path, 4, 1)
  local items = utils.recent_files_info()
  -- First item is always the current buffer; it should start with '4//'
  T.ok(#items >= 1, 'at least one item returned')
  T.ok(items[1]:sub(1, 2) == '4/', 'first entry starts with current lnum (4)')
end)

-- ── history: make_history_entry round-trip + open at correct position ─────────

T.group('history: make_history_entry produces parseable entry', function()
  local path = make_file('hist_test.txt', { 'alpha', 'beta', 'gamma', 'delta', 'epsilon' })
  local entry = history_m._test.make_history_entry(3, 2, path)

  -- Verify entry format: path:lnum:col\x01display
  T.ok(entry:find(path, 1, true) ~= nil, 'entry contains the file path')
  T.ok(entry:find(':3:2\x01', 1, true) ~= nil, 'entry contains :lnum:col\\x01 separator')
end)

T.group('history: parse_entry recovers lnum, col, fname', function()
  local path = make_file('hist_parse.txt', { 'alpha', 'beta', 'gamma', 'delta', 'epsilon' })
  local entry = history_m._test.make_history_entry(5, 3, path)
  local lnum, col, fname = history_m._test.parse_entry(entry)
  T.eq(fname, path, 'parse_entry: correct filename')
  T.eq(lnum, 5, 'parse_entry: correct lnum')
  T.eq(col, 3, 'parse_entry: correct col')
end)

T.group('history: open_file lands cursor at saved position', function()
  local path = make_file('hist_open.txt', { 'alpha', 'beta', 'gamma', 'delta', 'epsilon' })
  local lnum, col, fname = history_m._test.parse_entry(history_m._test.make_history_entry(4, 2, path))
  utils.open_file('edit', fname, lnum, col)
  local cur = vim.api.nvim_win_get_cursor(0)
  T.eq(cur[1], 4, 'cursor lands on saved line')
  T.eq(cur[2] + 1, 2, 'cursor lands on saved column (1-indexed)')
end)

-- ── parse_rg_line in real Neovim ──────────────────────────────────────────────

T.group('parse_rg_line: standard rg output', function()
  local r = utils.parse_rg_line('src/foo.lua:10:5:hello world')
  T.ok(r ~= nil, 'parses successfully')
  T.eq(r.filename, 'src/foo.lua', 'filename')
  T.eq(r.lnum, 10, 'lnum')
  T.eq(r.col, 5, 'col')
  T.eq(r.text, 'hello world', 'text')
end)

T.group('parse_rg_line: colon in text preserved', function()
  local r = utils.parse_rg_line('file.lua:3:1:key: value: extra')
  T.ok(r ~= nil, 'parses successfully')
  T.eq(r.filename, 'file.lua', 'filename')
  T.eq(r.lnum, 3, 'lnum')
  T.eq(r.text, 'key: value: extra', 'text with colons preserved')
end)

T.group('parse_rg_line: non-match returns nil', function()
  local r = utils.parse_rg_line('not a match')
  T.eq(r, nil, 'non-matching line returns nil')
end)

-- ── buffers format_buffer display names ───────────────────────────────────────

T.group('format_buffer: inside git root shows relative path', function()
  -- Create a temp file inside a fake git root
  local fake_root = tmpdir .. '/fakegit'
  local subdir = fake_root .. '/src'
  vim.fn.mkdir(subdir, 'p')
  local fpath = subdir .. '/inside.lua'
  vim.fn.writefile({ 'hello' }, fpath)
  -- Open it in a buffer
  vim.cmd('edit ' .. vim.fn.fnameescape(fpath))
  local b = vim.fn.bufnr('')
  local buffers_m = require('siefe.buffers')
  local entry = buffers_m._test.format_buffer(b, fake_root)
  -- The display part is after the first \x01
  local display = entry:match('\x01(.*)')
  -- Should contain the relative path from git root (src/inside.lua), NOT fake_root prefix
  T.ok(display:find('src/inside%.lua', 1, false) ~= nil, 'display contains relative path src/inside.lua')
  -- Should NOT contain the absolute fake_root prefix in the display part
  T.ok(display:find(fake_root, 1, true) == nil, 'display does not contain full absolute fake_root prefix')
  -- The metadata field (before \x01) must still contain the absolute path for the previewer
  local meta = entry:match('^(.-)\x01')
  T.ok(meta:find(fpath, 1, true) ~= nil, 'metadata field contains absolute path for previewer')
  vim.cmd('bdelete! ' .. b)
end)

T.group('format_buffer: outside git root shows absolute path', function()
  -- Create a temp file outside the fake git root (a sibling directory)
  local fake_root = tmpdir .. '/fakegit2'
  vim.fn.mkdir(fake_root, 'p')
  local outside = tmpdir .. '/outside_repo'
  vim.fn.mkdir(outside, 'p')
  local fpath = outside .. '/outside.lua'
  vim.fn.writefile({ 'world' }, fpath)
  vim.cmd('edit ' .. vim.fn.fnameescape(fpath))
  local b = vim.fn.bufnr('')
  local buffers_m = require('siefe.buffers')
  local entry = buffers_m._test.format_buffer(b, fake_root)
  local display = entry:match('\x01(.*)')
  -- Display should contain the full absolute path (not a truncated/garbled version)
  T.ok(display:find(fpath, 1, true) ~= nil, 'display contains absolute path for outside-root buffer')
  -- Should NOT show the √ git-relative prefix
  T.ok(display:find('√', 1, true) == nil, 'display does not show √ prefix for outside-root buffer')
  vim.cmd('bdelete! ' .. b)
end)

T.group('format_buffer: no git root shows absolute path', function()
  local fpath = tmpdir .. '/nogit.lua'
  vim.fn.writefile({ 'standalone' }, fpath)
  vim.cmd('edit ' .. vim.fn.fnameescape(fpath))
  local b = vim.fn.bufnr('')
  local buffers_m = require('siefe.buffers')
  -- Pass empty git_dir (no git context): falls through to name (:p:~:. form), no √
  local entry = buffers_m._test.format_buffer(b, '')
  local display = entry:match('\x01(.*)')
  T.ok(display:find('√', 1, true) == nil, 'display does not show √ without git root')
  vim.cmd('bdelete! ' .. b)
end)

-- ── Cleanup ───────────────────────────────────────────────────────────────────

vim.fn.delete(tmpdir, 'rf')

T.finish()
