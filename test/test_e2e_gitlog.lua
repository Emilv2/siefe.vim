-- test/test_e2e_gitlog.lua
-- Exhaustive end-to-end tests for the git log picker.
--
-- Creates a temporary git repository with a known, reproducible history and
-- verifies that the git log picker shows the correct commits under every
-- filtering and search mode.
--
-- Repository layout created by this test:
--
--   gitrepo/
--   ├── src/
--   │   ├── main.lua    (commits: A  C  E)
--   │   └── utils.lua   (commit:     B    )
--   └── docs/
--       └── readme.txt  (commit:        D )
--
-- Commits (newest = E at top in reverse-list layout):
--   E  GITLOGTEST_REMOVE_E  removes UNIQUE_PICKAXE_TOKEN from main.lua
--   D  GITLOGTEST_DOCS_D    adds docs/readme.txt
--   C  GITLOGTEST_MARKER_C  adds UNIQUE_PICKAXE_TOKEN to main.lua
--   B  GITLOGTEST_UTILS_B   adds src/utils.lua
--   A  GITLOGTEST_INIT_A    initial: adds src/main.lua
--
-- Tests covered:
--   1. Unfiltered log shows all 5 commits
--   2. File filter (src/main.lua) → 3 commits (A, C, E); B and D absent
--   3. Directory filter (src/) → 4 commits (A, B, C, E); D absent
--   4. From subdirectory (src/), no path filter → all 5 commits still visible
--   5. From subdirectory, absolute-path filter → same result as test 2
--   6. Pickaxe -G (regex): type UNIQUE_PICKAXE_TOKEN → C and E visible
--   7. Pickaxe -S (literal count-diff): type UNIQUE_PICKAXE_TOKEN → C and E
--   8. F7 preview cycle key: 3 presses do not crash fzf

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))

-- ── Prerequisites ─────────────────────────────────────────────────────────────

local fzf_lua_path = os.getenv('FZF_LUA_PATH') or '/tmp/fzf-lua'
if vim.fn.isdirectory(fzf_lua_path) == 0 then
  io.stdout:write('SKIP: fzf-lua not found at ' .. fzf_lua_path .. '\n')
  io.stdout:write('  Clone with: git clone --depth=1 https://github.com/ibhagwan/fzf-lua ' .. fzf_lua_path .. '\n')
  os.exit(0)
end
vim.opt.rtp:prepend(fzf_lua_path)

if vim.fn.executable('fzf') ~= 1 then
  io.stdout:write('SKIP: fzf binary not found in PATH\n')
  os.exit(0)
end

local ok_fzflua = pcall(require, 'fzf-lua')
if not ok_fzflua then
  io.stdout:write('SKIP: fzf-lua could not be loaded\n')
  os.exit(0)
end

local T = require('test.helpers')
local E = require('test.helpers_e2e')

-- ── Build a temporary git repository with known history ───────────────────────

-- Use vim.fn.tempname() for a guaranteed-unique path managed by Neovim's
-- temporary-file infrastructure.  We append a suffix so the directory is
-- recognisable in logs.  This avoids both predictable names and the
-- timestamp uniqueness issues of manual PID/time combinations.
local gitrepo = vim.fn.tempname() .. '_siefe_gitlog'

vim.fn.mkdir(gitrepo .. '/src', 'p')
vim.fn.mkdir(gitrepo .. '/docs', 'p')

-- Run a git command inside the repo (GIT_CONFIG_NOSYSTEM=1 prevents reading
-- /etc/gitconfig or ~/.gitconfig which may not exist in CI environments).
local function git(args)
  return vim.fn.system('GIT_CONFIG_NOSYSTEM=1 git -C ' .. vim.fn.shellescape(gitrepo) .. ' ' .. args)
end

-- Initialise repo and set a local identity so commits don't fail with
-- "Please tell me who you are" in environments without a global git config.
git('init')
git('config user.email "test@siefe.test"')
git('config user.name "Siefe Test"')

-- Disable ANSI colour in git output so pattern matching against commit
-- messages is not confused by interspersed escape codes.
git('config color.ui false')
git('config color.diff false')

