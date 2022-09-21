" Title:        Siefe, Fzf Sieve
" Description:  Plugin for meticulous searching in your git repository and history
" Maintainer:   Emil vanherp <emil@vanherp.me>

if exists("g:loaded_siefe")
    finish
endif
let g:loaded_siefe = 1


command! -nargs=* -bang RG call RipgrepFzf(<q-args>, getcwd(), s:get_relative_git_or_pwd(), 0, 0, 0, 0, 0, getcwd(), <bang>0)
command! -nargs=* -bang Rv call RipgrepFzf(VisualSelection(), getcwd(), s:get_relative_git_or_pwd(), 0, 0, 0, 0, 1, getcwd(), <bang>0)
command! -nargs=* -bang RgWord call RipgrepFzf(expand("<cword>"), '.', s:get_relative_git_or_pwd(), 0, 0, 0, 0, 0, getcwd(), <bang>0)
command! -nargs=* -bang RgWORD call RipgrepFzf(expand("<cWORD>"), '.', s:get_relative_git_or_pwd(), 0, 0, 0, 0, 0, getcwd(), <bang>0)
command! -nargs=* -bang RgLine call RipgrepFzf(trim(getline('.')), '.', s:get_relative_git_or_pwd(), 0, 0, 0, 0, 0, getcwd(), <bang>0)

command! -nargs=* -bang ProjectRg call RipgrepFzf(<q-args>, s:get_git_root(), s:get_git_basename_or_pwd(), 0, 0, 0, 0, 0, getcwd(), <bang>0)
command! -nargs=* -bang ProjectRgWord call RipgrepFzf(expand("<cword>"), s:get_git_root(), s:get_git_basename_or_pwd(), 0, 0, 0, 0, 0, getcwd(), <bang>0)
command! -nargs=* -bang ProjectRgWORD call RipgrepFzf(expand("<cWORD>"), s:get_git_root(), s:get_git_basename_or_pwd(), 0, 0, 0, 0, 0, getcwd(), <bang>0)
command! -nargs=* -bang ProjectRgLine call RipgrepFzf(trim(getline('.')), s:get_git_root(), s:get_git_basename(), 0, 0, 0, 0, 0, getcwd(), <bang>0)

command! -nargs=* -bang Gp    call GitPickaxeFzf(<q-args>, [], [], [], 0, 0, <bang>0)
command! -nargs=* -bang Gv    call GitPickaxeFzf(VisualSelection(), '', 0, 0, <bang>0)
command! -nargs=* -bang GWord call GitPickaxeFzf(expand("<cword>"), '', 0, 0, <bang>0)
command! -nargs=* -bang GWORD call GitPickaxeFzf(expand("<cWORD>"), '', 0, 0, <bang>0)
command! -nargs=* -bang Gline call GitPickaxeFzf(expand("<cword>"), '', 0, 0, <bang>0)
