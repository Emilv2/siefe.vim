" Title:        Siefe, Fzf Sieve
" Description:  Plugin for meticulous searching in your git repository and history
" Maintainer:   Emil vanherp <emil@vanherp.me>

if exists('g:loaded_siefe')
    finish
endif
let g:loaded_siefe = 1

command! -nargs=* -bang SiefeRg call siefe#ripgrepfzf(<q-args>,  siefe#bufdir(), siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), "", <bang>0)
command! -nargs=* -bang SiefeRgVisual call siefe#ripgrepfzf(siefe#visual_selection(),  siefe#bufdir(), siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 1, siefe#bufdir(), "", <bang>0)
command! -nargs=* -bang SiefeRgWord call siefe#ripgrepfzf(expand("<cword>"), '.', siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), "", <bang>0)
command! -nargs=* -bang SiefeRgWORD call siefe#ripgrepfzf(expand("<cWORD>"), '.', siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), "", <bang>0)
command! -nargs=* -bang SiefeRgLine call siefe#ripgrepfzf(trim(getline('.')), '.', siefe#get_relative_git_or_bufdir(), 0, 0, 0, 0, 1, siefe#bufdir(), "", <bang>0)

command! -nargs=* -bang SiefeProjectRg call siefe#ripgrepfzf(<q-args>, siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), "", <bang>0)
command! -nargs=* -bang SiefeProjectRgVisual call siefe#ripgrepfzf(siefe#visual_selection(), siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), 0, 0, 0, 0, 1, siefe#bufdir(), "", <bang>0)
command! -nargs=* -bang SiefeProjectRgWord call siefe#ripgrepfzf(expand("<cword>"), siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), "", <bang>0)
command! -nargs=* -bang SiefeProjectRgWORD call siefe#ripgrepfzf(expand("<cWORD>"), siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), 0, 0, 0, 0, 0, siefe#bufdir(), "", <bang>0)
command! -nargs=* -bang SiefeProjectRgLine call siefe#ripgrepfzf(trim(getline('.')), siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), 0, 0, 0, 0, 1, siefe#bufdir(), "", <bang>0)

command! -nargs=* -bang SiefeGitLog     call siefe#gitlogfzf(<q-args>, [], [], [], 0, 0, [], 0, 0, '', <bang>0)
command! -nargs=* -bang SiefeGitLogWord call siefe#gitlogfzf(expand("<cword>"), [], [], [], 0, 0, [], 0, 0, '', <bang>0)
command! -nargs=* -bang SiefeGitLogWORD call siefe#gitlogfzf(expand("<cWORD>"), [], [], [], 0, 0, [], 0, 0, '', <bang>0)
command! -nargs=* -bang SiefeGitLogLine call siefe#gitlogfzf(trim(getline('.')), [], [], [], 0, 0, [], 0, 0, '', <bang>0)