-- Commit A ─ initial: adds src/main.lua
vim.fn.writefile({ 'function setup()', 'return M' }, gitrepo .. '/src/main.lua')
git('add src/main.lua')
git("commit --no-gpg-sign -m 'GITLOGTEST_INIT_A'")

-- Commit B ─ adds src/utils.lua (separate file; should NOT appear for main.lua filter)
vim.fn.writefile({ 'function helper()', 'return {}' }, gitrepo .. '/src/utils.lua')
git('add src/utils.lua')
git("commit --no-gpg-sign -m 'GITLOGTEST_UTILS_B'")

-- Commit C ─ adds UNIQUE_PICKAXE_TOKEN to main.lua (count 0 → 1)
vim.fn.writefile(
  { 'function setup()', 'local UNIQUE_PICKAXE_TOKEN = 1', 'return M' },
  gitrepo .. '/src/main.lua'
)
git('add src/main.lua')
git("commit --no-gpg-sign -m 'GITLOGTEST_MARKER_C'")

-- Commit D ─ adds docs/readme.txt (separate dir; should NOT appear for src/ filter)
vim.fn.writefile({ 'readme text' }, gitrepo .. '/docs/readme.txt')
git('add docs/readme.txt')
git("commit --no-gpg-sign -m 'GITLOGTEST_DOCS_D'")

-- Commit E ─ removes UNIQUE_PICKAXE_TOKEN from main.lua (count 1 → 0)
vim.fn.writefile({ 'function setup()', 'return M' }, gitrepo .. '/src/main.lua')
git('add src/main.lua')
git("commit --no-gpg-sign -m 'GITLOGTEST_REMOVE_E'")

-- Sanity-check: verify the repo was created correctly before running tests.
local log_check = git('log --oneline --no-color')
if not log_check:match('GITLOGTEST_REMOVE_E') then
  io.stderr:write('ERROR: git repo setup failed:\n' .. log_check .. '\n')
  os.exit(1)
end

-- ── Launch helpers ────────────────────────────────────────────────────────────

-- Launch gitlogfzf from the repo root directory.  `get_git_root()` in
-- utils.lua first tries FugitiveFind (unavailable in headless tests), then
-- falls back to `git -C bufdir rev-parse --show-toplevel`.  Setting cwd to
-- gitrepo ensures the fallback resolves the correct git root, which is then
-- embedded as a literal path in the fzf commands.
local function launch_gitlog(kwargs, cwd, ready_ms)
  vim.cmd('cd ' .. vim.fn.fnameescape(cwd or gitrepo))
  return E.launch_and_wait(function()
    -- Clear module cache so each test starts with fresh kwargs defaults.
    package.loaded['siefe.git_log'] = nil
    require('siefe.git_log').gitlogfzf(false, kwargs or {})
  end, ready_ms or 2500)
end

-- ── Tests ─────────────────────────────────────────────────────────────────────

-- 1. Unfiltered log shows all 5 commits ----------------------------------------

T.group('e2e git log: all 5 commits visible in unfiltered log', function()
  vim.cmd('enew!')
  local h = launch_gitlog({})
  T.ok(h ~= nil, 'picker launched')
  if not h then
    return
  end

  -- With --layout=reverse-list, newest commit (E) is at the top of the list.
  -- Wait for E, then confirm all others are present too.  We wait for A
  -- (oldest) as the final confirmation that all entries have been loaded.
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_REMOVE_E', 4000)
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_INIT_A', 4000)
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_REMOVE_E'), 'commit E visible')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_DOCS_D'), 'commit D visible')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_MARKER_C'), 'commit C visible')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_UTILS_B'), 'commit B visible')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_INIT_A'), 'commit A visible')

  vim.fn.chansend(h.chan, '\x1b') -- ESC
  E.wait_fzf_close(h.fzf_buf, 3000)
end)

-- 2. File filter: only commits touching src/main.lua ---------------------------

