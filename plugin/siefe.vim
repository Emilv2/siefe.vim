" Title:        Siefe, Fzf Sieve
" Description:  Plugin for meticulous searching in your git repository and history
" Maintainer:   Emil vanherp <emil@vanherp.me>

if exists("g:loaded_siefe")
    finish
endif
let g:loaded_siefe = 1

command! -nargs=* -bang RG call siefe#ripgrepfzf(<q-args>,  siefe#bufdir(), siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), <bang>0)
command! -nargs=* -bang Rv call siefe#ripgrepfzf(siefe#visual_selection(),  siefe#bufdir(), siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 1, siefe#bufdir(), <bang>0)
command! -nargs=* -bang RgWord call siefe#ripgrepfzf(expand("<cword>"), '.', siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), <bang>0)
command! -nargs=* -bang RgWORD call siefe#ripgrepfzf(expand("<cWORD>"), '.', siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), <bang>0)
command! -nargs=* -bang RgLine call siefe#ripgrepfzf(trim(getline('.')), '.', siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), <bang>0)

command! -nargs=* -bang ProjectRg call siefe#ripgrepfzf(<q-args>, siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), <bang>0)
command! -nargs=* -bang ProjectRgWord call siefe#ripgrepfzf(expand("<cword>"), siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), <bang>0)
command! -nargs=* -bang ProjectRgWORD call siefe#ripgrepfzf(expand("<cWORD>"), siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), <bang>0)
command! -nargs=* -bang ProjectRgLine call siefe#ripgrepfzf(trim(getline('.')), siefe#get_git_root(), siefe#get_git_basename(), 0, 0, 0, 0, 0, siefe#bufdir(), <bang>0)

command! -nargs=* -bang Gp    call siefe#gitlogfzf(<q-args>, [], [], [], 0, 0, siefe#bufdir(), 0, <bang>0)
command! -nargs=* -bang Gv    call siefe#gitlogfzf(siefe#visual_selection(), [], [], [], 0, 0, <bang>0)
command! -nargs=* -bang GWord call siefe#gitlogfzf(expand("<cword>"), [], [], [], 0, 0, <bang>0)
command! -nargs=* -bang GWORD call siefe#gitlogfzf(expand("<cWORD>"), [], [], [], 0, 0, <bang>0)
command! -nargs=* -bang Gline call siefe#gitlogfzf(expand("<cword>"), [], [], [], 0, 0, <bang>0)
