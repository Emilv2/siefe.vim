-- test/test_integration.lua – integration tests that call the real binaries
-- (diffgrep, pickaxe-diff).  Each group skips gracefully if the binary
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

T.finish()