T.group('e2e git log: file filter shows only commits touching that file', function()
  vim.cmd('enew!')
  -- Pass the absolute path so git can resolve it regardless of cwd.
  local h = launch_gitlog({ paths = { gitrepo .. '/src/main.lua' } })
  T.ok(h ~= nil, 'picker launched (file filter)')
  if not h then
    return
  end

  -- Three commits touch src/main.lua: A (initial), C (add token), E (remove).
  -- Wait for A to confirm all matching entries have been emitted by git.
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_REMOVE_E', 4000)
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_INIT_A', 4000)
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_REMOVE_E'), 'commit E visible for main.lua')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_MARKER_C'), 'commit C visible for main.lua')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_INIT_A'), 'commit A visible for main.lua')
  -- B (utils.lua) and D (readme.txt) do NOT touch main.lua → absent.
  T.ok(not E.has_pattern(h.fzf_buf, 'GITLOGTEST_UTILS_B'), 'commit B absent for main.lua')
  T.ok(not E.has_pattern(h.fzf_buf, 'GITLOGTEST_DOCS_D'), 'commit D absent for main.lua')

  vim.fn.chansend(h.chan, '\x1b')
  E.wait_fzf_close(h.fzf_buf, 3000)
end)

-- 3. Directory filter: only commits touching src/ ------------------------------

T.group('e2e git log: directory filter shows only commits touching that directory', function()
  vim.cmd('enew!')
  local h = launch_gitlog({ paths = { gitrepo .. '/src/' } })
  T.ok(h ~= nil, 'picker launched (dir filter)')
  if not h then
    return
  end

  -- Four commits touch src/: A, B, C, E.
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_REMOVE_E', 4000)
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_INIT_A', 4000)
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_REMOVE_E'), 'commit E visible for src/')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_MARKER_C'), 'commit C visible for src/')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_UTILS_B'), 'commit B visible for src/')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_INIT_A'), 'commit A visible for src/')
  -- D touches only docs/ → must be absent.
  T.ok(not E.has_pattern(h.fzf_buf, 'GITLOGTEST_DOCS_D'), 'commit D absent for src/')

  vim.fn.chansend(h.chan, '\x1b')
  E.wait_fzf_close(h.fzf_buf, 3000)
end)

-- 4. From subdirectory: unfiltered log still shows all commits -----------------

T.group('e2e git log: from subdirectory, unfiltered log shows all commits', function()
  -- cd into src/ — git rev-parse --show-toplevel (run inside the fzf shell
  -- command) must still resolve the correct repo root.
  vim.cmd('enew!')
  local h = launch_gitlog({}, gitrepo .. '/src')
  T.ok(h ~= nil, 'picker launched from subdir (no paths)')
  if not h then
    return
  end

  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_REMOVE_E', 4000)
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_INIT_A', 4000)
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_REMOVE_E'), 'commit E visible from subdir')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_DOCS_D'), 'commit D visible from subdir')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_MARKER_C'), 'commit C visible from subdir')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_UTILS_B'), 'commit B visible from subdir')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_INIT_A'), 'commit A visible from subdir')

  vim.fn.chansend(h.chan, '\x1b')
  E.wait_fzf_close(h.fzf_buf, 3000)
end)

-- 5. From subdirectory with absolute path filter --------------------------------

T.group('e2e git log: from subdirectory, absolute-path filter works correctly', function()
  vim.cmd('enew!')
  -- Use an absolute path so git (running in the repo root) can find the file
  -- even though Neovim's cwd is src/.
  local h = launch_gitlog({ paths = { gitrepo .. '/src/main.lua' } }, gitrepo .. '/src')
  T.ok(h ~= nil, 'picker launched from subdir (absolute path)')
  if not h then
    return
  end

  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_REMOVE_E', 4000)
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_INIT_A', 4000)
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_REMOVE_E'), 'commit E visible (abs path / subdir)')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_MARKER_C'), 'commit C visible (abs path / subdir)')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_INIT_A'), 'commit A visible (abs path / subdir)')
  T.ok(not E.has_pattern(h.fzf_buf, 'GITLOGTEST_UTILS_B'), 'commit B absent (abs path / subdir)')
  T.ok(not E.has_pattern(h.fzf_buf, 'GITLOGTEST_DOCS_D'), 'commit D absent (abs path / subdir)')

  vim.fn.chansend(h.chan, '\x1b')
  E.wait_fzf_close(h.fzf_buf, 3000)
