-- test/test_integration.lua – integration tests that call the real binaries
-- (rg2fzf, diffgrep, shada2fzf).  Each group skips gracefully if the binary
-- has not been built yet (run `make build` first).
--
-- Run with: nvim --headless -u NONE -l test/test_integration.lua

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h'))

local T = require('test.helpers')
local utils = require('siefe.utils')

-- Helper: run `bin` with `input` as stdin; return stdout string.
-- Uses vim.fn.system which passes the second argument as stdin.
local function run_bin(bin_path, input, extra_args)
  local cmd = { bin_path }
  for _, a in ipairs(extra_args or {}) do
    table.insert(cmd, a)
  end
  local out = vim.fn.system(cmd, input or '')
  return out
end

-- Binary-safe helper for programs whose stdin or stdout contains NUL or SOH
-- bytes.  vim.fn.system() converts such values to Blobs, making string methods
-- unavailable (E976).  This helper writes input to a temp file and reads
-- output via io.popen/io.open in binary mode, bypassing Vim's Blob handling.
local function run_bin_binary(bin_path, input)
  local tmpin = os.tmpname()
  local tmpout = os.tmpname()
  local f = assert(io.open(tmpin, 'wb'))
  f:write(input or '')
  f:close()
  os.execute(vim.fn.shellescape(bin_path) .. ' <' .. tmpin .. ' >' .. tmpout .. ' 2>/dev/null')
  local of = assert(io.open(tmpout, 'rb'))
  local out = of:read('*a')
  of:close()
  os.remove(tmpin)
  os.remove(tmpout)
  return out
end

-- ── rg2fzf binary ─────────────────────────────────────────────────────────────

