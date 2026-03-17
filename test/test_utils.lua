-- test/test_utils.lua – tests for lua/siefe/utils.lua (pure-Lua helpers)
-- Run with: nvim --headless -u NONE -l test/test_utils.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

local T = require('test.helpers')

-- Clear the siefe.config singleton so utils lazy-loads fresh defaults
package.loaded['siefe.config'] = nil

local utils = require('siefe.utils')

-- ── rg_delimiter ─────────────────────────────────────────────────────────────

T.group('rg_delimiter', function()
  T.eq(utils.rg_delimiter(), ':', 'returns colon')
  -- Idempotent
  T.eq(utils.rg_delimiter(), ':', 'idempotent')
end)

-- ── parse_rg_line ─────────────────────────────────────────────────────────────

T.group('parse_rg_line', function()
  -- Standard rg --column output: file:line:col:text
  local r = utils.parse_rg_line('src/foo.lua:10:5:hello world')
  T.eq(r.filename, 'src/foo.lua', 'filename')
  T.eq(r.lnum, 10, 'lnum')
  T.eq(r.col, 5, 'col')
  T.eq(r.text, 'hello world', 'text')

  -- Colons inside text are preserved
  local r2 = utils.parse_rg_line('a.lua:1:1:foo:bar:baz')
  T.eq(r2.filename, 'a.lua', 'filename with colons in text')
  T.eq(r2.text, 'foo:bar:baz', 'text with colons preserved')

  -- Non-matching line returns nil
  local r3 = utils.parse_rg_line('not a match')
  T.ok(r3 == nil, 'non-rg line returns nil')

  -- ANSI-escaped line (rg --color=always adds escape sequences in text)
  local ansi_line = 'file.lua:3:1:\27[31mhello\27[0m'
  local r4 = utils.parse_rg_line(ansi_line)
  T.eq(r4.filename, 'file.lua', 'filename with ANSI in text')
  T.eq(r4.lnum, 3, 'lnum with ANSI in text')
end)

-- ── detect_dups ───────────────────────────────────────────────────────────────

T.group('detect_dups', function()
  T.eq(utils.detect_dups({ 'a', 'b', 'c' }), '', 'no duplicates')
  T.eq(utils.detect_dups({ 'a', 'b', 'a' }), 'a', 'one duplicate')
  T.eq(utils.detect_dups({ 'x', 'x', 'y', 'y' }), 'x y', 'two duplicates')
  T.eq(utils.detect_dups({}), '', 'empty list')
end)

-- ── preview_window_size ───────────────────────────────────────────────────────

T.group('preview_window_size', function()
  -- Narrow window: preview should be hidden by default, other_size visible
  package.loaded['siefe.config'] = nil
  require('siefe.config').setup({ preview_hide_threshold = 200, default_preview_size = 40 })
  vim.o.columns = 100 -- below threshold

  local def, other = utils.preview_window_size()
  T.eq(def, '0%', 'narrow: default_size is 0% (hidden)')
  T.eq(other, '40%', 'narrow: other_size shows preview')

  -- Wide window: preview visible by default
  vim.o.columns = 300 -- above threshold
  def, other = utils.preview_window_size()
  T.eq(def, '40%', 'wide: default_size shows preview')
  T.eq(other, 'hidden', 'wide: other_size is hidden')

  -- Reset
  package.loaded['siefe.config'] = nil
end)

-- ── ANSI color helpers ────────────────────────────────────────────────────────

T.group('ANSI helpers', function()
  -- Helpers return non-empty strings wrapping the input
  local r = utils.red('hello')
  T.ok(r:find('hello', 1, true), 'red() contains original text')
  T.ok(r:find('\27%[', 1), 'red() contains ESC sequence')

  local b = utils.blue('world')
  T.ok(b:find('world', 1, true), 'blue() contains original text')

  -- reset sequence present
  T.ok(r:find('\27%[m'), 'red() ends with reset')
end)

-- ── data_path ─────────────────────────────────────────────────────────────────

