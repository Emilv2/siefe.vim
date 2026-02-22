-- test/helpers.lua – minimal test helpers for headless nvim runs
--
-- Usage:
--   local T = require('test.helpers')
--   T.group('my group', function()
--     T.eq(actual, expected, 'description')
--     T.ok(condition, 'description')
--   end)
--   T.finish()   -- exits 0 on success, 1 on failure

local M = {}

local pass_count = 0
local fail_count = 0
local current_group = ''

local function fmt_fail(desc, msg)
  io.stderr:write(string.format('  FAIL [%s] %s\n    %s\n', current_group, desc, msg))
end

local function pass(desc)
  pass_count = pass_count + 1
  io.stdout:write(string.format('  pass [%s] %s\n', current_group, desc))
end

--- Assert two values are equal (uses vim.deep_equal for tables).
---@param actual any
---@param expected any
---@param desc string
function M.eq(actual, expected, desc)
  local ok
  if type(actual) == 'table' or type(expected) == 'table' then
    ok = vim.deep_equal(actual, expected)
  else
    ok = actual == expected
  end
  if ok then
    pass(desc)
  else
    fail_count = fail_count + 1
    fmt_fail(desc, string.format('expected %s, got %s', vim.inspect(expected), vim.inspect(actual)))
  end
end

--- Assert a condition is truthy.
---@param condition any
---@param desc string
function M.ok(condition, desc)
  if condition then
    pass(desc)
  else
    fail_count = fail_count + 1
    fmt_fail(desc, 'condition was falsy')
  end
end

--- Run a group of assertions, catching errors so one failure doesn't abort all.
---@param name string
---@param fn function
function M.group(name, fn)
  current_group = name
  io.stdout:write(string.format('\n%s\n', name))
  local ok, err = pcall(fn)
  if not ok then
    fail_count = fail_count + 1
    fmt_fail('(group error)', tostring(err))
  end
end

--- Print summary and exit with appropriate code.
function M.finish()
  io.stdout:write(string.format('\n%d passed, %d failed\n', pass_count, fail_count))
  if fail_count > 0 then
    os.exit(1)
  else
    os.exit(0)
  end
end

return M
