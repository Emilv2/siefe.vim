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

let g:siefe_map_keys = get(g:, 'siefe_map_keys', 1)

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
command! -bang SiefeJumps               call siefe#jumps(<bang>0, {'query': <q-args> })

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

nnoremap <silent> <Plug>SiefeRG :SiefeRg<CR>
nnoremap <silent> <Plug>SiefeRgWord :SiefeRgWord<CR>
nnoremap <silent> <Plug>SiefeRgWORD :SiefeRgWORD<CR>
nnoremap <silent> <Plug>SiefeRgLine :SiefeRgLine<CR>
nnoremap <silent> <Plug>SiefeFiles :SiefeFiles<CR>
xnoremap <silent> <Plug>SiefeRgVisual :<c-u>SiefeRgVisual<CR>

nnoremap <silent> <Plug>SiefeProjectRG :SiefeProjectRg<CR>
nnoremap <silent> <Plug>SiefeProjectRgWord :SiefeProjectRgWord<CR>
nnoremap <silent> <Plug>SiefeProjectRgWORD :SiefeProjectRgWORD<CR>
nnoremap <silent> <Plug>SiefeProjectRgLine :SiefeProjectRgLine<CR>
nnoremap <silent> <Plug>SiefeProjectFiles :SiefeProjectFiles<CR>

nnoremap <silent> <Plug>SiefeRgP :SiefeRg <c-r>+<CR>
nnoremap <silent> <Plug>SiefeProjectRgP :SiefeProjectRg <c-r>+<CR>

nnoremap <silent> <Plug>SiefeMarks :SiefeMarks<CR>
nnoremap <silent> <Plug>SiefeJumps :SiefeJumps<CR>
nnoremap <silent> <Plug>SiefeHistory :SiefeHistory<CR>
nnoremap <silent> <Plug>SiefeProjectHistory :SiefeProjectHistory<CR>
nnoremap <silent> <Plug>SiefeBuffers :SiefeBuffers<CR>
nnoremap <silent> <Plug>SiefeToggleGitStatus :SiefeToggleGitStatus<CR>
nnoremap <silent> <Plug>SiefeGitBufferLogg :SiefeGitBufferLog<CR>
xnoremap <silent> <Plug>SiefeGitBufferLogVisual :<c-u>SiefeGitBufferLogVisual<CR>
xnoremap <silent> <Plug>SiefeGitLLog :<c-u>SiefeGitLLog<CR>
nnoremap <silent> <Plug>SiefeGitBufferLogWord :SiefeGitBufferLogWord<CR>
nnoremap <silent> <Plug>SiefeGitBufferLogWORD :SiefeGitBufferLogWORD<CR>
nnoremap <silent> <Plug>SiefeGitLogg :SiefeGitLog<CR>
xnoremap <silent> <Plug>SiefeGitLogVisual :<c-u>SiefeGitLogVisual<CR>
nnoremap <silent> <Plug>SiefeGitLogWord :SiefeGitLogWord<CR>
nnoremap <silent> <Plug>SiefeGitLogWORD :SiefeGitLogWORD<CR>

if exists(':Maps')
  nnoremap <silent> <Plug>Maps :Maps<CR>
endif

if exists(':History')
  nnoremap <silent> <Plug>HistorySearch :History/<CR>
  nnoremap <silent> <Plug>HistoryCommands :History:<CR>
endif

if g:siefe_map_keys

