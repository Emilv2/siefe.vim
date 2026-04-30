-- plugin/siefe.lua
-- Command definitions, <Plug> mappings, and autocmds for siefe.vim (Lua rewrite)

if vim.g.loaded_siefe_lua then
  return
end
vim.g.loaded_siefe_lua = 1

local siefe = require('siefe')
local utils = require('siefe.utils')
local config = require('siefe.config')

-- Ensure the buffer tracker autocmd is set up even without explicit setup()
vim.api.nvim_create_augroup('siefe_buffer_tracker', { clear = true })
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
  group = 'siefe_buffer_tracker',
  callback = function(args)
    siefe.buffers_tracker[args.buf] = (vim.uv or vim.loop).hrtime()
  end,
})
vim.api.nvim_create_autocmd('BufDelete', {
  group = 'siefe_buffer_tracker',
  callback = function(args)
    siefe.buffers_tracker[args.buf] = nil
  end,
})

-- ── Helper for buffer list ───────────────────────────────────────────────────

local function buf_paths()
  return vim.tbl_map(
    function(info)
      return vim.fn.fnamemodify(info.name, ':p:~:.')
    end,
    vim.tbl_filter(function(info)
      return info.listed == 1
    end, vim.fn.getbufinfo())
  )
end

-- ── Conflict regex ───────────────────────────────────────────────────────────

local git_conflict_regex = '^(<{7} .*|={7}$|\\|{7}$|>{7} .*)'

-- ── Commands ─────────────────────────────────────────────────────────────────