end)

-- 6. Pickaxe -G (regex): typing a pattern filters to matching diff hunks -------

T.group('e2e git log: pickaxe -G regex filters to commits with matching diff', function()
  vim.cmd('enew!')
  -- G=true (default) uses -G which finds commits whose diff contains a line
  -- matching the regex.  Both C (adds) and E (removes) touch the token.
  local h = launch_gitlog({ G = true })
  T.ok(h ~= nil, 'picker launched (-G mode)')
  if not h then
    return
  end

  -- Wait for the initial unfiltered list to appear before typing.
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_', 3000)

  -- Type the pickaxe pattern; the reload command sends it to git -G.
  E.fzf_type(h.chan, 'UNIQUE_PICKAXE_TOKEN', 300)

  -- After git reloads, only commits C and E should appear.
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_MARKER_C', 6000)
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_REMOVE_E', 6000)
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_MARKER_C'), 'commit C visible (-G)')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_REMOVE_E'), 'commit E visible (-G)')

  vim.fn.chansend(h.chan, '\x1b')
  E.wait_fzf_close(h.fzf_buf, 3000)
end)

-- 7. Pickaxe -S (literal string count diff) ------------------------------------

T.group('e2e git log: pickaxe -S finds commits where string count changes', function()
  vim.cmd('enew!')
  -- G=false switches to -S mode: git finds commits where the number of
  -- occurrences of the literal string changes between the two tree states.
  -- UNIQUE_PICKAXE_TOKEN: 0→1 in C, 1→0 in E → both should appear.
  local h = launch_gitlog({ G = false })
  T.ok(h ~= nil, 'picker launched (-S mode)')
  if not h then
    return
  end

  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_', 3000)
  E.fzf_type(h.chan, 'UNIQUE_PICKAXE_TOKEN', 300)

  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_MARKER_C', 6000)
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_REMOVE_E', 6000)
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_MARKER_C'), 'commit C visible (-S)')
  T.ok(E.has_pattern(h.fzf_buf, 'GITLOGTEST_REMOVE_E'), 'commit E visible (-S)')

  vim.fn.chansend(h.chan, '\x1b')
  E.wait_fzf_close(h.fzf_buf, 3000)
end)

-- 8. F7 preview cycle: 3 presses do not crash fzf ------------------------------

T.group('e2e git log: F7 preview cycle key does not crash fzf', function()
  vim.cmd('enew!')
  local h = launch_gitlog({})
  T.ok(h ~= nil, 'picker launched for F7 test')
  if not h then
    return
  end

  -- Wait until at least one entry is visible so a commit is focused.
  E.wait_fzf_match(h.fzf_buf, 'GITLOGTEST_REMOVE_E', 4000)

  -- F7 xterm terminal escape sequence: ESC [ 1 8 ~
  -- Each press: execute-silent(toggle_script) + refresh-preview
  --   mode 0 → 1 (matching files)  → 2 (matching hunks) → 3 (diff) → ...
  local f7 = '\x1b[18~'

  vim.fn.chansend(h.chan, f7) -- press #1
  vim.wait(700) -- allow preview to re-render
  T.ok(
    vim.api.nvim_get_option_value('buftype', { buf = h.fzf_buf }) == 'terminal',
    'fzf still running after F7 #1 (mode 0→1)'
  )

  vim.fn.chansend(h.chan, f7) -- press #2
  vim.wait(700)
  T.ok(
    vim.api.nvim_get_option_value('buftype', { buf = h.fzf_buf }) == 'terminal',
    'fzf still running after F7 #2 (mode 1→2)'
  )

  vim.fn.chansend(h.chan, f7) -- press #3
  vim.wait(700)
  T.ok(
    vim.api.nvim_get_option_value('buftype', { buf = h.fzf_buf }) == 'terminal',
    'fzf still running after F7 #3 (mode 2→3)'
  )

  vim.fn.chansend(h.chan, '\x1b') -- ESC
  E.wait_fzf_close(h.fzf_buf, 3000)
end)

-- ── Cleanup ───────────────────────────────────────────────────────────────────

vim.fn.delete(gitrepo, 'rf')
T.finish()