"if !hasmapto('<Plug>(GitGutterPrevHunk)') && maparg('[c', 'n') ==# ''
"  nmap <buffer> [c <Plug>(GitGutterPrevHunk)
"
  if !hasmapto('<Plug>SiefeRG') && maparg('<leader>rg', 'n') ==# ''
    nmap <leader>rg <Plug>SiefeRG
  endif

  if !hasmapto('<Plug>SiefeRgWord') && maparg('<leader>rw', 'n') ==# ''
    nmap <leader>rw <Plug>SiefeRgWord
  endif

  if !hasmapto('<Plug>SiefeRgWORD') && maparg('<leader>rW', 'n') ==# ''
    nmap <leader>rW <Plug>SiefeRgWORD
  endif

  if !hasmapto('<Plug>SiefeRgLine') && maparg('<leader>rl', 'n') ==# ''
    nmap <leader>rl <Plug>SiefeRgLine
  endif

  if !hasmapto('<Plug>SiefeFiles') && maparg('<leader>rf', 'n') ==# ''
    nmap <leader>rf <Plug>SiefeFiles
  endif

  if !hasmapto('<Plug>SiefeRgVisual') && maparg('<leader>rg', 'x') ==# ''
    xmap <leader>rg <Plug>SiefeRgVisual
  endif

  if !hasmapto('<Plug>SiefeProjectRG') && maparg('<leader>Rg', 'n') ==# ''
    nmap <leader>Rg <Plug>SiefeProjectRG
  endif

  if !hasmapto('<Plug>SiefeProjectRgWord') && maparg('<leader>Rw', 'n') ==# ''
    nmap <leader>Rw <Plug>SiefeProjectRgWord
  endif

  if !hasmapto('<Plug>SiefeProjectRgWORD') && maparg('<leader>RW', 'n') ==# ''
    nmap <leader>RW <Plug>SiefeProjectRgWORD
  endif

  if !hasmapto('<Plug>SiefeProjectRgLines') && maparg('<leader>Rl', 'n') ==# ''
    nmap <leader>Rl <Plug>SiefeProjectRgLines
  endif

  if !hasmapto('<Plug>SiefeProjecFiles') && maparg('<leader>Rf', 'n') ==# ''
    nmap <leader>Rf <Plug>SiefeProjectFiles
  endif

  if !hasmapto('<Plug>SiefeProjectRgVisual') && maparg('<leader>Rg', 'x') ==# ''
    xmap <leader>Rg <Plug>SiefeProjectRgVisual
  endif

  if !hasmapto('<Plug>SiefeRgP') && maparg('<leader>rp', 'n') ==# ''
    nmap <leader>rp <Plug>SiefeRgP
  endif

  if !hasmapto('<Plug>SiefeProjectRgP') && maparg('<leader>Rp', 'n') ==# ''
    nmap <leader>Rp <Plug>SiefeProjectRgP
  endif

  if !hasmapto('<Plug>SiefeMarks') && maparg('<leader>m', 'n') ==# ''
    nmap <leader>m <Plug>SiefeMarks
  endif

  if !hasmapto('<Plug>SiefeJumps') && maparg('<leader>j', 'n') ==# ''
    nmap <leader>j <Plug>SiefeJumps
  endif

  if !hasmapto('<Plug>SiefeHistory') && maparg('<leader>hH', 'n') ==# ''
    nmap <leader>hH <Plug>SiefeHistory
  endif

  if !hasmapto('<Plug>SiefeProjectHistory') && maparg('<leader>hh', 'n') ==# ''
    nmap <leader>hh <Plug>SiefeProjectHistory
  endif

  if !hasmapto('<Plug>SiefeBuffers') && maparg('<leader>b', 'n') ==# ''
    nmap <leader>b <Plug>SiefeBuffers
  endif

  if !hasmapto('<Plug>SiefeToggleGitStatus') && maparg('<leader>gg', 'n') ==# ''
    nmap <leader>gg <Plug>SiefeToggleGitStatus
  endif

  if !hasmapto('<Plug>SiefeGitBufferLogg') && maparg('<leader>gl', 'n') ==# ''
    nmap <leader>gl <Plug>SiefeGitBufferLogg
  endif

  if !hasmapto('<Plug>SiefeGitBufferLogg') && maparg('<leader>gl', 'n') ==# ''
    nmap <leader>gl <Plug>SiefeGitBufferLogg
  endif

  if !hasmapto('<Plug>SiefeGitBufferLogVisual') && maparg('<leader>gl', 'x') ==# ''
    xmap <leader>gl <Plug>SiefeGitBufferLogVisual
  endif

  if !hasmapto('<Plug>SiefeGitLLog') && maparg('<leader>gL', 'x') ==# ''
    xmap <leader>gL <Plug>SiefeGitLLog
  endif

  if !hasmapto('<Plug>SiefeGitBufferLogWord') && maparg('<leader>gw', 'n') ==# ''
    nmap <leader>gw <Plug>SiefeGitBufferLogWord
  endif

  if !hasmapto('<Plug>SiefeGitBufferLogWORD') && maparg('<leader>gW', 'n') ==# ''
    nmap <leader>gW <Plug>SiefeGitBufferLogWORD
  endif

  if !hasmapto('<Plug>SiefeGitLogg') && maparg('<leader>Gl', 'n') ==# ''
    nmap <leader>Gl <Plug>SiefeGitLogg
  endif

  if !hasmapto('<Plug>SiefeGitLogWord') && maparg('<leader>Gw', 'n') ==# ''
    nmap <leader>Gw <Plug>SiefeGitLogWord
  endif

  if !hasmapto('<Plug>SiefeGitLogWORD') && maparg('<leader>GW', 'n') ==# ''
    nmap <leader>GW <Plug>SiefeGitLogWORD
  endif

  if exists(':Maps')
    if !hasmapto('<Plug>Maps') && maparg('<leader>M', 'n') ==# ''
      nmap <leader>M <Plug>Maps
    endif
  endif

  if exists(':History')
    if !hasmapto('<Plug>HistorySearch') && maparg('<leader>h/', 'n') ==# ''
      nmap <leader>h/ <Plug>HistorySearch
    endif

    if !hasmapto('<Plug>HistoryCommands') && maparg('<leader>h:', 'n') ==# ''
      nmap <leader>h: <Plug>HistoryCommands
    endif
  endif
endif