vim.api.nvim_create_user_command('SiefeRg', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = args.args,
    prompt = utils.get_relative_git_or_bufdir(),
  })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeRgVisual', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = utils.visual_selection(),
    prompt = utils.get_relative_git_or_bufdir(),
    fixed_strings = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeRgWord', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = vim.fn.expand('<cword>'),
    prompt = utils.get_relative_git_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeRgWORD', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = vim.fn.expand('<cWORD>'),
    prompt = utils.get_relative_git_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeRgLine', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = vim.trim(vim.fn.getline('.')),
    prompt = utils.get_relative_git_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeRgConflict', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = git_conflict_regex,
    prompt = utils.get_relative_git_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectRg', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = args.args,
    prompt = utils.get_git_basename_or_bufdir(),
  })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeProjectRgVisual', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = utils.visual_selection(),
    prompt = utils.get_git_basename_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectRgWord', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.fn.expand('<cword>'),
    prompt = utils.get_git_basename_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectRgWORD', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.fn.expand('<cWORD>'),
    prompt = utils.get_git_basename_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectRgLine', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.trim(vim.fn.getline('.')),
    prompt = utils.get_git_basename_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectRgConflict', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = git_conflict_regex,
    prompt = utils.get_git_basename_or_bufdir(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeBuffersRg', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = args.args,
    prompt = utils.get_git_basename_or_bufdir(),
    paths = buf_paths(),
  })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeBuffersRgWord', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.fn.expand('<cword>'),
    prompt = utils.get_git_basename_or_bufdir(),
    paths = buf_paths(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeBuffersRgWORD', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.fn.expand('<cWORD>'),
    prompt = utils.get_git_basename_or_bufdir(),
    paths = buf_paths(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeBuffersRgLine', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.trim(vim.fn.getline('.')),
    prompt = utils.get_git_basename_or_bufdir(),
    paths = buf_paths(),
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeFiles', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = args.args,
    prompt = utils.get_relative_git_or_bufdir(),
    files = true,
  })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeFilesVisual', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = utils.visual_selection(),
    prompt = utils.get_relative_git_or_bufdir(),
    fixed_strings = true,
    files = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeFilesWord', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = vim.fn.expand('<cword>'),
    prompt = utils.get_relative_git_or_bufdir(),
    files = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeFilesWORD', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = vim.fn.expand('<cWORD>'),
    prompt = utils.get_relative_git_or_bufdir(),
    files = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeFilesLine', function(args)
  siefe.ripgrepfzf(args.bang, utils.bufdir(), {
    query = vim.trim(vim.fn.getline('.')),
    prompt = utils.get_relative_git_or_bufdir(),
    files = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectFiles', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = args.args,
    prompt = utils.get_git_basename_or_bufdir(),
    files = true,
  })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeProjectFilesVisual', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = utils.visual_selection(),
    prompt = utils.get_git_basename_or_bufdir(),
    files = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectFilesWord', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.fn.expand('<cword>'),
    prompt = utils.get_git_basename_or_bufdir(),
    files = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectFilesWORD', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.fn.expand('<cWORD>'),
    prompt = utils.get_git_basename_or_bufdir(),
    files = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeProjectFilesLine', function(args)
  siefe.ripgrepfzf(args.bang, utils.get_git_root(), {
    query = vim.trim(vim.fn.getline('.')),
    prompt = utils.get_git_basename_or_bufdir(),
    files = true,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeHistory', function(args)
  siefe.historyoldfiles(args.bang, { query = args.args })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeProjectHistory', function(args)
  siefe.historyoldfiles(args.bang, { query = args.args, project = true })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeRegisters', function(args)
  siefe.registers(false, { query = '' })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitLog', function(args)
  siefe.gitlogfzf(args.bang, { query = args.args })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeGitLogWord', function(args)
  siefe.gitlogfzf(args.bang, { query = vim.fn.expand('<cword>') })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitLogWORD', function(args)
  siefe.gitlogfzf(args.bang, { query = vim.fn.expand('<cWORD>') })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitLogVisual', function(args)
  siefe.gitlogfzf(args.bang, { query = utils.visual_selection() })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitBufferLog', function(args)
  siefe.gitlogfzf(args.bang, {
    query = args.args,
    paths = { vim.fn.fnamemodify(vim.fn.expand('%'), ':p') },
  })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeGitBufferLogWord', function(args)
  siefe.gitlogfzf(args.bang, {
    query = vim.fn.expand('<cword>'),
    paths = { vim.fn.fnamemodify(vim.fn.expand('%'), ':p') },
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitBufferLogWORD', function(args)
  siefe.gitlogfzf(args.bang, {
    query = vim.fn.expand('<cWORD>'),
    paths = { vim.fn.fnamemodify(vim.fn.expand('%'), ':p') },
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitBufferLogVisual', function(args)
  siefe.gitlogfzf(args.bang, {
    query = utils.visual_selection(),
    paths = { vim.fn.fnamemodify(vim.fn.expand('%'), ':p') },
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitLLog', function(args)
  local lines = utils.visual_line_nu()
  siefe.gitlogfzf(args.bang, {
    query = vim.trim(vim.fn.getline('.')),
    paths = { vim.fn.fnamemodify(vim.fn.expand('%'), ':p') },
    line_range = lines,
  })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitStatus', function(args)
  siefe.gitstatus(args.bang, { query = args.args })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeToggleGitStatus', function()
  siefe.toggle_git_status()
end, { nargs = 0 })

vim.api.nvim_create_user_command('SiefeGitBranch', function(args)
  siefe.gitbranch(args.bang)
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeGitStash', function(args)
  siefe.gitstash(args.bang, { query = args.args })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeMarks', function(args)
  siefe.marks(args.bang, { query = args.args })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeJumps', function(args)
  siefe.jumps(args.bang, { query = args.args })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeBuffers', function(args)
  siefe.buffers(args.bang, { query = args.args })
end, { nargs = '*', bang = true })

vim.api.nvim_create_user_command('SiefeMaps', function(args)
  siefe.maps(args.bang, '', { 'n' })
end, { nargs = 0, bang = true })

vim.api.nvim_create_user_command('SiefeWindows', function(args)
  siefe.windows(args.bang, { query = args.args })
end, { nargs = '*', bang = true })

-- :SiefeInstall       — install / build binaries if missing
-- :SiefeInstall!      — force reinstall even if already present
vim.api.nvim_create_user_command('SiefeInstall', function(args)
  siefe.install(args.bang)
end, { nargs = 0, bang = true })

-- ── <Plug> Mappings ───────────────────────────────────────────────────────────

local function plug(lhs, rhs_cmd, mode)
  mode = mode or 'n'
  vim.keymap.set(mode, lhs, rhs_cmd, { silent = true })
end

plug('<Plug>SiefeRG', '<cmd>SiefeRg<CR>')
plug('<Plug>SiefeRgWord', '<cmd>SiefeRgWord<CR>')
plug('<Plug>SiefeRgWORD', '<cmd>SiefeRgWORD<CR>')
plug('<Plug>SiefeRgLine', '<cmd>SiefeRgLine<CR>')
plug('<Plug>SiefeRgConflict', '<cmd>SiefeRgConflict<CR>')
plug('<Plug>SiefeRgVisual', ':<c-u>SiefeRgVisual<CR>', 'x')
plug('<Plug>SiefeFiles', '<cmd>SiefeFiles<CR>')
plug('<Plug>SiefeFilesWord', '<cmd>SiefeFilesWord<CR>')
plug('<Plug>SiefeFilesWORD', '<cmd>SiefeFilesWORD<CR>')
plug('<Plug>SiefeFilesLine', ':<c-u>SiefeFilesLine<CR>')
plug('<Plug>SiefeFilesVisual', ':<c-u>SiefeFilesVisual<CR>', 'x')

plug('<Plug>SiefeProjectRG', '<cmd>SiefeProjectRg<CR>')
plug('<Plug>SiefeProjectRgWord', '<cmd>SiefeProjectRgWord<CR>')
plug('<Plug>SiefeProjectRgWORD', '<cmd>SiefeProjectRgWORD<CR>')
plug('<Plug>SiefeProjectRgLine', '<cmd>SiefeProjectRgLine<CR>')
plug('<Plug>SiefeProjectRgConflict', '<cmd>SiefeProjectRgConflict<CR>')
plug('<Plug>SiefeProjectRgVisual', ':<c-u>SiefeProjectRgVisual<CR>', 'x')
plug('<Plug>SiefeProjectFiles', '<cmd>SiefeProjectFiles<CR>')
plug('<Plug>SiefeProjectFilesWord', '<cmd>SiefeProjectFilesWord<CR>')
plug('<Plug>SiefeProjectFilesWORD', '<cmd>SiefeProjectFilesWORD<CR>')
plug('<Plug>SiefeProjectFilesLine', '<cmd>SiefeProjectFilesLine<CR>')
plug('<Plug>SiefeProjectFilesVisual', ':<c-u>SiefeProjectFilesVisual<CR>', 'x')

plug('<Plug>SiefeBuffersRG', '<cmd>SiefeBuffersRg<CR>')
plug('<Plug>SiefeBuffersRgWord', '<cmd>SiefeBuffersRgWord<CR>')
plug('<Plug>SiefeBuffersRgWORD', '<cmd>SiefeBuffersRgWORD<CR>')
plug('<Plug>SiefeBuffersRgLine', '<cmd>SiefeBuffersRgLine<CR>')

plug('<Plug>SiefeRgP', '<cmd>SiefeRg <c-r>+<CR>')
plug('<Plug>SiefeProjectRgP', '<cmd>SiefeProjectRg <c-r>+<CR>')

plug('<Plug>SiefeMarks', '<cmd>SiefeMarks<CR>')
plug('<Plug>SiefeJumps', '<cmd>SiefeJumps<CR>')
plug('<Plug>SiefeHistory', '<cmd>SiefeHistory<CR>')
plug('<Plug>SiefeProjectHistory', '<cmd>SiefeProjectHistory<CR>')
plug('<Plug>SiefeBuffers', '<cmd>SiefeBuffers<CR>')
plug('<Plug>SiefeToggleGitStatus', '<cmd>SiefeToggleGitStatus<CR>')
plug('<Plug>SiefeGitStash', '<cmd>SiefeGitStash<CR>')
plug('<Plug>SiefeGitBufferLog', '<cmd>SiefeGitBufferLog<CR>')
plug('<Plug>SiefeGitBufferLogVisual', ':<c-u>SiefeGitBufferLogVisual<CR>', 'x')
plug('<Plug>SiefeGitLLog', ':<c-u>SiefeGitLLog<CR>', 'x')
plug('<Plug>SiefeGitBufferLogWord', '<cmd>SiefeGitBufferLogWord<CR>')
plug('<Plug>SiefeGitBufferLogWORD', '<cmd>SiefeGitBufferLogWORD<CR>')
plug('<Plug>SiefeGitLog', '<cmd>SiefeGitLog<CR>')
plug('<Plug>SiefeGitLogVisual', ':<c-u>SiefeGitLogVisual<CR>', 'x')
plug('<Plug>SiefeGitLogWord', '<cmd>SiefeGitLogWord<CR>')
plug('<Plug>SiefeGitLogWORD', '<cmd>SiefeGitLogWORD<CR>')
plug('<Plug>SiefeGitStatus', '<cmd>SiefeGitStatus<CR>')
plug('<Plug>SiefeRegisters', ':<c-u>SiefeRegisters<CR>')
plug('<Plug>SiefeMaps', '<cmd>SiefeMaps<CR>')
plug('<Plug>SiefeGitBranch', '<cmd>SiefeGitBranch<CR>')
plug('<Plug>SiefeWindows', '<cmd>SiefeWindows<CR>')
plug('<Plug>SiefeInstall', '<cmd>SiefeInstall<CR>')

-- ── Default key mappings (if enabled) ────────────────────────────────────────

if config.map_keys then
  local function maybe_map(mode, lhs, plug_name)
    if vim.fn.hasmapto(plug_name) == 0 and vim.fn.maparg(lhs, mode) == '' then
      vim.keymap.set(mode, lhs, plug_name, { silent = true, remap = true })
    end
  end

  maybe_map('n', '<leader>rg', '<Plug>SiefeRG')
  maybe_map('n', '<leader>rw', '<Plug>SiefeRgWord')
  maybe_map('n', '<leader>rW', '<Plug>SiefeRgWORD')
  maybe_map('n', '<leader>rl', '<Plug>SiefeRgLine')
  maybe_map('n', '<leader>rc', '<Plug>SiefeRgConflict')
  maybe_map('x', '<leader>rg', '<Plug>SiefeRgVisual')

  maybe_map('n', '<leader>ff', '<Plug>SiefeFiles')
  maybe_map('n', '<leader>fw', '<Plug>SiefeFilesWord')
  maybe_map('n', '<leader>fW', '<Plug>SiefeFilesWORD')
  maybe_map('n', '<leader>fl', '<Plug>SiefeFilesLine')
  maybe_map('x', '<leader>ff', '<Plug>SiefeFilesVisual')

  maybe_map('n', '<leader>Rg', '<Plug>SiefeProjectRG')
  maybe_map('n', '<leader>Rw', '<Plug>SiefeProjectRgWord')
  maybe_map('n', '<leader>RW', '<Plug>SiefeProjectRgWORD')
  maybe_map('n', '<leader>Rl', '<Plug>SiefeProjectRgLine')
  maybe_map('n', '<leader>Rc', '<Plug>SiefeProjectRgConflict')
  maybe_map('x', '<leader>Rg', '<Plug>SiefeProjectRgVisual')

  maybe_map('n', '<leader>Ff', '<Plug>SiefeProjectFiles')
  maybe_map('n', '<leader>Fw', '<Plug>SiefeProjectFilesWord')
  maybe_map('n', '<leader>FW', '<Plug>SiefeProjectFilesWORD')
  maybe_map('n', '<leader>Fl', '<Plug>SiefeProjectFilesLine')
  maybe_map('x', '<leader>Ff', '<Plug>SiefeProjectFilesVisual')

  maybe_map('n', '<leader>rp', '<Plug>SiefeRgP')
  maybe_map('n', '<leader>Rp', '<Plug>SiefeProjectRgP')

  maybe_map('n', '<leader>Bg', '<Plug>SiefeBuffersRG')
  maybe_map('n', '<leader>Bw', '<Plug>SiefeBuffersRgWord')
  maybe_map('n', '<leader>BW', '<Plug>SiefeBuffersRgWORD')
  maybe_map('n', '<leader>Bl', '<Plug>SiefeBuffersRgLine')

  maybe_map('n', '<leader>m', '<Plug>SiefeMarks')
  maybe_map('n', '<leader>j', '<Plug>SiefeJumps')
  maybe_map('n', '<leader>hH', '<Plug>SiefeHistory')
  maybe_map('n', '<leader>hh', '<Plug>SiefeProjectHistory')
  maybe_map('n', '<leader>b', '<Plug>SiefeBuffers')
  maybe_map('n', '<leader>gg', '<Plug>SiefeToggleGitStatus')
  maybe_map('n', '<leader>gs', '<Plug>SiefeGitStash')
  maybe_map('n', '<leader>gl', '<Plug>SiefeGitBufferLog')
  maybe_map('x', '<leader>gl', '<Plug>SiefeGitBufferLogVisual')
  maybe_map('x', '<leader>gL', '<Plug>SiefeGitLLog')
  maybe_map('n', '<leader>gw', '<Plug>SiefeGitBufferLogWord')
  maybe_map('n', '<leader>gW', '<Plug>SiefeGitBufferLogWORD')
  maybe_map('n', '<leader>Gl', '<Plug>SiefeGitLog')
  maybe_map('x', '<leader>Gl', '<Plug>SiefeGitLogVisual')
  maybe_map('n', '<leader>Gw', '<Plug>SiefeGitLogWord')
  maybe_map('n', '<leader>GW', '<Plug>SiefeGitLogWORD')
  maybe_map('n', '<leader>RR', '<Plug>SiefeRegisters')
  maybe_map('n', '<leader>M', '<Plug>SiefeMaps')
  maybe_map('n', '<leader>g?', '<Plug>SiefeGitStatus')
  maybe_map('n', '<leader>gf', '<Plug>SiefeGitBranch')
  maybe_map('n', '<leader>W', '<Plug>SiefeWindows')
end