T.group('rg2fzf binary', function()
  local bin = utils.bin_path('rg2fzf')
  if vim.fn.executable(bin) == 0 then
    io.stdout:write('  SKIP rg2fzf not built — run: make build\n')
    return
  end

  -- Basic NUL→SOH translation: filename\0rest\n → filename\x01rest\0
  local out1 = run_bin_binary(bin, 'file.lua\x001:5:hello world\n')
  T.ok(out1:find('\x01', 1, true), 'output contains SOH separator')
  T.ok(out1:find('file.lua', 1, true), 'output contains filename')
  T.ok(out1:find('hello world', 1, true), 'output contains match text')
  T.ok(out1:sub(-1) == '\0', 'record is NUL-terminated')

  -- Multiple records
  local out2 = run_bin_binary(bin, 'a.lua\x001:1:foo\nb.lua\x002:3:bar\n')
  T.eq(out2, 'a.lua\x011:1:foo\0b.lua\x012:3:bar\0', 'multiple records')

  -- Passthrough for lines without NUL (logger output etc.)
  local out3 = run_bin_binary(bin, 'log line without nul\n')
  T.ok(out3:find('log line', 1, true), 'passthrough line preserved')
  T.ok(out3:sub(-1) == '\0', 'passthrough line NUL-terminated')

  -- Colons in both filename and match text: SOH is the unambiguous separator
  local out4 = run_bin_binary(bin, 'server:8080/api.go\x001:1:http://host:9090/\n')
  T.ok(out4:find('server:8080/api.go\x01', 1, true), 'colon-in-filename preserved before SOH')

  -- Empty input → empty output
  local out5 = run_bin_binary(bin, '')
  T.eq(#out5, 0, 'empty input yields empty output')
end)

-- ── diffgrep binary ───────────────────────────────────────────────────────────

T.group('diffgrep binary', function()
  local bin = utils.bin_path('diffgrep')
  if vim.fn.executable(bin) == 0 then
    io.stdout:write('  SKIP diffgrep not built — run: make build\n')
    return
  end

  -- Diff with two hunks: one matches "needle", one doesn't.
  -- diffgrep should include only the matching hunk.
  local diff = table.concat({
    'diff --git a/foo.rs b/foo.rs',
    'index abc..def 100644',
    '--- a/foo.rs',
    '+++ b/foo.rs',
    '@@ -1,2 +1,3 @@ first_hunk',
    ' context line',
    '+added needle here',
    '+added another line',
    '@@ -10,1 +11,1 @@ second_hunk',
    '+unrelated addition',
  }, '\n') .. '\n'

  local out1 = run_bin(bin, diff, { 'needle' })
  T.ok(vim.v.shell_error == 0, 'exit 0 when match found')
  T.ok(out1:find('+added needle here', 1, true), 'matching hunk included')
  T.ok(not out1:find('+unrelated addition', 1, true), 'non-matching hunk excluded')

  -- No match: empty output, non-zero exit
  run_bin(bin, diff, { 'NOTFOUND' })
  T.ok(vim.v.shell_error ~= 0, 'exit non-zero when no match')

  -- Context lines never trigger a match
  local ctx_diff = table.concat({
    'diff --git a/foo.rs b/foo.rs',
    'index abc..def 100644',
    '--- a/foo.rs',
    '+++ b/foo.rs',
    '@@ -1,2 +1,2 @@',
    ' needle in context',
    '+unrelated',
  }, '\n') .. '\n'
  run_bin(bin, ctx_diff, { 'needle' })
  T.ok(vim.v.shell_error ~= 0, 'context-only match does not count')
end)

-- ── shada2fzf binary ──────────────────────────────────────────────────────────

T.group('shada2fzf binary', function()
  local bin = utils.bin_path('shada2fzf')
  if vim.fn.executable(bin) == 0 then
    io.stdout:write('  SKIP shada2fzf not built — run: make build\n')
    return
  end

  -- Craft a minimal shada file: one type-11 LocalMark `"` for a.lua
  -- at line=10, col=2, timestamp=100.
  --
  -- Binary layout (msgpack):
  --   0x0b          — type 11 (kSDItemLocalMark)
  --   0x64          — timestamp 100 (fixint)
  --   0x12          — data length 18 (fixint)
  --   0x84          — fixmap with 4 key-value pairs
  --   0xa1 'f'      — key "f" (fixstr len 1)
  --   0xa5 "a.lua"  — value "a.lua" (fixstr len 5)
  --   0xa1 'n'      — key "n" (fixstr len 1)
  --   0x22          — value 34 = '"' (fixint)
  --   0xa1 'l'      — key "l" (fixstr len 1)
  --   0x0a          — value 10 (fixint)
  --   0xa1 'c'      — key "c" (fixstr len 1)
  --   0x02          — value 2 (fixint)
  local shada_bytes = '\x0b' -- type 11
    .. '\x64' -- timestamp 100
    .. '\x12' -- data length 18
    .. '\x84' -- fixmap 4 pairs
    .. '\xa1f' -- key "f"
    .. '\xa5a.lua' -- value "a.lua"
    .. '\xa1n' -- key "n"
    .. '\x22' -- value 34
    .. '\xa1l' -- key "l"
    .. '\x0a' -- value 10
    .. '\xa1c' -- key "c"
    .. '\x02' -- value 2

  local tmp = '/tmp/siefe_test_integration.shada'
  local wf = io.open(tmp, 'wb')
  if not wf then
    io.stdout:write('  SKIP cannot write temp file ' .. tmp .. '\n')
    return
  end
  wf:write(shada_bytes)
  wf:close()

  local out = vim.fn.system({ bin, tmp })
  T.ok(vim.v.shell_error == 0, 'shada2fzf exits 0 for valid shada')
  T.ok(out:find('10//2//a.lua', 1, true), 'output is line//col//filename, got: ' .. vim.inspect(out))

  -- Empty shada → empty output, exit 0
  local empty_tmp = '/tmp/siefe_test_empty.shada'
  local ef = io.open(empty_tmp, 'wb')
  if ef then
    ef:write('')
    ef:close()
    local out2 = vim.fn.system({ bin, empty_tmp })
    T.ok(vim.v.shell_error == 0, 'exit 0 for empty shada')
    T.eq(#out2, 0, 'empty shada → empty output')
  end
end)

T.finish()