T.group('data_path', function()
  local p = utils.data_path()
  T.ok(type(p) == 'string' and #p > 0, 'data_path returns a non-empty string')
  T.ok(vim.fn.isdirectory(p) == 1, 'data_path directory was created')
end)

-- ── bin_path ──────────────────────────────────────────────────────────────────

T.group('bin_path', function()
  local preview = utils.bin_path('preview')
  T.ok(preview:find('/bin/preview$'), 'bin_path returns correct path')
  T.ok(vim.fn.filereadable(preview) == 1, 'bin/preview exists')
end)

-- ── csi ───────────────────────────────────────────────────────────────────────

T.group('csi', function()
  -- Hex color, foreground: 38;2;r;g;b
  T.eq(utils.csi('#ff0080', true), '38;2;255;0;128', 'hex fg: 38;2;r;g;b')
  -- Hex color, background: 48;2;r;g;b
  T.eq(utils.csi('#ff0080', false), '48;2;255;0;128', 'hex bg: 48;2;r;g;b')
  -- Named/256-index color, fg: 38;5;N
  T.eq(utils.csi('42', true), '38;5;42', 'indexed fg: 38;5;N')
  -- Named/256-index color, bg: 48;5;N
  T.eq(utils.csi('42', false), '48;5;42', 'indexed bg: 48;5;N')
  -- Black (#000000)
  T.eq(utils.csi('#000000', true), '38;2;0;0;0', 'black hex')
  -- White (#ffffff)
  T.eq(utils.csi('#ffffff', true), '38;2;255;255;255', 'white hex')
end)

-- ── prettify_help ─────────────────────────────────────────────────────────────

T.group('prettify_help', function()
  local h = utils.prettify_help('ctrl-a')
  -- Key must be uppercased in the output
  T.ok(h:find('CTRL%-A', 1) ~= nil or h:find('CTRL-A', 1, true) ~= nil, 'key uppercased')
  -- Must contain an ANSI escape sequence
  T.ok(h:find('\27%[', 1) ~= nil, 'has ANSI escape')
  -- Must end with reset
  T.ok(h:find('\27%[m', 1) ~= nil, 'has ANSI reset')
end)

-- ── prettify_header ───────────────────────────────────────────────────────────

T.group('prettify_header', function()
  -- char == text:sub(1,1): no italic insertion, just key + ' ' + text
  local h1 = utils.prettify_header('ctrl-a', 'all hidden')
  T.ok(h1:find('all hidden', 1, true) ~= nil, 'text preserved when first char matches')
  -- The italic escape (ESC[3m) should NOT appear in this branch
  T.ok(h1:find('\27%[3m', 1) == nil, 'no italic when char matches first letter')

  -- char != text:sub(1,1): italic escape injected around matching char in body
  local h2 = utils.prettify_header('ctrl-h', 'show hidden')
  -- The text is rendered as 's' + italic('h') + 'ow hidden'; 'show' is split by
  -- ANSI escapes, but 'ow hidden' appears verbatim after the italic-h sequence.
  T.ok(h2:find('ow hidden', 1, true) ~= nil, 'text body preserved after italic char')

  -- Result always starts with the ANSI-styled key
  T.ok(h1:find('\27%[', 1) ~= nil, 'header starts with ANSI key')
end)

-- ── preview_help ──────────────────────────────────────────────────────────────

T.group('preview_help', function()
  -- Consecutive range: f1,f2,f3 → "f1-3" (algorithm: fSTART-END, no second f)
  local r1 = utils.preview_help({ 'f1', 'f2', 'f3' })
  T.ok(r1:find('f1', 1, true) ~= nil, 'consecutive: start present (f1)')
  -- Range end is the bare number (not f3): 'f1-3'
  T.ok(r1:find('-3', 1, true) ~= nil, 'consecutive: end number present (-3)')
  T.ok(r1:find('-', 1, true) ~= nil, 'consecutive: hyphen used')

  -- Non-consecutive: f1, f3 — both should appear, separated
  local r2 = utils.preview_help({ 'f1', 'f3' })
  T.ok(r2:find('f1', 1, true) ~= nil, 'non-consecutive: f1 present')
  T.ok(r2:find('f3', 1, true) ~= nil, 'non-consecutive: f3 present')

  -- Non-f key only: returned with leading ", "
  local r3 = utils.preview_help({ 'ctrl-p' })
  T.ok(r3:find('ctrl%-p', 1) ~= nil or r3:find('ctrl-p', 1, true) ~= nil, 'non-f key included')

  -- Mixed: f keys + non-f keys both appear
  local r4 = utils.preview_help({ 'f1', 'f2', 'ctrl-p' })
  T.ok(r4:find('f', 1, true) ~= nil, 'mixed: f keys present')
  T.ok(r4:find('ctrl', 1, true) ~= nil, 'mixed: non-f key present')

  -- Single f key: rendered as "fN-fN" (current algorithm repeats)
  local r5 = utils.preview_help({ 'f2' })
  T.ok(r5:find('f2', 1, true) ~= nil, 'single f key present')

  -- Empty list → empty string
  T.eq(utils.preview_help({}), '', 'empty list → empty string')
end)

-- ── make_binds ────────────────────────────────────────────────────────────────

T.group('make_binds', function()
  -- All binds go into keymap.fzf
  local km = utils.make_binds({ ['ctrl-a'] = 'abort', ['ctrl-b'] = 'up' })
  T.ok(type(km.fzf) == 'table', 'keymap.fzf is a table')
  T.eq(km.fzf['ctrl-a'], 'abort', 'bind in keymap.fzf')
  T.eq(km.fzf['ctrl-b'], 'up', 'second bind in keymap.fzf')

  -- Nil/no input → empty keymap (no error)
  local km2 = utils.make_binds()
  T.eq(km2.fzf, {}, 'nil input → empty keymap table')

  -- Complex fzf actions (change-preview, reload, etc.) also go in keymap.fzf
  local km3 = utils.make_binds({
    ['f1'] = 'change-preview(git show {1})',
    ['change'] = 'first+reload(rg {q})',
  })
  T.eq(km3.fzf['f1'], 'change-preview(git show {1})', 'change-preview bind stored')
  T.eq(km3.fzf['change'], 'first+reload(rg {q})', 'reload bind stored')

  -- Multiple simple binds all stored
  local km4 = utils.make_binds({ ['ctrl-x'] = 'clear-query', ['ctrl-y'] = 'yank' })
  T.eq(km4.fzf['ctrl-x'], 'clear-query', 'second simple bind stored')
  T.eq(km4.fzf['ctrl-y'], 'yank', 'third simple bind stored')
end)

-- ── log_path ──────────────────────────────────────────────────────────────────

T.group('log_path', function()
  local p = utils.log_path()
  T.ok(type(p) == 'string' and #p > 0, 'log_path returns non-empty string')
  T.ok(p:find('/siefe%.log$') ~= nil, 'log_path ends with /siefe.log')
  -- Prefix must be data_path()
  local dp = utils.data_path()
  T.eq(p:sub(1, #dp), dp, 'log_path starts with data_path()')
  -- Calling twice returns the same path (idempotent)
  T.eq(utils.log_path(), p, 'log_path idempotent')
end)

-- ── fzf_key_to_nvim ───────────────────────────────────────────────────────────

T.group('fzf_key_to_nvim: converts fzf notation to Neovim angle-bracket notation', function()
  -- ctrl-X → <C-x> (lowercase)
  T.eq(utils.fzf_key_to_nvim('ctrl-/'), '<C-/>', 'ctrl-/ → <C-/>')
  T.eq(utils.fzf_key_to_nvim('ctrl-a'), '<C-a>', 'ctrl-a → <C-a>')
  T.eq(utils.fzf_key_to_nvim('ctrl-z'), '<C-z>', 'ctrl-z → <C-z>')
  -- alt- → <A->
  T.eq(utils.fzf_key_to_nvim('alt-p'), '<A-p>', 'alt-p → <A-p>')
  T.eq(utils.fzf_key_to_nvim('alt-enter'), '<A-enter>', 'alt-enter → <A-enter>')
  -- shift- → <S->
  T.eq(utils.fzf_key_to_nvim('shift-tab'), '<S-tab>', 'shift-tab → <S-tab>')
  -- plain function keys (no modifier) just get wrapped
  T.eq(utils.fzf_key_to_nvim('f4'), '<f4>', 'f4 → <f4>')
  T.eq(utils.fzf_key_to_nvim('f7'), '<f7>', 'f7 → <f7>')
  -- input is lowercased
  T.eq(utils.fzf_key_to_nvim('CTRL-A'), '<C-a>', 'CTRL-A (upper) → <C-a>')
  -- partial-match safety: modifier name without trailing dash is not replaced
  T.ok(utils.fzf_key_to_nvim('alternative'):find('A-', 1, true) == nil, '"alt" not replaced when no trailing dash')
end)

T.group('fzf_key_to_nvim: default toggle_preview_key converts correctly', function()
  local cfg = require('siefe.config')
  local nvim_key = utils.fzf_key_to_nvim(cfg.toggle_preview_key)
  -- Default is 'ctrl-/' → must become '<C-/>'
  T.eq(nvim_key, '<C-/>', 'default toggle_preview_key converts to <C-/>')
  -- The raw fzf key must NOT equal the Neovim key
  T.ok(nvim_key ~= cfg.toggle_preview_key, 'fzf key and Neovim key are different strings')
end)

-- ── builtin_toggle_keys ───────────────────────────────────────────────────────

T.group('builtin_toggle_keys: ctrl-/ returns both <C-/> and <C-_> for terminal compat', function()
  local keys = utils.builtin_toggle_keys('ctrl-/')
  -- Must include <C-/> (CSI-u / kitty terminals)
  T.ok(vim.tbl_contains(keys, '<C-/>'), 'ctrl-/ includes <C-/> (CSI-u terminal key)')
  -- Must include <C-_> (standard terminals where Ctrl+/ sends 0x1f = <C-_>)
  T.ok(vim.tbl_contains(keys, '<C-_>'), 'ctrl-/ includes <C-_> (standard terminal 0x1f)')
  T.eq(#keys, 2, 'ctrl-/ returns exactly 2 keys')
end)

T.group('builtin_toggle_keys: non-slash ctrl keys return single key', function()
  local keys = utils.builtin_toggle_keys('ctrl-p')
  T.eq(#keys, 1, 'ctrl-p returns 1 key')
  T.eq(keys[1], '<C-p>', 'ctrl-p returns <C-p>')
end)

T.group('builtin_toggle_keys: alt key returns single key', function()
  local keys = utils.builtin_toggle_keys('alt-p')
  T.eq(#keys, 1, 'alt-p returns 1 key')
  T.eq(keys[1], '<A-p>', 'alt-p returns <A-p>')
end)

T.group('builtin_toggle_keys: function key returns single key', function()
  local keys = utils.builtin_toggle_keys('f4')
  T.eq(#keys, 1, 'f4 returns 1 key')
  T.eq(keys[1], '<f4>', 'f4 returns <f4>')
end)

T.finish()
