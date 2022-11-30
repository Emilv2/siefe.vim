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
            \ })

command! -nargs=* -bang SiefeRgVisual call siefe#ripgrepfzf(
            \ <bang>0,
            \ siefe#bufdir(),
            \ {
            \  'query' : siefe#visual_selection(),
            \  'fixed_strings' : 1,
            \ })

command! -nargs=* -bang SiefeRgWord call siefe#ripgrepfzf(
            \ <bang>0,
            \ siefe#bufdir(),
            \ {
            \  'query' : expand('<cword>'),
            \ })

command! -nargs=* -bang SiefeRgWORD call siefe#ripgrepfzf(
            \ <bang>0,
            \ siefe#bufdir(),
            \ {
            \  'query' : expand('<cWORD>'),
            \ })

command! -nargs=* -bang SiefeRgLine call siefe#ripgrepfzf(
            \ <bang>0,
            \ siefe#bufdir(),
            \ {
            \  'query' : trim(getline('.')),
            \ })

command! -nargs=* -bang SiefeRgFiles call siefe#ripgrepfzf(
            \ <bang>0,
            \ siefe#bufdir(),
            \ {
            \  'query' : <q-args>,
            \  'files' : '//',
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

command! -nargs=* -bang SiefeProjectRgWord call siefe#ripgrepfzf(expand(
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

command! -nargs=* -bang SiefeProjectRgFiles call siefe#ripgrepfzf(
            \ <bang>0,
            \ siefe#get_git_root(),
            \ {
            \  'query' : <q-args>,
            \  'prompt' : siefe#get_git_basename_or_bufdir(),
            \  'files' : '//',
            \ })

command! -nargs=* -bang SiefeBuffersRg call siefe#ripgrepfzf(
            \ <bang>0,
            \ siefe#get_git_root(),
            \ {
            \  'query' : <q-args>,
            \  'prompt' : siefe#get_git_basename_or_bufdir(),
            \  'paths' : map(filter(copy(getbufinfo()), 'v:val.listed'),  'fnamemodify(v:val.name, ":p:~:.")'),
            \ })

command! -nargs=* -bang SiefeGitLog     call siefe#gitlogfzf(<q-args>, '', '', [], 0, 0, [], 0, 0, '', [], <bang>0)
command! -nargs=* -bang SiefeGitLogWord call siefe#gitlogfzf(expand("<cword>"), '', '', [], 0, 0, [], 0, 0, '', [], <bang>0)
command! -nargs=* -bang SiefeGitLogWORD call siefe#gitlogfzf(expand("<cWORD>"), '', '', [], 0, 0, [], 0, 0, '', [], <bang>0)
command! -nargs=* -bang SiefeGitLogLine call siefe#gitlogfzf(trim(getline('.')), '', '', [], 0, 0, [], 0, 0, '', [], <bang>0)
command! -nargs=* -bang SiefeGitLLog    call siefe#gitlogfzf(<q-args>, '', '', [], 0, 0, [expand('%')], 0, 0, '', siefe#visual_line_nu(), <bang>0)
