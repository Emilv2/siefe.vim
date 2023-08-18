" Title:        Siefe, Fzf Sieve
" Description:  Plugin for meticulous searching in your git repository and history
" Maintainer:   Emil vanherp <emil@vanherp.me>

if exists('g:loaded_siefe')
    finish
endif
let g:loaded_siefe = 1

let g:siefe_rg_default_word = get(g:, 'siefe_rg_default_word', 0)
let g:siefe_rg_default_case_sensitive = get(g:, 'siefe_rg_default_case_sensitive', 0)
let g:siefe_rg_default_hidden = get(g:, 'siefe_rg_default_hidden', 0)
let g:siefe_rg_default_no_ignore = get(g:, 'siefe_rg_default_no_ignore', 0)
let g:siefe_rg_default_fixed_strings = get(g:, 'siefe_rg_default_fixed_strings', 0)
let g:siefe_rg_default_max_1 = get(g:, 'siefe_rg_default_max_1', 0)
let g:siefe_rg_default_search_zip = get(g:, 'siefe_rg_default_search_zip', 0)

command! -nargs=* -bang SiefeRg call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : <q-args>,
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeRgVisual call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : siefe#visual_selection(),
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \  'fixed_strings' : 1,
            \ })

command! -nargs=* -bang SiefeRgWord call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : expand('<cword>'),
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeRgWORD call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : expand('<cWORD>'),
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeRgLine call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : trim(getline('.')),
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeProjectRg call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : <q-args>,
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeProjectRgVisual call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : siefe#visual_selection(),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeProjectRgWord call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : expand('<cword>'),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeProjectRgWORD call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : expand('<cWORD>'),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeProjectRgLine call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : trim(getline('.')),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \ })

command! -nargs=* -bang SiefeBuffersRg call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : <q-args>,
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'paths' : map(filter(copy(getbufinfo()), 'v:val.listed'),  'fnamemodify(v:val.name, ":p:~:.")'),
  \ })

command! -nargs=* -bang SiefeBuffersRgWord call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : expand('<cword>'),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'paths' : map(filter(copy(getbufinfo()), 'v:val.listed'),  'fnamemodify(v:val.name, ":p:~:.")'),
  \ })

command! -nargs=* -bang SiefeBuffersRgWORD call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : expand('<cWORD>'),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'paths' : map(filter(copy(getbufinfo()), 'v:val.listed'),  'fnamemodify(v:val.name, ":p:~:.")'),
  \ })

command! -nargs=* -bang SiefeFiles call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : <q-args>,
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeFilesVisual call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : siefe#visual_selection(),
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \  'fixed_strings' : 1,
  \  'files' : '//',
            \ })

command! -nargs=* -bang SiefeFilesWord call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : expand('<cword>'),
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeFilesWORD call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : expand('<cWORD>'),
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeFilesLine call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#bufdir(),
  \ {
  \  'query' : trim(getline('.')),
  \  'prompt' : siefe#get_relative_git_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeProjectFiles call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : <q-args>,
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeProjectFilesVisual call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : siefe#visual_selection(),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeProjectFilesWord call siefe#ripgrepfzf(expand(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : expand('<cword>'),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeProjectFilesWORD call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : expand('<cWORD>'),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeProjectFilesLine call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : trim(getline('.')),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'files' : '//',
  \ })

command! -nargs=* -bang SiefeHistory call siefe#history(
  \ <bang>0,
  \ {
  \  'query' : <q-args>,
  \ })

command! -nargs=* -bang SiefeProjectHistory call siefe#history(
  \ <bang>0,
  \ {
  \  'query' : <q-args>,
  \  'project' : 1,
  \ })

" TODO
command! -nargs=* -bang SiefeRgHistory call siefe#ripgrepfzf(
  \ <bang>0,
  \ siefe#get_git_root(),
  \ {
  \  'query' : trim(getline('.')),
  \  'prompt' : siefe#get_git_basename_or_bufdir(),
  \  'files' : '//',
  \ })


command! -nargs=* -bang SiefeGitLog     call siefe#gitlogfzf(<bang>0, {'query': <q-args> })
command! -nargs=* -bang SiefeGitLogWord call siefe#gitlogfzf(<bang>0, {'query': expand("<cword>")})
command! -nargs=* -bang SiefeGitLogWORD call siefe#gitlogfzf(<bang>0, {'query': expand("<cWORD>")})
command! -nargs=* -bang SiefeGitLogVisual call siefe#gitlogfzf(<bang>0, {'query': siefe#visual_selection() })
command! -nargs=* -bang SiefeGitBufferLog call siefe#gitlogfzf(<bang>0, {'query': <q-args>, 'paths' : [fnamemodify(expand('%'), ':p')] })
command! -nargs=* -bang SiefeGitBufferLogWord call siefe#gitlogfzf(<bang>0, {'query': expand("<cword>"), 'paths' : [fnamemodify(expand('%'), ':p')] })
command! -nargs=* -bang SiefeGitBufferLogWORD call siefe#gitlogfzf(<bang>0, {'query': expand("<cWORD>"), 'paths' : [fnamemodify(expand('%'), ':p')] })
command! -nargs=* -bang SiefeGitBufferLogVisual call siefe#gitlogfzf(<bang>0, {'query': siefe#visual_selection(), 'paths' : [fnamemodify(expand('%'), ':p')] })
command! -nargs=* -bang SiefeGitLLog    call siefe#gitlogfzf(<bang>0, {'query': trim(getline('.')), 'paths' : [fnamemodify(expand('%'), ':p')], 'line_range' : siefe#visual_line_nu()})

command! -bang SiefeMarks               call siefe#marks(<bang>0, {'query': <q-args> })

command! -bang SiefeGitBranch            call siefe#gitbranch(<bang>0)

command! SiefeToggleGitStatus           call siefe#toggle_git_status()
command! -bang SiefeGitStash            call siefe#gitstash(<bang>0, {'query': <q-args> })

command! -nargs=* -bang SiefeBuffers call siefe#buffers(
            \ <bang>0,
            \ {
            \  'query' : <q-args>,
            \ })

if !exists('g:siefe#buffers')
  let g:siefe#buffers = {}
endif

augroup siefe_buffers
  autocmd!
  if exists('*reltimefloat')
    autocmd BufWinEnter,WinEnter * let g:siefe#buffers[bufnr('')] = reltimefloat(reltime())
  else
    autocmd BufWinEnter,WinEnter * let g:siefe#buffers[bufnr('')] = localtime()
  endif
  autocmd BufDelete * silent! call remove(g:siefe#buffers, expand('<abuf>'))
augroup END
