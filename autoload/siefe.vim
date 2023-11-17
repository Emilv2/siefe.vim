scriptencoding utf-8

let s:min_version = '0.35.0'
let s:is_win = has('win32') || has('win64')
let s:is_wsl_bash = s:is_win && (exepath('bash') =~? 'Windows[/\\]system32[/\\]bash.exe$')
let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:p:h:h').'/bin/'
let s:bin = {
\ 'pickaxe_diff': s:bin_dir.'pickaxe-diff',
\ 'git_SG': s:bin_dir.'git_SG',
\ 'preview': s:bin_dir.'preview',
\ 'logger': s:bin_dir.'logger',
\ }
let s:TYPE = {'dict': type({}), 'funcref': type(function('call')), 'string': type(''), 'list': type([])}
if s:is_win
  if has('nvim')
    let s:bin.preview = split(system('for %A in ("'.s:bin.preview.'") do @echo %~sA'), "\n")[0]
  else
    let preview_path = s:is_wsl_bash
      \ ? substitute(s:bin.preview, '^\([A-Z]\):', '/mnt/\L\1', '')
      \ : fnamemodify(s:bin.preview, ':8')
    let s:bin.preview = substitute(preview_path, '\', '/', 'g')
  endif
endif

function! s:prettify_help(key) abort
    return s:magenta(toupper(a:key), 'Special')
endfunction

let s:ansi = {'black': 30, 'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35, 'cyan': 36}

function! s:csi(color, fg) abort
  let prefix = a:fg ? '38;' : '48;'
  if a:color[0] ==# '#'
    return prefix.'2;'.join(map([a:color[1:2], a:color[3:4], a:color[5:6]], 'str2nr(v:val, 16)'), ';')
  endif
  return prefix.'5;'.a:color
endfunction

function! s:ansi(str, group, default, ...) abort
  let fg = s:get_color('fg', a:group)
  let bg = s:get_color('bg', a:group)
  let color = (empty(fg) ? s:ansi[a:default] : s:csi(fg, 1)) .
        \ (empty(bg) ? '' : ';'.s:csi(bg, 0))
  return printf("\x1b[%s%sm%s\x1b[m", color, a:0 ? ';1' : '', a:str)
endfunction

function! s:magenta(str, ...) abort
  return s:ansi(a:str, get(a:, 1, ''), 'magenta')
endfunction

function! s:blue(str, ...) abort
  return s:ansi(a:str, get(a:, 1, ''), 'blue')
endfunction

function! s:red(str, ...) abort
  return s:ansi(a:str, get(a:, 1, ''), 'red')
endfunction

function! s:green(str, ...) abort
  return s:ansi(a:str, get(a:, 1, ''), 'green')
endfunction

function! s:yellow(str, ...) abort
  return s:ansi(a:str, get(a:, 1, ''), 'yellow')
endfunction

function! s:fill_quickfix(list, ...) abort
  if len(a:list) > 1
    call setqflist(a:list)
    copen
    wincmd p
    if a:0
      execute a:1
    endif
  endif
endfunction

function! s:fill_loc(list, ...) abort
  if len(a:list) > 1
    call setloclist(0, a:list)
    lopen
    wincmd p
    if a:0
      execute a:1
    endif
  endif
endfunction

function! s:yank_to_register(data) abort
  let @" = a:data
  silent! let @* = a:data
  silent! let @+ = a:data
endfunction

function! s:prettify_header(key, text) abort
  let char = split(a:key, '-')[-1]
  if char == a:text[0]
    return s:magenta(toupper(a:key), 'Special') . ' ' . a:text
  else
    return s:magenta(toupper(a:key), 'Special') . ' ' . a:text[0] . substitute(a:text[1:], char, "\e[3m".char."\e[m", '')
  endif
endfunction

function! s:get_color(attr, ...) abort
  let gui = has('termguicolors') && &termguicolors
  let fam = gui ? 'gui' : 'cterm'
  let pat = gui ? '^#[a-f0-9]\+' : '^[0-9]\+$'
  for group in a:000
    let code = synIDattr(synIDtrans(hlID(group)), a:attr, fam)
    if code =~? pat
      return code
    endif
  endfor
  return ''
endfunction



function! s:preview_help(preview_keys) abort
  let f_keys = filter(copy(a:preview_keys), 'v:val[0] ==? "f"')
  let non_f_keys = filter(copy(a:preview_keys), 'v:val[0] !=? "f"')
  let f_ints = sort(map(f_keys, 'str2nr(v:val[1:])'), 'n')
  let last_val = f_ints[0]
  let result = ''
  let val_start = f_ints[0]
  for val in f_ints[1:]
    if val != last_val + 1
      if val_start != last_val
        let result .= 'f' . val_start . '-' . last_val . ', '
      else
        let result .= 'f'. last_val . ', '
      endif
      let val_start = val
    endif
    let last_val = val
  endfor
  let result .= 'f' . val_start . '-' . last_val
  return result . join(map(non_f_keys, '", " . v:val'), '')
endfunction


""" ripgrep < 13 does not support setting the match separator
let _ = system('rg --help | grep -- "--field-match-separator"')
let s:delimiter = v:shell_error ? ':' : '//'
let s:field_match_separator = v:shell_error ? '' : '--field-match-separator="\x1b[9;31;31m//\x1b[0m"'

let s:checked = 0

function! s:check_requirements() abort
  if s:checked
    return
  endif

  if !exists('*fzf#run')
    throw 'fzf#run function not found. You also need Vim plugin from the main fzf repository (i.e. junegunn/fzf *and* junegunn/fzf.vim)'
  endif
  if !exists('*fzf#exec')
    throw 'fzf#exec function not found. You need to upgrade Vim plugin from the main fzf repository ("junegunn/fzf")'
  endif
  let gitlog_dups = s:detect_dups(s:gitlog_keys)
  if gitlog_dups !=# ''
    throw 'duplicates found in `siefe_gitlog_*_key`s :'. gitlog_dups
  endif
  let rg_dups = s:detect_dups(s:rg_keys)
  if rg_dups !=# ''
    throw 'duplicates found in `siefe_rg_*_key`s :'. rg_dups
  endif
  let fd_dups = s:detect_dups(s:fd_keys)
  if fd_dups !=# ''
    throw 'duplicates found in `siefe_fd_*_key`s :'. fd_dups
  endif


  let s:checked = !empty(fzf#exec(s:min_version))
endfunction

let s:data_path = expand($XDG_DATA_HOME) !=# '' ?  expand($XDG_DATA_HOME) . '/siefe.vim' : expand($HOME) . '/.local/share/siefe.vim'
if !isdirectory(s:data_path)
  call mkdir(s:data_path, 'p')
endif

let s:logger = s:bin.logger . ' '. s:data_path . '/error_log '

""" load configuration options
let g:siefe_loclist = get(g:, 'siefe_loclist', 0)
let g:siefe_rg_loclist = get(g:, 'siefe_rg_loclist', g:siefe_loclist)
let g:siefe_gitlog_loclist = get(g:, 'siefe_gitlog_loclist', g:siefe_loclist)
let g:siefe_history_loclist = get(g:, 'siefer_history_loclist', g:siefe_loclist)
let g:siefe_marks_loclist = get(g:, 'siefe_marks_loclist', g:siefe_loclist)

let g:siefe_delta_options = get(g:, 'siefe_delta_options', '--keep-plus-minus-markers') . ' ' . get(g:, 'siefe_delta_extra_options', '')
let g:siefe_bat_options = get(g:, 'siefe_bat_options', '--style=numbers,changes') . ' ' . get(g:, 'siefe_bat_extra_options', '')

let g:siefe_abort_key = get(g:, 'siefe_abort_key', 'esc')
let g:siefe_next_history_key = get(g:, 'siefe_next_history_key', 'ctrl-n')
let g:siefe_previous_history_key = get(g:, 'siefe_previous_history_key', 'ctrl-p')
let g:siefe_up_key = get(g:, 'siefe_up_key', 'ctrl-k')
let g:siefe_down_key = get(g:, 'siefe_down_key', 'ctrl-j')
let g:siefe_accept_key = get(g:, 'siefe_accept_key', 'ctrl-m')
let g:siefe_toggle_up_key = get(g:, 'siefe_toggle_up_key', 'tab')
let g:siefe_toggle_down_key = get(g:, 'siefe_toggle_down_key', 'shift-tab')
let g:siefe_help_key = get(g:, 'siefe_help_key', 'f9')

let s:common_keys = [
  \ g:siefe_abort_key,
  \ g:siefe_next_history_key,
  \ g:siefe_previous_history_key,
  \ g:siefe_up_key,
  \ g:siefe_down_key,
  \ g:siefe_accept_key,
  \ g:siefe_toggle_up_key,
  \ g:siefe_toggle_down_key,
  \ g:siefe_help_key,
\ ]

let g:siefe_split_key = get(g:, 'siefe_split_key', 'ctrl-]')
let g:siefe_vsplit_key = get(g:, 'siefe_vsplit_key', 'ctrl-\')
let g:siefe_tab_key = get(g:, 'siefe_tab_key', 'alt-enter')
let g:siefe_vdiffsplit_key = get(g:, 'siefe_vdiffsplit_key', 'alt-d')

let s:common_window_actions = {
  \ g:siefe_vdiffsplit_key : 'vert diffsplit',
  \ g:siefe_tab_key : 'tab split',
  \ g:siefe_split_key : 'split',
  \ g:siefe_vsplit_key : 'vsplit',
\ }

let s:fugitive_window_actions = {
  \ 'tab split' : 'Gtabedit',
  \ 'split' : 'Gsplit',
  \ 'vsplit' : 'Gvsplit',
\ }

let s:common_window_keys = keys(s:common_window_actions)
let s:common_window_expect_keys = join(filter(keys(s:common_window_actions), '!empty(v:val)'), ',')
let s:common_window_help = join(map(filter(keys(s:common_window_actions), '!empty(v:val)'), 's:prettify_help(v:val) . " " . get(s:common_window_actions, v:val)'), ' ╱ ')

let g:siefe_preview_hide_threshold = str2nr(get(g:, 'siefe_preview_hide_threshold', 80))
let g:siefe_default_preview_size = str2nr(get(g:, 'siefe_default_preview_size', 50))
let g:siefe_2nd_preview_size = str2nr(get(g:, 'siefe_2nd_preview_size', 80))


let g:siefe_rg_toggle_fzf_key = get(g:, 'siefe_rg_toggle_fzf_key', 'ctrl-r')
let g:siefe_rg_rgfzf_key = get(g:, 'siefe_rg_rgfzf_key', 'alt-f')
let g:siefe_rg_files_key = get(g:, 'siefe_rg_files_key', 'ctrl-f')
let g:siefe_rg_type_key = get(g:, 'siefe_rg_type_key', 'ctrl-t')
let g:siefe_rg_type_not_key = get(g:, 'siefe_rg_type_not_key', 'ctrl-^')
let g:siefe_rg_word_key = get(g:, 'siefe_rg_word_key', 'ctrl-w')
let g:siefe_rg_case_key = get(g:, 'siefe_rg_case_key', 'ctrl-s')
let g:siefe_rg_hidden_key = get(g:, 'siefe_rg_hidden_key', 'alt-.')
let g:siefe_rg_no_ignore_key = get(g:, 'siefe_rg_no_ignore_key', 'ctrl-u')
let g:siefe_rg_fixed_strings_key = get(g:, 'siefe_rg_fixed_strings_key', 'ctrl-x')
let g:siefe_rg_max_1_key = get(g:, 'siefe_rg_max_1_key', 'ctrl-a')
let g:siefe_rg_search_zip_key = get(g:, 'siefe_rg_search_zip_key', 'alt-z')
let g:siefe_rg_text_key = get(g:, 'siefe_rg_text_key', 'alt-t')
let g:siefe_rg_dir_key = get(g:, 'siefe_rg_dir_key', 'ctrl-d')
let g:siefe_rg_buffers_key = get(g:, 'siefe_rg_buffers_key', 'ctrl-b')
let g:siefe_rg_yank_key = get(g:, 'siefe_rg_yank_key', 'ctrl-y')
let g:siefe_rg_history_key = get(g:, 'siefe_rg_history_key', 'ctrl-h')

let g:siefe_rg_preview_key = get(g:, 'siefe_rg_preview_key', 'f1')
let g:siefe_rg_fast_preview_key = get(g:, 'siefe_rg_fast_preview_key', 'f2')
let g:siefe_rg_faster_preview_key = get(g:, 'siefe_rg_faster_preview_key', 'f3')

let s:rg_preview_keys = [
  \ g:siefe_rg_preview_key,
  \ g:siefe_rg_fast_preview_key,
  \ g:siefe_rg_faster_preview_key,
\ ]

let s:bat_command = executable('batcat') ? 'batcat' : executable('bat') ? 'bat' : ''
let s:fd_command = executable('fdfind') ? 'echo -e "' . s:blue('..') . '"; fdfind' : executable('fd') ? 'echo -e "' . s:blue('..') . '"; fd' : ''
let s:files_preview_command = s:bat_command !=# '' ? s:bin.preview . ' {} '. s:bat_command . ' --color=always --pager=never ' . g:siefe_bat_options . ' -- ' : s:bin.preview . ' {} cat'
let s:rg_preview_command = s:bat_command !=# '' ? s:bin.preview . ' {1} ' . s:bat_command . ' --color=always --highlight-line={2} --pager=never ' . g:siefe_bat_options . ' -- ' : s:bin.preview . ' {1} cat'
let s:rg_fast_preview_command = s:bin.preview . ' {1} cat | awk ' . "'" . '{ if (NR == {2} ) { gsub ("/\xb1[[0-9 ; ]*m/", "& \x1b[7m" ) ; printf( "\x1b[7m%s\n\x1b[m", $0) ; } else printf("\x1b[m%s\n", $0) ; }' . "'"
let s:rg_faster_preview_command = s:bin.preview . ' {1} cat'

let s:rg_preview_commands = [
  \ s:rg_preview_command,
  \ s:rg_fast_preview_command,
  \ s:rg_faster_preview_command,
\ ]

let g:siefe_history_preview_key = get(g:, 'siefe_history_preview_key', g:siefe_rg_preview_key)
let g:siefe_history_fast_preview_key = get(g:, 'siefe_history_fast_preview_key', g:siefe_rg_fast_preview_key)
let g:siefe_history_faster_preview_key = get(g:, 'siefe_history_faster_preview_key', g:siefe_rg_faster_preview_key)

let s:history_preview_keys = [
  \ g:siefe_history_preview_key,
  \ g:siefe_history_fast_preview_key,
  \ g:siefe_history_faster_preview_key,
\ ]

let s:history_preview_command = s:bat_command !=# '' ? s:bin.preview . ' {2} ' . s:bat_command . ' --color=always --highlight-line={1} --pager=never ' . g:siefe_bat_options . ' -- ' : s:bin.preview . ' {2} cat'
let s:history_fast_preview_command = s:bin.preview . ' {2} cat | awk ' . "'" . '{ if (NR == {1} ) { gsub ("/\xb1[[0-9 ; ]*m/", "& \x1b[7m" ) ; printf( "\x1b[7m%s\n\x1b[m", $0) ; } else printf("\x1b[m%s\n", $0) ; }' . "'"
let s:history_faster_preview_command = s:bin.preview . ' {2} cat'

let s:history_preview_commands = [
  \ s:history_preview_command,
  \ s:history_fast_preview_command,
  \ s:history_faster_preview_command,
\ ]


let s:rg_keys = [
  \ g:siefe_rg_toggle_fzf_key,
  \ g:siefe_rg_rgfzf_key,
  \ g:siefe_rg_files_key,
  \ g:siefe_rg_type_key,
  \ g:siefe_rg_type_not_key,
  \ g:siefe_rg_word_key,
  \ g:siefe_rg_case_key,
  \ g:siefe_rg_hidden_key,
  \ g:siefe_rg_no_ignore_key,
  \ g:siefe_rg_fixed_strings_key,
  \ g:siefe_rg_max_1_key,
  \ g:siefe_rg_search_zip_key,
  \ g:siefe_rg_text_key,
  \ g:siefe_rg_dir_key,
  \ g:siefe_rg_buffers_key,
  \ g:siefe_rg_yank_key,
  \ g:siefe_rg_history_key,
\ ] + s:rg_preview_commands
  \ + s:common_keys
  \ + s:common_window_keys

let g:siefe_toggle_preview_key = get(g:, 'siefe_toggle_preview_key', 'ctrl-/')

let g:siefe_rg_fzf_default = get(g:, 'siefe_rg_fzf_default', 0)
let g:siefe_rg_default_preview_command = get(g:, 'siefe_rg_default_preview_command', 0)

let g:siefe_history_default_preview_command = get(g:, 'siefe_history_default_preview_command', g:siefe_rg_default_preview_command)

let g:siefe_gitlog_ignore_case_key = get(g:, 'siefe_gitlog_ignore_case_key', 'alt-i')
let g:siefe_gitlog_vdiffsplit_key = get(g:, 'siefe_gitlog_vdiffsplit_key', 'ctrl-v')
let g:siefe_gitlog_type_key = get(g:, 'siefe_gitlog_type_key', 'ctrl-t')
let g:siefe_gitlog_author_key = get(g:, 'siefe_gitlog_author_key', 'ctrl-a')
let g:siefe_gitlog_branch_key = get(g:, 'siefe_gitlog_branch_key', 'ctrl-b')
let g:siefe_gitlog_not_branch_key = get(g:, 'siefe_gitlog_not_branch_key', 'ctrl-^')
let g:siefe_gitlog_sg_key = get(g:, 'siefe_gitlog_sg_key', 'ctrl-e')
let g:siefe_gitlog_fzf_key = get(g:, 'siefe_gitlog_fzf_key', 'ctrl-f')
let g:siefe_gitlog_s_key = get(g:, 'siefe_gitlog_s_key', 'ctrl-s')
let g:siefe_gitlog_pickaxe_regex_key = get(g:, 'siefe_gitlog_pickaxe_regex_key', 'ctrl-x')
let g:siefe_gitlog_dir_key = get(g:, 'siefe_gitlog_dir_key', 'ctrl-d')
let g:siefe_gitlog_follow_key = get(g:, 'siefe_gitlog_follow_key', 'ctrl-o')
let g:siefe_gitlog_switch_key = get(g:, 'siefe_gitlog_switch_key', 'ctrl-s')

let g:siefe_gitlog_preview_0_key = get(g:, 'siefe_gitlog_preview_0_key', 'f1')
let g:siefe_gitlog_preview_1_key = get(g:, 'siefe_gitlog_preview_1_key', 'f2')
let g:siefe_gitlog_preview_2_key = get(g:, 'siefe_gitlog_preview_2_key', 'f3')
let g:siefe_gitlog_preview_3_key = get(g:, 'siefe_gitlog_preview_3_key', 'f4')
let g:siefe_gitlog_preview_4_key = get(g:, 'siefe_gitlog_preview_4_key', 'f5')

let g:siefe_gitlog_default_preview_command = get(g:, 'siefe_gitlog_default_preview_command', 0)

let s:gitlog_preview_keys = [
  \ g:siefe_gitlog_preview_0_key,
  \ g:siefe_gitlog_preview_1_key,
  \ g:siefe_gitlog_preview_2_key,
  \ g:siefe_gitlog_preview_3_key,
  \ g:siefe_gitlog_preview_4_key,
\ ]

let s:gitlog_keys = [
  \ g:siefe_gitlog_ignore_case_key,
  \ g:siefe_gitlog_vdiffsplit_key,
  \ g:siefe_gitlog_type_key,
  \ g:siefe_gitlog_author_key,
  \ g:siefe_gitlog_branch_key,
  \ g:siefe_gitlog_not_branch_key,
  \ g:siefe_gitlog_sg_key,
  \ g:siefe_gitlog_fzf_key,
  \ g:siefe_gitlog_s_key,
  \ g:siefe_gitlog_pickaxe_regex_key,
  \ g:siefe_gitlog_dir_key,
  \ g:siefe_gitlog_follow_key,
\ ] + s:gitlog_preview_keys
  \ + s:common_keys

let g:siefe_gitbranch_preview_0_key = get(g:, 'siefe_gitbranch_preview_0_key', 'f1')
let g:siefe_gitbranch_preview_1_key = get(g:, 'siefe_gitbranch_preview_1_key', 'f2')
let g:siefe_gitbranch_preview_2_key = get(g:, 'siefe_gitbranch_preview_2_key', 'f3')
let g:siefe_gitbranch_preview_3_key = get(g:, 'siefe_gitbranch_preview_3_key', 'f4')

let g:siefe_fd_hidden_key = get(g:, 'siefe_fd_hidden_key', 'ctrl-h')
let g:siefe_fd_no_ignore_key = get(g:, 'siefe_fd_no_ignore_key', 'ctrl-u')
let g:siefe_fd_git_root_key = get(g:, 'siefe_fd_git_root_key', 'ctrl-r')
let g:siefe_fd_project_root_key = get(g:, 'siefe_fd_project_root_key', 'ctrl-o')
let g:siefe_fd_search_git_root_key = get(g:, 'siefe_fd_search_git_root_key', 'ctrl-s')
let g:siefe_fd_search_project_root_key = get(g:, 'siefe_fd_search_project_root_key', 'ctrl-e')

let s:fd_keys = [
  \ g:siefe_fd_hidden_key,
  \ g:siefe_fd_no_ignore_key,
  \ g:siefe_fd_git_root_key,
  \ g:siefe_fd_project_root_key,
  \ g:siefe_fd_search_git_root_key,
  \ g:siefe_fd_search_project_root_key,
\ ]
  \ + s:common_keys


let g:siefe_fd_project_root_env = get(g:, 'siefe_fd_git_root_env', '')

let g:siefe_branches_all_key = get(g:, 'siefe_branches_all_key', 'ctrl-a')
let g:siefe_branches_switch_key = get(g:, 'siefe_branches_switch_key', 'ctrl-o')
let g:siefe_branches_merge_key = get(g:, 'siefe_branches_rebase_interactive_key', 'ctrl-e')
let g:siefe_branches_rebase_interactive_key = get(g:, 'siefe_branches_rebase_interactive_key', 'ctrl-r')

let g:siefe_gitlog_default_G = get(g:, 'siefe_gitlog_default_G', 0)
let g:siefe_gitlog_default_regex = get(g:, 'siefe_gitlog_default_regex', 0)
let g:siefe_gitlog_default_follow = get(g:, 'siefe_gitlog_default_follow', 0)
let g:siefe_gitlog_default_ignore_case = get(g:, 'siefe_gitlog_default_ignore_case', 0)

let g:siefe_rg_default_word = get(g:, 'siefe_rg_default_word', 0)
let g:siefe_rg_default_case_sensitive = get(g:, 'siefe_rg_default_case_sensitive', 1)
let g:siefe_rg_default_hidden = get(g:, 'siefe_rg_default_hidden', 0)
let g:siefe_rg_default_no_ignore = get(g:, 'siefe_rg_default_no_ignore', 0)
let g:siefe_rg_default_fixed_strings = get(g:, 'siefe_rg_default_fixed_strings', 0)
let g:siefe_rg_default_max_1 = get(g:, 'siefe_rg_default_max_1', 0)
let g:siefe_rg_default_search_zip = get(g:, 'siefe_rg_default_search_zip', 0)
let g:siefe_rg_default_text = get(g:, 'siefe_rg_default_text', 0)

let g:siefe_history_git_key = get(g:, 'siefe_history_git_key', 'ctrl-p')
let g:siefe_history_buffers_key = get(g:, 'siefe_history_buffers_key', 'ctrl-b')
let g:siefe_history_files_key = get(g:, 'siefe_history_files_key', 'ctrl-l')
let g:siefe_history_rg_key = get(g:, 'siefe_history_rg_key', 'ctrl-s')

let g:siefe_stash_apply_key = get(g:, 'siefe_stash_apply_key', 'ctrl-a')
let g:siefe_stash_pop_key = get(g:, 'siefe_stash_pop_key', 'ctrl-p')
let g:siefe_stash_drop_key = get(g:, 'siefe_stash_drop_key', 'del')
let g:siefe_stash_ignore_case_key = get(g:, 'siefe_stash_ignore_case_key', 'alt-i')
let g:siefe_stash_sg_key = get(g:, 'siefe_stash_sg_key', 'ctrl-e')
let g:siefe_stash_fzf_key = get(g:, 'siefe_stash_fzf_key', 'ctrl-f')
let g:siefe_stash_s_key = get(g:, 'siefe_stash_s_key', 'ctrl-s')
let g:siefe_stash_pickaxe_regex_key = get(g:, 'siefe_stash_pickaxe_regex_key', 'ctrl-x')

let g:siefe_stash_preview_0_key = get(g:, 'siefe_stash_preview_0_key', 'f1')
let g:siefe_stash_preview_1_key = get(g:, 'siefe_stash_preview_1_key', 'f2')
let g:siefe_stash_preview_2_key = get(g:, 'siefe_stash_preview_2_key', 'f3')
let g:siefe_stash_preview_3_key = get(g:, 'siefe_stash_preview_3_key', 'f4')
let g:siefe_stash_preview_4_key = get(g:, 'siefe_stash_preview_4_key', 'f5')

let g:siefe_stash_default_preview_command = get(g:, 'siefe_stash_default_preview_command', 0)

let g:siefe_buffers_delete_key = get(g:, 'siefe_buffers_delete_key', 'del')
let g:siefe_buffers_git_key = get(g:, 'siefe_buffers_git_key', 'ctrl-p')
let g:siefe_buffers_history_key = get(g:, 'siefe_buffers_history_key', 'ctrl-h')

let g:siefe_buffers_default_preview_command = get(g:, 'siefe_buffers_default_preview_command', g:siefe_rg_default_preview_command)
let g:siefe_buffers_preview_key = get(g:, 'siefe_buffers_preview_key', g:siefe_rg_preview_key)
let g:siefe_buffers_fast_preview_key = get(g:, 'siefe_buffers_fast_preview_key', g:siefe_rg_fast_preview_key)

let s:buffers_preview_command = s:bat_command !=# '' ? s:bin.preview . ' {1} ' . s:bat_command . ' --color=always --highlight-line={2} --pager=never ' . g:siefe_bat_options . ' -- ' : s:bin.preview . ' {1} cat'
let s:buffers_fast_preview_command = s:bin.preview . ' {1} cat'

let s:buffers_preview_commands = [
  \ s:buffers_preview_command,
  \ s:buffers_fast_preview_command,
\ ]

let g:siefe_marks_delete_key = get(g:, 'siefe_marks_delete_key', 'del')
let g:siefe_marks_yank_key = get(g:, 'siefe_marks_yank_key', 'ctrl-y')
let g:siefe_marks_default_preview_command = get(g:, 'siefe_marks_default_preview_command', g:siefe_rg_default_preview_command)
let g:siefe_marks_preview_key = get(g:, 'siefe_marks_preview_key', g:siefe_rg_preview_key)
let g:siefe_marks_fast_preview_key = get(g:, 'siefe_marks_fast_preview_key', g:siefe_rg_fast_preview_key)

let s:marks_preview_command = s:bat_command !=# '' ? s:bin.preview . ' {2} ' . s:bat_command . ' --color=always --highlight-line={3} --pager=never ' . g:siefe_bat_options . ' -- ' : s:bin.preview . ' {2} cat'
let s:marks_fast_preview_command = s:bin.preview . ' {2} cat'

let s:marks_preview_commands = [
  \ s:marks_preview_command,
  \ s:marks_fast_preview_command,
\ ]

let g:siefe_jumps_yank_key = get(g:, 'siefe_jumps_yank_key', 'ctrl-y')
let g:siefe_jumps_preview_key = get(g:, 'siefe_jumps_preview_key', g:siefe_rg_preview_key)
let g:siefe_jumps_default_preview_command = get(g:, 'siefe_jumps_default_preview_command', g:siefe_rg_default_preview_command)
let g:siefe_jumps_fast_preview_key = get(g:, 'siefe_jumps_fast_preview_key', g:siefe_rg_fast_preview_key)
let g:siefe_jumps_clear_key = get(g:, 'siefe_jumps_clear_key', 'del')

let s:jumps_preview_command = s:bat_command !=# '' ? s:bin.preview . ' {1} ' . s:bat_command . ' --color=always --highlight-line={2} --pager=never ' . g:siefe_bat_options . ' -- ' : s:bin.preview . ' {1} cat'
let s:jumps_fast_preview_command = s:bin.preview . ' {1} cat'

let s:jumps_preview_commands = [
  \ s:jumps_preview_command,
  \ s:jumps_fast_preview_command,
\ ]

let g:siefe_registers_paste_key = get(g:, 'siefe_registers_paste_key', 'ctrl-p')
let g:siefe_registers_edit_key = get(g:, 'siefe_registers_edit_key', 'ctrl-e')
let g:siefe_registers_execute_key = get(g:, 'siefe_registers_execute_key', 'ctrl-x')
let g:siefe_registers_clear_key = get(g:, 'siefe_registers_clear_key', 'del')


let g:siefe_maps_open_key = get(g:, 'siefe_maps_open_key', 'ctrl-o')
let g:siefe_maps_modes_key = get(g:, 'siefe_maps_modes_key', 'ctrl-d')

let g:siefe_modes_select_all_key = get(g:, 'siefe_modes_select_all_key', 'ctrl-a')

function! siefe#ripgrepfzf(fullscreen, dir, kwargs) abort
  call s:check_requirements()

  if empty(a:dir)
    return
  endif

  " default values
  let a:kwargs.query = get(a:kwargs, 'query', '')
  let a:kwargs.prompt = get(a:kwargs, 'prompt', a:dir)
  let a:kwargs.word = get(a:kwargs, 'word', g:siefe_rg_default_word)
  let a:kwargs.case_sensitive = get(a:kwargs, 'case_sensitive', g:siefe_rg_default_case_sensitive)
  let a:kwargs.hidden = get(a:kwargs, 'hidden', g:siefe_rg_default_hidden)
  let a:kwargs.no_ignore = get(a:kwargs, 'no_ignore', g:siefe_rg_default_no_ignore)
  let a:kwargs.fixed_strings = get(a:kwargs, 'fixed_strings', g:siefe_rg_default_fixed_strings)
  let a:kwargs.max_1 = get(a:kwargs, 'max_1', g:siefe_rg_default_max_1)
  let a:kwargs.search_zip = get(a:kwargs, 'search_zip', g:siefe_rg_default_search_zip)
  let a:kwargs.text = get(a:kwargs, 'text', g:siefe_rg_default_text)
  let a:kwargs.orig_dir = get(a:kwargs, 'orig_dir', a:dir)
  let a:kwargs.paths = get(a:kwargs, 'paths', [])
  let a:kwargs.type = get(a:kwargs, 'type', '')
  let a:kwargs.files = get(a:kwargs, 'files', '')
  let a:kwargs.preview = get(a:kwargs, 'preview', g:siefe_rg_default_preview_command)
  let a:kwargs.fzf = get(a:kwargs, 'fzf', g:siefe_rg_fzf_default)

  if empty(a:kwargs.files)
    let a:kwargs.files = tempname()
    let files = 0
    call writefile([files], a:kwargs.files)
  """ // is never a valid filename, so we use this to indicate enable files
  elseif a:kwargs.files ==# '//'
    let a:kwargs.files = tempname()
    let files = 1
    call writefile([files], a:kwargs.files)
  else
    let files = readfile(a:kwargs.files)[0]
  endif

  let paths = join(map(copy(a:kwargs.paths), 'shellescape(split(v:val,"//")[-1])'), ' ')

  let word = a:kwargs.word ? '-w ' : ''
  let word_toggle = a:kwargs.word ? 'off' : 'on'
  let hidden = a:kwargs.hidden ? '-. ' : ''
  let hidden_option = a:kwargs.hidden ? '--hidden ' : ''
  let hidden_toggle = a:kwargs.hidden ? 'off' : 'on'
  let case_sensitive = a:kwargs.case_sensitive == 1 ? '--smart-case ' :
        \ a:kwargs.case_sensitive == 2 ? '--ignore-case ' : '--case-sensitive '
  let case_symbol = a:kwargs.case_sensitive == 1 ? '-S ' :
        \ a:kwargs.case_sensitive == 2 ? '-s ' : '-i '
  let case_sensitive_toggle = a:kwargs.case_sensitive == 1 ? '-s ' :
        \ a:kwargs.case_sensitive == 2 ? '-i ' : '-S '
  let no_ignore = a:kwargs.no_ignore == 1 ? '-u ' :
        \ a:kwargs.no_ignore == 2 ? '-uu ' :
        \ a:kwargs.no_ignore == 3 ? '-uuu ' : ' '
  let no_ignore_toggle = a:kwargs.no_ignore == 1 ? '-uu' :
        \ a:kwargs.no_ignore == 2 ? '-uuu' :
        \ a:kwargs.no_ignore == 3 ? 'off' : '-u'
  let fixed_strings = a:kwargs.fixed_strings ? '-F ' : ''
  let fixed_strings_toggle = a:kwargs.fixed_strings ? 'off' : 'on'
  let max_1 = a:kwargs.max_1 ? '-m1 ' : ''
  let max_1_toggle = a:kwargs.max_1 ? 'off' : 'on'
  let search_zip = a:kwargs.search_zip ? '-z ' : ''
  let search_zip_toggle = a:kwargs.search_zip ? 'off' : 'on'
  let text = a:kwargs.text ? '--text ' : ''
  let text_symbol = a:kwargs.text ? '-a ' : ''
  let text_toggle = a:kwargs.text ? 'off' : 'on'
  let command_fmt = 'echo 0 > ' . a:kwargs.files . '; ' . s:logger . ' rg --column --auto-hybrid-regex -U --glob \!.git/objects '
    \ . ' --line-number --no-heading --color=always --colors "column:fg:green" --with-filename '
    \ . case_sensitive
    \ . s:field_match_separator . ' '
    \ . word
    \ . no_ignore
    \ . hidden_option
    \ . fixed_strings
    \ . max_1
    \ . search_zip
    \ . text
    \ . a:kwargs.type
    \ . ' -- %s '
    \ . paths
  if a:kwargs.fzf
    let rg_command = printf(command_fmt, shellescape(''))
  else
    let rg_command = printf(command_fmt, shellescape(a:kwargs.query))
  endif
  let reload_command = printf(command_fmt, '{q}')
  let empty_command = printf(command_fmt, '""')

  let rel_path = substitute(a:dir, siefe#bufdir(), '', '')

  " not a subdir
  if rel_path ==# a:dir
    let rel_path = substitute(siefe#bufdir(), a:dir, '', '')
  endif

  " also not a superdir
  if rel_path ==# siefe#bufdir()
    let bufname_exclude = ''
  else
    let bufname_exclude = empty(expand('%:p:t')) ? '' :  ' -g ' . shellescape('!') . rel_path . '/' . expand('%:p:t')
  endif

  let files_command = 'echo 1 > ' . a:kwargs.files . '; rg '
    \ . search_zip
    \ . text
    \ . no_ignore
    \ . hidden_option
    \ . bufname_exclude
    \ .  ' --color=always --files '.a:kwargs.type

  let fzf_rg = a:kwargs.fzf ? 'fzf' : 'rg'
  let fzf_rg_help = a:kwargs.fzf ? 'rg' : 'fzf'

  let type_prompt = a:kwargs.type ==# '' ? '' : a:kwargs.type . ' '
  let rg_prompt = word
    \ . no_ignore
    \ . hidden
    \ . case_symbol
    \ . fixed_strings
    \ . max_1
    \ . search_zip
    \ . text_symbol
    \ . type_prompt
    \ . a:kwargs.prompt
    \ . ' ' . fzf_rg . '> '

  let files_prompt = no_ignore
    \ . hidden
    \ . search_zip
    \ . text_symbol
    \ . type_prompt
    \ . a:kwargs.prompt
    \ . ' Files> '

  if files
    let initial_command = files_command
    let initial_prompt = files_prompt
    let preview = s:files_preview_command
  else
    let initial_command = rg_command
    let initial_prompt = rg_prompt
    let preview = s:rg_preview_commands[a:kwargs.preview]
  endif

  let name_info = empty(bufname()) ? '[No Name]' : bufname()
  let paths_info = a:kwargs.paths ==# [] ? '' : "\npaths: " . join(map(copy(a:kwargs.paths), 'split(v:val,"//")[-1]'), ' ')

  let rg_fzf_help_line = a:kwargs.fzf ? '' : ' ╱ ' . s:prettify_header(g:siefe_rg_rgfzf_key, 'rg/fzf')

  let header = name_info
        \ . "\n" . s:prettify_header(g:siefe_rg_toggle_fzf_key, fzf_rg_help)
        \ . rg_fzf_help_line
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_files_key, 'Files')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_type_key, '-t')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_type_not_key, '-T')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_buffers_key, 'Buffers')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_no_ignore_key, no_ignore_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_hidden_key, '-.:' . hidden_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_case_key, case_sensitive_toggle)
        \ . "\n" . s:prettify_header(g:siefe_help_key, 'help')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_dir_key, 'cd')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_yank_key, 'yank')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_history_key, 'history')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_word_key, '-w:' . word_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_fixed_strings_key, '-F:' . fixed_strings_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_max_1_key, '-m1:' . max_1_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_search_zip_key, '-z:' . search_zip_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_text_key, '--text:' . text_toggle)
        \ . ' ╱ ' . s:magenta(s:preview_help(s:rg_preview_keys), 'Special') . ' change preview'
        \ . "\n" . s:common_window_help
        \ . paths_info

  let files_header = name_info
        \ . "\n" . s:prettify_header(g:siefe_rg_toggle_fzf_key, fzf_rg)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_files_key, 'Files')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_type_key, '-t')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_type_not_key, '-T')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_buffers_key, 'Buffers')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_no_ignore_key, no_ignore_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_hidden_key, '-.:' . hidden_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_case_key, case_sensitive_toggle)
        \ . "\n" . s:prettify_header(g:siefe_help_key, 'help')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_dir_key, 'cd')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_yank_key, 'yank')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_history_key, 'history')
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_word_key, '-w:' . word_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_fixed_strings_key, '-F:' . fixed_strings_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_max_1_key, '-m1:' . max_1_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_search_zip_key, '-z:' . search_zip_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_rg_text_key, '--text:' . text_toggle)
        \ . ' ╱ ' . s:magenta(s:preview_help(s:rg_preview_keys), 'Special') . ' change preview'
        \ . "\n" . s:common_window_help
        \ . paths_info

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  " https://github.com/junegunn/fzf.vim
  " https://github.com/junegunn/fzf/blob/master/ADVANCED.md#toggling-between-data-sources
  let spec = {
    \ 'options': [
      \ '--history', s:data_path . '/rg_fzf_history',
      \ '--preview', preview,
      \ '--bind', 'enter:ignore',
      \ '--bind', 'esc:ignore',
      \ '--bind', g:siefe_accept_key . ':accept',
      \ '--bind', g:siefe_rg_preview_key . ':change-preview:'.s:rg_preview_command,
      \ '--bind', g:siefe_rg_fast_preview_key . ':change-preview:'.s:rg_fast_preview_command,
      \ '--bind', g:siefe_rg_faster_preview_key . ':change-preview:'.s:rg_faster_preview_command,
      \ '--bind', g:siefe_help_key . ':change-preview:echo -e "'
        \ . s:prettify_help(g:siefe_help_key) . "\t" . 'show this help file'
        \ . "\n" . s:prettify_help(g:siefe_rg_toggle_fzf_key) . "\t". 'search with ' . fzf_rg_help
        \ . "\n" . s:prettify_help(g:siefe_rg_rgfzf_key) . "\t" . 'search with fzf in current ripgrep result'
        \ . "\n" . s:prettify_help(g:siefe_rg_files_key) . "\t" . 'search files with fzf'
        \ . "\n" . s:prettify_help(g:siefe_rg_type_key) . "\t" . 'select file type to search, rg \`-t, --type\`'
        \ . "\n" . s:prettify_help(g:siefe_rg_type_not_key) . "\t" . 'select file type to exclude, rg \`-t, --type-not\`'
        \ . "\n" . s:prettify_help(g:siefe_rg_buffers_key) . "\t" . 'toggle limit search to currently open buffers'
        \ . "\n" . s:prettify_help(g:siefe_rg_no_ignore_key) . "\t" . 'toggle search ignored files ' . no_ignore_toggle
        \ . "\n" . s:prettify_help(g:siefe_rg_hidden_key) . "\t" . 'toggle search hidden files ' . hidden_toggle
        \ . "\n" . s:prettify_help(g:siefe_rg_case_key) . "\t" . 'toggle case sensitive ' . hidden_toggle
          \ . ".\n\t" . 'Toggles between smart case and case sensitive. rg \`-S, --smart-case\`'
        \ . "\n" . s:prettify_help(g:siefe_rg_dir_key) . "\t" . 'change path to search'
        \ . "\n" . s:prettify_help(g:siefe_rg_yank_key) . "\t" . 'yank selected matches line'
        \ . "\n" . s:prettify_help(g:siefe_rg_history_key) . "\t" . 'search file history'
        \ . "\n" . s:prettify_help(g:siefe_rg_word_key) . "\t" . 'toggle only show matches surrounded by word boundaries ' . word_toggle
          \ . ".\n\t" . 'rg \`-w, --word-regexp\`'
        \ . "\n" . s:prettify_help(g:siefe_rg_fixed_strings_key) . "\t"
          \ . 'toggle treat the pattern as a literal string ' . fixed_strings_toggle
          \ . ".\n\t" . 'rg \`-F, --fixed-strings\`'
        \ . "\n" . s:prettify_help(g:siefe_rg_max_1_key) . "\t" . 'toggle limit the number of matching lines per file searched to 1' . max_1_toggle
          \ . ".\n\t" . 'rg \`-m, --max-count 1\`'
        \ . "\n" . s:prettify_help(g:siefe_rg_search_zip_key) . "\t" . 'toggle search in compressed files ' . search_zip_toggle
          \ . ".\n\t" . '(gzip, bzip2, xz, LZ4, LZMA, Brotli and Zstd). rg \`-z, --search-zip\`'
        \ . "\n" . s:prettify_help(g:siefe_rg_text_key) . "\t" . 'toggle search binary files ' . text_toggle
          \ . '. We can search in tar this way.'
          \ . "\n\t" . '  rg \`-a, --text\`. combined with \`-z\` we can also search tar.gz'
          \ . "\n" . s:prettify_help(g:siefe_rg_fast_preview_key) . "\t" . 'fast preview with \`cat\`, no colors but fast'
          \ . "\n" . s:prettify_help(g:siefe_rg_preview_key) . "\t" . 'preview with \`bat\`, colors and git info but slower than \`cat\`'
        \ . '"',
      \ '--bind', g:siefe_down_key . ':down',
      \ '--bind', g:siefe_up_key . ':up',
      \ '--bind', g:siefe_next_history_key . ':next-history',
      \ '--bind', g:siefe_previous_history_key . ':previous-history',
      \ '--print-query',
      \ '--ansi',
      \ '--print0',
      \ '--expect='
        \ . g:siefe_rg_toggle_fzf_key . ','
        \ . g:siefe_rg_type_key . ','
        \ . g:siefe_rg_type_not_key . ','
        \ . g:siefe_rg_word_key . ','
        \ . g:siefe_rg_case_key . ','
        \ . g:siefe_rg_hidden_key . ','
        \ . g:siefe_rg_no_ignore_key . ','
        \ . g:siefe_rg_fixed_strings_key . ','
        \ . g:siefe_rg_max_1_key . ','
        \ . g:siefe_rg_search_zip_key . ','
        \ . g:siefe_rg_text_key . ','
        \ . g:siefe_rg_dir_key . ','
        \ . g:siefe_rg_buffers_key . ','
        \ . g:siefe_rg_yank_key . ','
        \ . g:siefe_rg_history_key . ','
        \ . g:siefe_abort_key . ','
        \ . s:common_window_expect_keys,
      \ '--preview-window', '+{2}-/2,' . default_preview_size,
      \ '--multi',
      \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
      \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
      \ '--query', a:kwargs.query,
      \ '--delimiter', s:delimiter,
      \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
      \ '--bind', 'change:+first',
      \ '--bind', g:siefe_rg_files_key
        \ . ':unbind(change,' . g:siefe_rg_files_key . ',' . g:siefe_rg_rgfzf_key . ')'
        \ . '+change-prompt(' . files_prompt . ')'
        \ . '+change-header(' . files_header . ')'
        \ . '+enable-search'
        \ . '+reload('.files_command.')'
        \ . '+change-preview('.s:files_preview_command.')',
      \ '--header', header,
      \ '--prompt', initial_prompt,
      \ ],
   \ 'dir': a:dir,
   \ 'sink*': function('s:ripgrep_sink', [a:fullscreen, a:dir, a:kwargs]),
   \ 'source': initial_command
  \ }
  if files == 0 && a:kwargs.fzf == 0
    let spec.options += [
      \ '--disabled',
      \ '--bind', 'change:reload:' . reload_command,
      \ '--bind',  g:siefe_rg_rgfzf_key
      \ . ':unbind(change,' . g:siefe_rg_rgfzf_key . ')'
      \ . '+change-prompt(' . no_ignore.hidden.a:kwargs.type . ' ' . a:kwargs.prompt . ' rg/fzf> )'
      \ . '+enable-search+rebind(' . g:siefe_rg_files_key . ')'
      \ . '+change-preview(' . s:rg_preview_commands[g:siefe_rg_default_preview_command] . ')'
    \ ]
  elseif files == 1 && a:kwargs.fzf == 0
    let spec.options += ['--bind', 'start:unbind(change)']
  endif

  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:ripgrep_sink(fullscreen, dir, kwargs, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  " query can contain newlines, we have to reconstruct it
  let [query, key; l:files] = split(a:lines[-1], "\n", 1)[0:-2]
  if len(a:lines) == 1
    let a:kwargs.query = query
  else
    let a:kwargs.query = join(a:lines[0:-2], "\n") . "\n" . query
  endif

  let filelist = []

  for item in l:files
    let file_data = split(item, s:delimiter, 1)
    let file = {}

    " rg/fzf '//' delimited result
    if len(file_data) >= 4
      let file.filename  = file_data[0]
      let file.lnum  = file_data[1]
      let file.col  = file_data[2]

      if len(file_data) == 4
        let file.text = file_data[3]
      else
        " If it's bigger than 4 that means there was a // in there result,
        " so we recreate the original content
        let file.text = join(file_data[3:], s:delimiter)."\n"
      endif

    " files result
    elseif len(file_data) == 1
      let file.filename = file_data[0]
      let content = readfile(file_data[0])
      let file.text = empty(content) ? '' : content[0]
      let file.lnum  = 1
      let file.col  = 1

      " this should never happen
      else
        return s:warn('Something went wrong... file_data = '.string(file_data).'lines = '.string(a:lines))
      endif
        let filelist += [file]
  endfor


  if key ==# ''
    " no match
    if len(l:files) == 0
      return
    endif

    augroup siefe_swap
    autocmd SwapExists * call s:swapchoice(v:swapname)
    augroup END

    execute 'e' fnameescape(file.filename)
    call cursor(file.lnum, file.col)
    normal! zvzz

    silent! autocmd! siefe_swap

    if g:siefe_rg_loclist
      call s:fill_loc(filelist)
    else
      call s:fill_quickfix(filelist)
    endif

  elseif has_key(s:common_window_actions, key)
    " no match
    if len(l:files) == 0
      return
    endif

    augroup siefe_swap
    autocmd SwapExists * call s:swapchoice(v:swapname)
    augroup END

    let cmd = s:common_window_actions[key]
    for file in filelist
      silent! autocmd! siefe_swap
        execute 'silent' cmd fnameescape(file.filename)
        call cursor(file.lnum, file.col)
        normal! zvzz
    endfor

    silent! autocmd! siefe_swap
  endif

  " work around for strange nested fzf change directory behaviour
  " when nested it will not cd back to the original directory
  exe 'cd' a:kwargs.orig_dir

  if key ==# g:siefe_rg_type_key
    call SiefeTypeSelect('SiefeRipgrepType', a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_type_not_key
    call SiefeTypeSelect('SiefeRipgrepTypeNot', a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_word_key
    let a:kwargs.word = a:kwargs.word ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_case_key
    let a:kwargs.case_sensitive = a:kwargs.case_sensitive == 0 ? 1 :
          \ a:kwargs.case_sensitive == 1 ? 2 : 0
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_hidden_key
    let a:kwargs.hidden = a:kwargs.hidden ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_no_ignore_key
    let a:kwargs.no_ignore = a:kwargs.no_ignore == 0 ? 1 :
          \ a:kwargs.no_ignore == 1 ? 2 :
          \ a:kwargs.no_ignore == 2 ? 3 : 0
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_fixed_strings_key
    let a:kwargs.fixed_strings = a:kwargs.fixed_strings ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_max_1_key
    let a:kwargs.max_1 = a:kwargs.max_1 ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_search_zip_key
    let a:kwargs.search_zip = a:kwargs.search_zip ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_text_key
    let a:kwargs.text = a:kwargs.text ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_toggle_fzf_key
    if readfile(a:kwargs.files)[0]
      call writefile([0], a:kwargs.files)
    else
      let a:kwargs.fzf = a:kwargs.fzf ? 0 : 1
    endif
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_buffers_key
    let bufferlist = map(filter(copy(getbufinfo()), 'v:val.listed'), 'fnamemodify(v:val.name, ":p:~:.")')
    if a:kwargs.paths != bufferlist
      let a:kwargs.paths = bufferlist
      call siefe#ripgrepfzf( a:fullscreen, a:dir, a:kwargs)
    else
      let a:kwargs.paths = []
      call siefe#ripgrepfzf( a:fullscreen, a:dir, a:kwargs)
    endif

  elseif key ==# g:siefe_rg_dir_key
    call SiefeDirSelect('SiefeRipgrepDir', a:fullscreen, a:dir, 0, 0, 'd', 0, '', a:kwargs)

  elseif key ==# g:siefe_rg_yank_key
    return s:yank_to_register(join(map(filelist, 'v:val.text'), "\n"))

  elseif key ==# g:siefe_rg_history_key && readfile(a:kwargs.files)[0] == 1
    call siefe#history(a:fullscreen, a:kwargs)

  elseif key ==# g:siefe_rg_history_key && readfile(a:kwargs.files)[0] == 0
    let dir = FugitiveFind(':/')
    if dir ==# ''
      let dir = expand('%:p:h')
    endif
    let recent_files = siefe#recent_files()
    if a:kwargs.paths != recent_files
      let a:kwargs.paths = recent_files
      call siefe#ripgrepfzf( a:fullscreen, dir, a:kwargs)
    else
      let a:kwargs.paths = []
      call siefe#ripgrepfzf( a:fullscreen, a:kwargs.orig_dir, a:kwargs)
    endif
  endif
endfunction

" Lots of functions to use fzf to also select ie rg types
function! SiefeTypeSelect(func, fullscreen, ...) abort
  call fzf#run(fzf#wrap({
        \ 'source': s:logger . 'rg --color=always --type-list ',
        \ 'options': [
          \ '--prompt', 'Choose type> ',
          \ '--multi',
          \ '--history', s:data_path . '/type_fzf_history',
          \ '--bind', 'enter:ignore',
          \ '--bind', 'esc:ignore',
          \ '--bind', g:siefe_accept_key . ':accept',
          \ '--bind', g:siefe_down_key . ':down',
          \ '--bind', g:siefe_up_key . ':up',
          \ '--bind', g:siefe_next_history_key . ':next-history',
          \ '--bind', g:siefe_previous_history_key . ':previous-history',
          \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
          \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
          \ '--expect', g:siefe_abort_key,
          \ '--header', s:prettify_header(g:siefe_abort_key, 'abort'),
          \ ],
        \ 'sink*': function(a:func, [a:fullscreen] + a:000)
      \ }, a:fullscreen))
endfunction


function! SiefeDirSelect(func, fullscreen, dir, fd_hidden, fd_no_ignore, fd_type, multi, base_dir, ...) abort
  let fd_hidden = a:fd_hidden ? '-H ' : ''
  let fd_hidden_toggle = a:fd_hidden ? 'off' : 'on'
  let fd_no_ignore = a:fd_no_ignore ? '-u ' : ''
  let fd_no_ignore_toggle = a:fd_no_ignore ? 'off' : 'on'
  let fd_type = a:fd_type !=# '' ? ' --type ' . a:fd_type : ''
  let base_dir = a:base_dir !=# '' ? ' --strip-cwd-prefix --base-directory ' . a:base_dir : ' --search-path=`realpath --relative-to=. "'.a:dir.'"` --relative-path '

  let siefe_fd_project_root_key = g:siefe_fd_project_root_env ==# '' ? '' : g:siefe_fd_project_root_key . ','
  let siefe_fd_project_root_help = g:siefe_fd_project_root_env ==# '' ? '' : ' ╱ ' . s:prettify_header(g:siefe_fd_project_root_key, '√work')
  let siefe_fd_search_project_root_key = g:siefe_fd_project_root_env ==# '' ? '' : g:siefe_fd_search_project_root_key . ','
  let siefe_fd_search_project_root_help = g:siefe_fd_project_root_env ==# '' ? '' : ' ╱ ' . s:prettify_header(g:siefe_fd_search_project_root_key, 'search √work')

  " TODO disable git/project root for git log

  exe 'cd' a:dir

  let options = [
    \ '--history', s:data_path . '/git_dir_history',
    \ '--print-query',
    \ '--ansi',
    \ '--scheme=path',
    \ '--bind', 'enter:ignore',
    \ '--bind', 'esc:ignore',
    \ '--bind', g:siefe_accept_key . ':accept',
    \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
    \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
    \ '--bind', g:siefe_down_key . ':down',
    \ '--bind', g:siefe_up_key . ':up',
    \ '--bind', g:siefe_next_history_key . ':next-history',
    \ '--bind', g:siefe_previous_history_key . ':previous-history',
    \ '--prompt', fd_no_ignore.fd_hidden.'fd> ',
    \ '--expect='
    \ . g:siefe_fd_hidden_key . ','
    \ . g:siefe_fd_no_ignore_key . ','
    \ . g:siefe_fd_git_root_key . ','
    \ . g:siefe_fd_search_git_root_key . ','
    \ . siefe_fd_project_root_key
    \ . siefe_fd_search_project_root_key
    \ . g:siefe_abort_key,
    \ '--header',  getcwd()
      \ . "\n" . s:prettify_header(g:siefe_fd_hidden_key, 'hidden:' . fd_hidden_toggle)
      \ . ' ╱ ' . s:prettify_header(g:siefe_fd_no_ignore_key, 'no ignore:' . fd_no_ignore_toggle)
      \ . ' ╱ ' . s:prettify_header(g:siefe_fd_git_root_key, '√git')
      \ . siefe_fd_project_root_help
      \ . ' ╱ ' . s:prettify_header(g:siefe_abort_key, 'abort')
      \ . "\n" . s:prettify_header(g:siefe_fd_search_git_root_key, 'search √git')
      \ . siefe_fd_search_project_root_help
    \ ]
  if a:multi
    let options += ['--multi']
  endif

  call fzf#run(fzf#wrap({
        \ 'source': s:logger . s:fd_command . ' --exclude ".git/" --color=always ' . fd_hidden . fd_no_ignore . fd_type . base_dir,
        \ 'options': options,
        \ 'sink*': function(a:func, [a:fullscreen, a:dir, a:fd_hidden, a:fd_no_ignore] + a:000)
      \ }, a:fullscreen))
endfunction

function! SiefeRipgrepDir(fullscreen, dir, fd_hidden, fd_no_ignore, kwargs, lines) abort
  let fd_query = a:lines[0]
  let key = a:lines[1]

  if len(a:lines) == 3
    let new_dir = a:lines[2]
  else
    let new_dir = a:dir
  endif

  if key ==# g:siefe_abort_key
    let a:kwargs.prompt = siefe#get_relative_git_or_bufdir()
    call siefe#ripgrepfzf(a:fullscreen, siefe#bufdir(), a:kwargs)

  elseif key ==# g:siefe_fd_hidden_key
    let fd_hidden = a:fd_hidden ? 0 : 1
    call SiefeDirSelect('SiefeRipgrepDir', a:fullscreen, a:dir, fd_hidden, a:fd_no_ignore, 'd', 0, '', a:kwargs)

  elseif key ==# g:siefe_fd_no_ignore_key
    let fd_no_ignore = a:fd_no_ignore ? 0 : 1
    call SiefeDirSelect('SiefeRipgrepDir', a:fullscreen, a:dir, a:fd_hidden, fd_no_ignore, 'd', 0, '', a:kwargs)

  elseif key ==# g:siefe_fd_git_root_key
    let a:kwargs.prompt = siefe#get_git_basename_or_bufdir()
    call siefe#ripgrepfzf(a:fullscreen, siefe#get_git_root(), a:kwargs)

  elseif key ==# g:siefe_fd_project_root_key
    let a:kwargs.prompt = g:siefe_fd_project_root_env
    call siefe#ripgrepfzf(a:fullscreen, expand(g:siefe_fd_project_root_env), a:kwargs)

  elseif key ==# g:siefe_fd_search_git_root_key
    call SiefeDirSelect('SiefeRipgrepDir', a:fullscreen, siefe#get_git_root(), a:fd_hidden, a:fd_no_ignore, 'd', 0, '', a:kwargs)

  elseif key ==# g:siefe_fd_search_project_root_key
    call SiefeDirSelect('SiefeRipgrepDir', a:fullscreen, expand(g:siefe_fd_project_root_env), a:fd_hidden, a:fd_no_ignore, 'd', 0, '', a:kwargs)

  else
    let a:kwargs.prompt = siefe#get_relative_git_or_bufdir(new_dir)
    call siefe#ripgrepfzf(a:fullscreen, trim(system('realpath '.new_dir)), a:kwargs)
  endif
endfunction

function! SiefeRipgrepType(fullscreen, dir, kwargs, lines) abort
  if a:lines[0] ==# g:siefe_abort_key
    let a:kwargs.type = ''
  else
    let a:kwargs.type = join(map(a:lines[1:], '"-t" . split(v:val, ":")[0]'))
  endif
  call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)
endfunction

function! SiefeRipgrepTypeNot(fullscreen, dir, kwargs, lines) abort
  if a:lines[0] ==# g:siefe_abort_key
    let a:kwargs.type = ''
  else
    let a:kwargs.type = join(map(a:lines[1:], '"-T" . split(v:val, ":")[0]'))
  endif
  call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)
endfunction

function! siefe#gitlogfzf(fullscreen, kwargs) abort
  call s:check_requirements()

  " default values
  let a:kwargs.query = get(a:kwargs, 'query', '')
  let a:kwargs.branches = get(a:kwargs, 'branches', '')
  let a:kwargs.notbranches = get(a:kwargs, 'notbranches', '')
  let a:kwargs.authors = get(a:kwargs, 'authors', [])
  let a:kwargs.G = get(a:kwargs, 'G', g:siefe_gitlog_default_G)
  let a:kwargs.regex = get(a:kwargs, 'regex', g:siefe_gitlog_default_regex)
  let a:kwargs.paths = get(a:kwargs, 'paths', [])
  let a:kwargs.follow = get(a:kwargs, 'follow', g:siefe_gitlog_default_follow)
  let a:kwargs.ignore_case = get(a:kwargs, 'ignore_case', g:siefe_gitlog_default_ignore_case)
  let a:kwargs.type = get(a:kwargs, 'type', '')
  let a:kwargs.line_range = get(a:kwargs, 'line_range', [])
  let a:kwargs.fixup = get(a:kwargs, 'fixup', 0)

  if a:kwargs.branches ==# '--all'
    let branches = '--all '
    let notbranches = ''
  else
    let branches = a:kwargs.branches ==# '' ? '' : a:kwargs.branches . ' '
    let notbranches = a:kwargs.notbranches ==# '' ? '' : a:kwargs.notbranches . ' '
  endif

  let authors = join(map(copy(a:kwargs.authors), '"--author=".shellescape(v:val)'))

  if len(a:kwargs.paths)  == 1 && (filereadable(a:kwargs.paths[0]) || isdirectory(a:kwargs.paths[0])) && a:kwargs.line_range == []
    let siefe_gitlog_follow_key = g:siefe_gitlog_follow_key . ','
    let siefe_gitlog_follow_help = ' ╱ ' . s:prettify_header( g:siefe_gitlog_follow_key, 'follow')
    let follow = a:kwargs.follow ? '--follow ' : ''
  else
    let siefe_gitlog_follow_key = ''
    let siefe_gitlog_follow_help = ''
    let follow = ''
  endif
  if len(a:kwargs.type) > 0 && len(a:kwargs.paths) > 0
    let paths = []
    for path in a:kwargs.paths
      call s:warn(path[len(path)-1])
      if path[len(path)-1] ==# '/'
        for ftype in a:kwargs.type
          let paths += [path . ftype]
        endfor
      else
        let paths += [path]
      endif
    endfor
    let paths = join(map(paths, 'shellescape(v:val)'))

  elseif len(a:kwargs.type) > 0 && len(a:kwargs.paths) == 0
    let paths = join(map(copy(a:kwargs.type), 'shellescape(v:val)'))

  else
    let paths = join(map(filter(copy(a:kwargs.paths), 'filereadable(v:val) || isdirectory(v:val)'), 'shellescape(v:val)'))
  endif

  let G = a:kwargs.G ? '-G' : '-S'
  let G_prompt = a:kwargs.G ? '-G ' : '-S '
  " --pickaxe-regex and -G are incompatible
  let regex = a:kwargs.G ? '' : a:kwargs.regex ? '--pickaxe-regex ' : ''
  let ignore_case = a:kwargs.ignore_case ? '--regexp-ignore-case ' : ''
  let ignore_case_toggle = a:kwargs.ignore_case ? 'off' : 'on'
  let ignore_case_symbol = a:kwargs.ignore_case ? '-i ' : ''
  let remove_newlines = '| sed -z -E "s/\r?\n/↵/g"'

  " git -L is a bit crippled and ignores --format, so we have to make our own with sed
  if a:kwargs.line_range != []
    let initial_command = 'git log  --no-patch -z -L' . a:kwargs.line_range[0] . ',' . a:kwargs.line_range[1] . ':' . paths
      \ . ' ' . branches
      \ . ' ' . notbranches
      \ . ' ' . authors
      \ . ' ' . regex
      \ . ' ' . ignore_case
      \ . ' --color=always '
      \ . ' --abbrev-commit -- '
      \ . ' | sed -E -z "s/commit ([0-9a-f]*)([^\n]*)*.*\n\n/\1\2 •/" '
      \ . ' | sed -E -z "s/[ ][ ]*/ /g"'
      \ . remove_newlines
    let reload_command = ''
    let SG_expect = ''
    let SG_help = ''
    let query_file = '/dev/null'
    let line_range = '-L' . join(a:kwargs.line_range, ',') . ' '
    let G_prompt = ''
  else
    let SG_expect = g:siefe_gitlog_sg_key . ','
        \ . g:siefe_gitlog_ignore_case_key . ','
        \ . g:siefe_gitlog_type_key . ','
        \ . g:siefe_gitlog_pickaxe_regex_key . ','
        \ . siefe_gitlog_follow_key . ','
        \ . g:siefe_gitlog_dir_key
    let query_file = tempname()
    let write_query_initial = 'echo '. shellescape(a:kwargs.query) .' > '.query_file.' ;'
    let write_query_reload = 'echo {q} > '.query_file.' ;'
    let format = '--format=%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)%b'
    let command_fmt = s:bin.git_SG
        \ . ' -C `git rev-parse --show-toplevel` '
        \ . ' log '
        \ . G
        \ . '%s -z '
        \ . ' --color=always '
        \ . follow
        \ . ' ' . branches
        \ . ' ' . notbranches
        \ . ' ' . authors
        \ . ' ' . regex
        \ . ' ' . ignore_case
    let initial_command = s:logger . write_query_initial . s:logger . printf(command_fmt, shellescape(a:kwargs.query)).fzf#shellescape(format).' -- ' . paths . remove_newlines
    let reload_command = s:logger . write_query_reload . s:logger . printf(command_fmt, '{q}').fzf#shellescape(format).' -- ' . paths . remove_newlines
    let SG_help = " \n " . s:prettify_header(g:siefe_gitlog_sg_key, 'toggle S/G')
        \ . ' ╱ ' . s:prettify_header(g:siefe_gitlog_ignore_case_key, 'ignore case:' . ignore_case_toggle)
        \ . ' ╱ ' . s:prettify_header(g:siefe_gitlog_fzf_key,  'fzf messages')
        \ . ' ╱ ' . s:prettify_header(g:siefe_gitlog_pickaxe_regex_key, 'regex')
        \ . ' ╱ ' . s:prettify_header(g:siefe_gitlog_dir_key, 'pathspec')
    let line_range = ''
  endif

  let current = substitute(fnamemodify(expand('%'), ':p'), FugitiveFind(':/') . '/', '', '')
  let orderfile = tempname()
  call writefile([current], orderfile)

  let suffix = executable('delta') ? '| delta ' . g:siefe_delta_options  : ''

  let preview_all_command = 'echo -e "\033[0;35mgit show all\033[0m" && git -C `git rev-parse --show-toplevel` show --color=always -O'.fzf#shellescape(orderfile).' {1} '
  let preview_command_0 = preview_all_command . ' --patch --stat -- ' . suffix
  let preview_command_1 = preview_all_command . ' --format=format: -- ' . suffix

  let preview_command_2 = 'echo -e "\033[0;35mgit show matching files\033[0m" && ' . s:bin.git_SG . ' -C `git rev-parse --show-toplevel` show ' . G .'"`cat '.query_file.'`" -O'.fzf#shellescape(orderfile).' ' . regex . '--color=always {1} '
    \ . ' --format=format: --patch --stat -- ' . suffix
  let quote = "'"
  let preview_pickaxe_hunks_command = ' bash -c ' . quote . ' echo -e "\033[0;35mgit show matching hunks\033[0m" && (export GREPDIFF_REGEX=`cat ' . query_file . '`; ' . s:bin.git_SG . ' -C `git rev-parse --show-toplevel` -c diff.external=' . s:bin.pickaxe_diff . ' show {1} -O' . fzf#shellescape(orderfile) . ' --ext-diff ' . regex . G . '"`cat ' . query_file . '`"'
  let no_grepdiff_message = 'echo install grepdiff from the patchutils package for this preview'
  let preview_command_3 = executable('grepdiff') ? preview_pickaxe_hunks_command . ' --format=format: --patch --stat --) ' . quote . suffix : no_grepdiff_message
  let preview_command_4 = 'echo -e "\033[0;35mgit diff\033[0m" && git -C `git rev-parse --show-toplevel` diff --color=always -O'.fzf#shellescape(orderfile).' --patch --stat {1} -- ' . suffix

  let preview_commands = [
    \ preview_command_0,
    \ preview_command_1,
    \ preview_command_2,
    \ preview_command_3,
    \ preview_command_4,
  \ ]

  let authors_info = a:kwargs.authors ==# [] ? '' : "\nauthors: ".join(a:kwargs.authors)
  let paths_info = paths ==# '' ? '' : "\npaths: " . join(map(filter(copy(a:kwargs.paths), 'filereadable(v:val) || isdirectory(v:val)'), 'siefe#get_relative_git_or_buf(v:val)'))

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  let spec = {
    \ 'options': [
      \ '--history', s:data_path . '/git_fzf_history',
      \ '--preview', preview_commands[ g:siefe_gitlog_default_preview_command ],
      \ '--bind', 'enter:ignore',
      \ '--bind', 'esc:ignore',
      \ '--bind', g:siefe_accept_key . ':accept',
      \ '--bind', g:siefe_abort_key . ':abort',
      \ '--bind', g:siefe_gitlog_preview_0_key . ':change-preview:'.preview_command_0,
      \ '--bind', g:siefe_gitlog_preview_1_key . ':change-preview:'.preview_command_1,
      \ '--bind', g:siefe_gitlog_preview_2_key . ':change-preview:'.preview_command_2,
      \ '--bind', g:siefe_gitlog_preview_3_key . ':change-preview:'.preview_command_3,
      \ '--bind', g:siefe_gitlog_preview_4_key . ':change-preview:'.preview_command_4,
      \ '--bind', g:siefe_down_key . ':down',
      \ '--bind', g:siefe_up_key . ':up',
      \ '--bind', g:siefe_next_history_key . ':next-history',
      \ '--bind', g:siefe_previous_history_key . ':previous-history',
      \ '--print-query',
      \ '--layout=reverse-list',
      \ '--ansi',
      \ '--read0',
      \ '--expect='
        \ . g:siefe_gitlog_author_key . ','
        \ . g:siefe_gitlog_branch_key . ','
        \ . g:siefe_gitlog_not_branch_key . ','
        \ . g:siefe_gitlog_vdiffsplit_key . ','
        \ . g:siefe_gitlog_switch_key . ','
        \ . SG_expect . ','
        \ . s:common_window_expect_keys,
      \ '--bind', g:siefe_toggle_up_key . ':toggle+down',
      \ '--bind', g:siefe_toggle_down_key . ':toggle+up',
      \ '--delimiter', '•',
      \ '--preview-window', default_preview_size,
      \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
      \ '--header',
        \ s:prettify_header(g:siefe_gitlog_author_key, 'authors')
        \ . ' ╱ ' . s:prettify_header(g:siefe_gitlog_branch_key, 'branches')
        \ . ' ╱ ' . s:prettify_header(g:siefe_gitlog_type_key, 'type')
        \ . ' ╱ ' . s:prettify_header(g:siefe_gitlog_switch_key, 'switch')
        \ . ' ╱ ' . s:magenta(s:preview_help(s:gitlog_preview_keys), 'Special') . ' change preview'
        \ . ' ╱ ' . s:prettify_header(g:siefe_gitlog_not_branch_key, '^branches')
        \ . "\n" . s:common_window_help
        \ . SG_help
        \ . siefe_gitlog_follow_help
        \ . authors_info
        \ . paths_info,
      \ '--prompt', branches . notbranches . G_prompt . regex . ignore_case_symbol . follow . line_range . 'pickaxe> ',
      \ ],
   \ 'dir': siefe#get_git_root(),
   \ 'sink*': function('s:gitpickaxe_sink', [a:fullscreen, a:kwargs]),
   \ 'source': initial_command
  \ }

  if a:kwargs.fixup == 0
    let spec.options += [
      \ '--multi',
      \ ]
  endif

  if a:kwargs.line_range == []
    let spec.options += [
      \ '--disabled',
      \ '--query', a:kwargs.query,
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', g:siefe_gitlog_fzf_key . ':unbind(change,' . g:siefe_gitlog_fzf_key . ')+change-prompt(pickaxe/fzf> )+enable-search+rebind(' . g:siefe_gitlog_s_key . ')',
      \ '--bind', g:siefe_gitlog_s_key . ':unbind(change,' . g:siefe_gitlog_s_key . ')+change-prompt(' . branches . notbranches . G_prompt . regex . ignore_case_symbol . 'pickaxe> '. ')+disable-search+reload(' . reload_command . ')+rebind(change,' . g:siefe_gitlog_fzf_key . ')',
      \ ]
  endif

  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:gitpickaxe_sink(fullscreen, kwargs, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  let a:kwargs.query = a:lines[0]
  let key = a:lines[1]

  " split(v:val, ' ')[0]) == commit hash
  " join(split(v:val, ' ')[1:] == full commit message
  let quickfix_list = map(a:lines[2:], '{'
    \ . '"bufnr":bufadd(trim(fugitive#Open("", 0, "<mods>", split(v:val, " ")[0]))),'
    \ . '"text":join(split(v:val, " ")[1:], " ")[:(winwidth(0) - (len(split(v:val, " ")[0]) + 7))] . ( len(join(split(v:val, " ")[1:], " ")) > winwidth(0) ? "..." : ""),'
    \ . '"module":split(v:val, " ")[0],'
    \ . '}')

  if key == g:siefe_gitlog_sg_key
    let a:kwargs.G = a:kwargs.G ? 0 : 1
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)

  elseif key == g:siefe_gitlog_ignore_case_key
    let a:kwargs.ignore_case = a:kwargs.ignore_case ? 0 : 1
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)

  elseif key == g:siefe_gitlog_pickaxe_regex_key
    let a:kwargs.regex = a:kwargs.regex ? 0 : 1
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)

  elseif key == g:siefe_gitlog_follow_key
    let a:kwargs.follow = a:kwargs.follow ? 0 : 1
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)

  elseif key == g:siefe_gitlog_branch_key
    call SiefeBranchSelect('SiefeGitPickaxeBranch', a:fullscreen, 0, 0, a:kwargs)

  elseif key == g:siefe_gitlog_not_branch_key
    call SiefeBranchSelect('SiefeGitPickaxeNotBranch', a:fullscreen, 1, 0,  a:kwargs)

  elseif key == g:siefe_gitlog_author_key
    call SiefeAuthorSelect('SiefeGitPickaxeAuthor', a:fullscreen, a:kwargs)

  elseif key == g:siefe_gitlog_dir_key
    call SiefeDirSelect('SiefeGitPickaxePath', a:fullscreen, siefe#bufdir(), 0, 0, '', 1, siefe#get_git_root(), a:kwargs)

  elseif key == g:siefe_gitlog_type_key
    " git understands rg --type-list globs :)
    call SiefeTypeSelect('SiefeGitlogType', a:fullscreen, a:kwargs)

  elseif key == g:siefe_gitlog_switch_key
    if len(a:lines) != 3
      echom 'select exactly 1 commit for switch'
      call siefe#gitlogfzf(a:fullscreen, a:kwargs)
    endif
    let commit = split(a:lines[2], ' ')[0]
    let action = ''
      let action = input('create branch? (y/n) ')
    while 1
      if action ==# 'y'
        " todo what if fails (branch already exists)
        execute 'Git switch -c ' . commit
        break
      elseif action ==# 'n'
        execute 'Git switch ' . commit
        break
      endif
    endwhile

  elseif key == g:siefe_gitlog_vdiffsplit_key
    if len(quickfix_list) == 2
      execute 'Gedit '. quickfix_list[0].module . ':%'
      execute 'Gvdiffsplit '. quickfix_list[1].module . ':%'
    elseif len(quickfix_list) == 1
      execute 'Gedit HEAD:%'
      execute 'Gvdiffsplit '. quickfix_list[0].module . ':%'
    endif

  elseif a:kwargs.fixup == 1
    let commit = split(a:lines[2], ' ')[0]
        execute 'Git commit --fixup=' . commit

  elseif a:kwargs.fixup == 2
    let commit = split(a:lines[2], ' ')[0]
        execute 'Git commit --squash=' . commit

  elseif has_key(s:common_window_actions, key)
    " no match
    if len(a:lines[2:]) == 0
      return
    endif

    let cmd = s:fugitive_window_actions[s:common_window_actions[key]]
    for hash in a:lines[2:]
      execute 'silent' cmd hash
      normal! zvzz
    endfor

  else
    execute 'Gedit '. quickfix_list[0].module
    if g:siefe_gitlog_loclist
      call s:fill_loc(quickfix_list)
    else
      call s:fill_quickfix(quickfix_list)
    endif
  endif
endfunction

function! SiefeGitlogType(fullscreen, kwargs, lines) abort
  if a:lines[0] == g:siefe_abort_key
    let a:kwargs.type = ''
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)
  else
    let a:kwargs.type = s:reduce(map(a:lines[1:], 'split(substitute(split(v:val, ":")[1], ",", "", "g"))'), { acc, val -> type(val) == 3 ? extend(acc, val) : add(acc, val)})
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)
  endif
endfunction

function! SiefeBranchSelect(func, fullscreen, not, standalone, ...) abort
  let preview_command_0 = 'echo -e "\033[0;35m"git log {1}"\033[0m" ; echo {2} -- | xargs git log --color=always --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_1 = 'echo -e "\033[0;35m"git log ..{1} \(what they have, we dont\)"\033[0m"; echo ..{2} -- | xargs git log --color=always --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_2 = 'echo -e "\033[0;35m"git log {1}.. \(what we have, they dont\)"\033[0m"; echo {2}.. -- | xargs git log --color=always --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_3 = 'echo -e "\033[0;35m"git log {1}... \(what we both have, common ancester not\)"\033[0m"; echo {2}... -- | xargs git log --color=always --format="%m%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'

  let not = a:not ? '^' : ''
  let siefe_branches_all_key = a:not ? '' : g:siefe_branches_all_key . ','
  let siefe_branches_all_help = a:not ? '' : ' ╱ ' . s:prettify_header(g:siefe_branches_all_key, '--all')

  if a:standalone
    let extra_keys = g:siefe_branches_switch_key . ','
      \ . g:siefe_branches_merge_key . ','
      \ . g:siefe_branches_rebase_interactive_key . ','
    let extra_help = s:prettify_header(g:siefe_branches_switch_key, 'switch')
        \ . ' ╱ ' . s:prettify_header(g:siefe_branches_merge_key, 'merge')
        \ . ' ╱ ' . s:prettify_header(g:siefe_branches_rebase_interactive_key, 'rebase -i')
  else
    let extra_keys = siefe_branches_all_key
    let extra_help = siefe_branches_all_help
  endif

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'

  let spec = {
    \ 'source':  "git branch -a --sort='-authordate' --color --format='%(HEAD) %(if:equals=refs/remotes)%(refname:rstrip=-2)%(then)%(color:cyan)%(align:0)%(refname:lstrip=2)%(end)%(else)%(if)%(HEAD)%(then)%(color:reverse yellow)%(align:0)%(refname:lstrip=-1)%(end)%(else)%(color:yellow)%(align:0)%(refname:lstrip=-1)%(end)%(end)%(end)%(color:reset) %(color:red): %(if)%(symref)%(then)%(color:yellow)%(objectname:short)%(color:reset) %(color:red):%(color:reset) %(color:green)-> %(symref:lstrip=-2)%(else)%(color:yellow)%(objectname:short)%(color:reset) %(if)%(upstream)%(then)%(color:red): %(color:reset)%(color:green)[%(upstream:short)%(if)%(upstream:track)%(then):%(color:blue)%(upstream:track,nobracket)%(symref:lstrip=-2)%(color:green)%(end)]%(color:reset) %(end)%(color:red):%(color:reset) %(contents:subject)%(end) • %(color:blue)(%(authordate:short))'",
    \ 'sink*':   function(a:func, [a:fullscreen] + a:000),
    \ 'options':
      \ [
        \ '--history', s:data_path . '/rg_branch_history',
        \ '--ansi',
        \ '--delimiter', ':',
        \ '--bind', 'enter:ignore',
        \ '--bind', 'esc:ignore',
        \ '--bind', g:siefe_accept_key . ':accept',
        \ '--bind', g:siefe_gitbranch_preview_0_key . ':change-preview:' . preview_command_0,
        \ '--bind', g:siefe_gitbranch_preview_1_key . ':change-preview:' . preview_command_1,
        \ '--bind', g:siefe_gitbranch_preview_2_key . ':change-preview:' . preview_command_2,
        \ '--bind', g:siefe_gitbranch_preview_3_key . ':change-preview:' . preview_command_3,
        \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
        \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
        \ '--bind', g:siefe_down_key . ':down',
        \ '--bind', g:siefe_up_key . ':up',
        \ '--bind', g:siefe_next_history_key . ':next-history',
        \ '--bind', g:siefe_previous_history_key . ':previous-history',
        \ '--expect='
          \ . g:siefe_abort_key . ','
          \ . extra_keys,
        \ '--preview', preview_command_0,
        \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
        \ '--preview-window', '~1,' . default_preview_size,
        \ '--prompt', not . 'branches> ',
        \ '--header='
          \ . s:prettify_header(g:siefe_abort_key, 'abort')
          \ . extra_help
      \ ],
    \ 'placeholder': ''
  \ }

  if a:standalone
    let spec.options += ['--print-query']
  else
    let spec.options += ['--multi']
  endif

  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! siefe#gitbranch(fullscreen) abort
   call SiefeBranchSelect('s:branch_sink', a:fullscreen, 0, 1)
endfunction

function! s:branch_sink(fullscreen, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  let query = a:lines[0]
  let key = a:lines[1]
  " : is not allowed in branch names, so : as a delimiter is not an issue
  let branch = split(a:lines[2],':')[0]

  if key ==# g:siefe_branches_switch_key
    " we need to use execute and then query the result for interative
    " commands like rebase
    execute 'Git switch ' . branch
    let result = FugitiveResult()
    let action = ''
    while result.exit_status != 0
      let action = input(join(readfile(result.file), "\n") . 'Error, stash, open fugitive or abort? (s/f/a) ')
      if action ==# 's'
        FugitiveExecute('stash')
        execute 'Git switch ' . branch
        let result = FugitiveResult()
      elseif action ==# 'f'
        execute 'Git'
        execute 'Git switch ' . branch
        let result = FugitiveResult()
      elseif action ==# 'a'
        let result = {'exit_status' : 0}
      endif
    endwhile

  elseif key ==# g:siefe_branches_rebase_interactive_key
    " we need to use execute and then query the result for interative
    " commands like rebase
    execute 'Git rebase -i ' . branch
    let result = FugitiveResult()
    let action = ''
    while result.exit_status != 0
      let action = input(join(readfile(result.file), "\n") . 'Error, stash, open fugitive or abort? (s/f/a) ')
      if action ==# 's'
        FugitiveExecute('stash')
        execute 'Git rebase --interactive --autosquash ' . branch
        let result = FugitiveResult()
      elseif action ==# 'f'
        execute 'Git'
        execute 'Git rebase --interactive --autosquash ' . branch
        let result = FugitiveResult()
      elseif action ==# 'a'
        let result = {'exit_status' : 0}
      endif
    endwhile
  endif
endfunction

function! SiefeAuthorSelect(func, fullscreen, ...) abort
  let spec = {
    \ 'source':  "git log --format='%aN <%aE>' | awk '" . fzf#shellescape('!') . "x[$0]++'",
    \ 'sink*':   function(a:func, [a:fullscreen] + a:000),
    \ 'options':
      \ [
        \ '--history', s:data_path . '/rg_author_history',
        \ '--multi',
        \ '--expect', g:siefe_abort_key,
        \ '--header', s:prettify_header(g:siefe_abort_key, 'abort'),
        \ '--bind', 'enter:ignore',
        \ '--bind', 'esc:ignore',
        \ '--bind', g:siefe_accept_key . ':accept',
        \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
        \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
        \ '--bind', g:siefe_down_key . ':down',
        \ '--bind', g:siefe_up_key . ':up',
        \ '--bind', g:siefe_next_history_key . ':next-history',
        \ '--bind', g:siefe_previous_history_key . ':previous-history',
        \ ],
    \ 'placeholder': ''
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! SiefeGitPickaxeAuthor(fullscreen, kwargs, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    let a:kwargs.authors = []

  else
    let a:kwargs.authors = a:000[0][1:]

  endif
  call siefe#gitlogfzf(a:fullscreen, a:kwargs)
endfunction

function! SiefeGitPickaxeBranch(fullscreen, kwargs, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    let a:kwargs.branches = ''

  elseif a:000[0][0] == g:siefe_branches_all_key
    let a:kwargs.branches = '--all'

  else
    let a:kwargs.branches = join(map(a:000[0][1:], 'trim(split(v:val, ":")[0], " *")'))

  endif
  call siefe#gitlogfzf(a:fullscreen, a:kwargs)
endfunction

function! SiefeGitPickaxeNotBranch(fullscreen, kwargs, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    let a:kwargs.branches = ''
  else
    let a:kwargs.notbranches = join(map(a:000[0][1:], '"^" . trim(split(v:val, ":")[0], " *")'))
  endif
  call siefe#gitlogfzf(a:fullscreen, a:kwargs)
endfunction

function! SiefeGitPickaxePath(fullscreen, dir, fd_hidden, fd_no_ignore, kwargs, ...) abort
  let key = a:000[0][1]

  if key ==# g:siefe_abort_key
    let a:kwargs.paths = []
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)

  elseif key ==# g:siefe_fd_hidden_key
    let fd_hidden = a:fd_hidden ? 0 : 1
    call SiefeDirSelect('SiefeGitPickaxePath', a:fullscreen, siefe#bufdir(), fd_hidden, a:fd_no_ignore, '', 1, siefe#bufdir(), a:kwargs)

  elseif key ==# g:siefe_fd_no_ignore_key
    let fd_no_ignore = a:fd_no_ignore ? 0 : 1
    call SiefeDirSelect('SiefeGitPickaxePath', a:fullscreen, siefe#bufdir(), a:fd_hidden, fd_no_ignore, '', 1, siefe#bufdir(), a:kwargs)

  elseif key ==# g:siefe_fd_search_git_root_key
    call SiefeDirSelect('SiefeGitPickaxePath', a:fullscreen, siefe#bufdir(), a:fd_hidden, a:fd_no_ignore, '', 1, siefe#get_git_root(), a:kwargs)

  else
    let a:kwargs.paths = a:000[0][2:]
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)
  endif
endfunction

function! siefe#history(fullscreen, kwargs) abort
  call s:check_requirements()

  " default values
  let a:kwargs.query = get(a:kwargs, 'query', '')
  let a:kwargs.project = get(a:kwargs, 'project', 0)
  let a:kwargs.preview = get(a:kwargs, 'preview', g:siefe_history_default_preview_command)

  let bufdir = siefe#bufdir()
  let root = systemlist('git -C ' . fzf#shellescape(bufdir) . ' rev-parse --show-toplevel')[0]
  if !v:shell_error
    let git = 1
    let git_expect = g:siefe_history_git_key . ','
    let project_toggle = a:kwargs.project ? 'off' : 'on'
    let git_help =  ' ╱ ' . s:prettify_header(g:siefe_history_git_key, 'project history:' . project_toggle)
  else
    let git = 0
    let git_expect = ''
    let git_help =  ''
  endif

  if a:kwargs.project && git
    let a:kwargs.source = siefe#recent_git_files_info()
    let project = siefe#get_git_basename_or_bufdir() . ' '
  else
    let a:kwargs.source = siefe#recent_files_info()
    let project = ''
  endif


  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  let spec = {
        \ 'source' : a:kwargs.source,
        \ 'options' : [
          \ '-m',
          \ '--ansi',
          \ '--with-nth', '2..',
          \ '--history', s:data_path . '/rg_history_history',
          \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
          \ '--preview-window', '+{1}-/2,' . default_preview_size,
          \ '--bind', 'enter:ignore',
          \ '--bind', 'esc:ignore',
          \ '--bind', g:siefe_accept_key . ':accept',
          \ '--bind', g:siefe_abort_key . ':abort',
          \ '--bind', g:siefe_down_key . ':down',
          \ '--bind', g:siefe_up_key . ':up',
          \ '--bind', g:siefe_next_history_key . ':next-history',
          \ '--bind', g:siefe_previous_history_key . ':previous-history',
          \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
          \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
          \ '--bind', g:siefe_history_preview_key . ':change-preview:' . s:history_preview_command,
          \ '--bind', g:siefe_history_fast_preview_key . ':change-preview:' . s:history_fast_preview_command,
          \ '--bind', g:siefe_history_faster_preview_key . ':change-preview:' . s:history_faster_preview_command,
          \ '--preview', s:history_preview_commands[a:kwargs.preview],
          \ '--delimiter', '//',
          \ '--expect='
            \ . g:siefe_history_files_key . ','
            \ . g:siefe_history_rg_key . ','
            \ . g:siefe_history_buffers_key . ','
            \ . git_expect
            \ . s:common_window_expect_keys,
          \ '--header-lines',
          \ !empty(expand('%')),
          \ '--print-query',
          \ '--query', a:kwargs.query,
          \ '--prompt', project . 'Hist> ',
          \ '--header',
            \ s:prettify_header(g:siefe_history_files_key, 'rg files')
            \ . ' ╱ ' . s:prettify_header(g:siefe_history_rg_key, 'rg')
            \ . ' ╱ ' . s:prettify_header(g:siefe_history_buffers_key, 'buf')
            \ . git_help
            \ . ' ╱ ' . s:magenta(s:preview_help(s:history_preview_keys), 'Special') . ' change preview'
            \ . "\n" . s:common_window_help
          \ ],
        \ 'sink*': function('s:history_sink', [a:fullscreen, a:kwargs]),
   \ }

  if a:kwargs.project
    let spec.dir = siefe#get_git_root()
  endif

  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:history_sink(fullscreen, kwargs, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  let a:kwargs.query = a:lines[0]
  let key = a:lines[1]

  if key ==# g:siefe_history_git_key
    let a:kwargs.project = a:kwargs.project ? 0 : 1
    call siefe#history(a:fullscreen, a:kwargs)

  elseif key ==# g:siefe_history_buffers_key
    call siefe#buffers(a:fullscreen, a:kwargs)

  elseif key ==# g:siefe_history_files_key
    let a:kwargs.prompt = siefe#get_relative_git_or_bufdir()
    let a:kwargs.files = '//'
    call siefe#ripgrepfzf(
            \ a:fullscreen,
            \ siefe#bufdir(),
            \ a:kwargs
            \ )

  elseif key ==# g:siefe_history_rg_key
    let a:kwargs.prompt = siefe#get_relative_git_or_bufdir()
    let a:kwargs.paths = a:kwargs.source
    let a:kwargs.files = ''
    call siefe#ripgrepfzf(
            \ a:fullscreen,
            \ siefe#bufdir(),
            \ a:kwargs
            \ )

  elseif has_key(s:common_window_actions, key)
    let cmd = s:common_window_actions[key]
    for file in a:lines[2:]
      execute 'silent' cmd fnameescape(split(file, '//')[1])
      normal! zvzz
    endfor

  else
    echom a:lines[2]

    augroup siefe_swap
    autocmd SwapExists * call s:swapchoice(v:swapname)
    augroup END

    execute 'e' fnameescape(split(a:lines[2], '//')[1])
    normal! zvzz

    silent! autocmd! siefe_swap

    if g:siefe_history_loclist
      call s:fill_loc(map(a:lines[2:], "{'filename' : split(v:val, '//')[1] }"))
    else
      call s:fill_quickfix(map(a:lines[2:], "{'filename' : split(v:val, '//')[1] }"))
    endif
  endif

endfunction

function! siefe#gitstash(fullscreen, kwargs, ...) abort
  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'

  let a:kwargs.query = get(a:kwargs, 'query', '')
  let a:kwargs.G = get(a:kwargs, 'G', g:siefe_gitlog_default_G)
  let a:kwargs.regex = get(a:kwargs, 'regex', g:siefe_gitlog_default_regex)
  let a:kwargs.ignore_case = get(a:kwargs, 'ignore_case', g:siefe_gitlog_default_ignore_case)

  let G = a:kwargs.G ? '-G' : '-S'
  let G_prompt = a:kwargs.G ? '-G ' : '-S '
  " --pickaxe-regex and -G are incompatible
  let regex = a:kwargs.G ? '' : a:kwargs.regex ? '--pickaxe-regex ' : ''
  let ignore_case = a:kwargs.ignore_case ? '--regexp-ignore-case ' : ''
  let ignore_case_toggle = a:kwargs.ignore_case ? 'off' : 'on'
  let ignore_case_symbol = a:kwargs.ignore_case ? '-i ' : ''

  let SG_expect = g:siefe_gitlog_sg_key . ','
      \ . g:siefe_gitlog_ignore_case_key . ','
      \ . g:siefe_gitlog_pickaxe_regex_key
  let query_file = tempname()
  let write_query_initial = 'echo '. shellescape(a:kwargs.query) .' > '.query_file.' ;'
  let write_query_reload = 'echo {q} > '.query_file.' ;'
  let format = '--format=%C(blue)%gd • %C(auto)%h • %s %C(green)%cr %C(reset)'
  let command_fmt = s:bin.git_SG
      \ . ' log '
      \ . G
      \ . '%s -z '
      \ . ' --color=always '
      \ . ' ' . regex
      \ . ' ' . ignore_case

  let remove_newlines = '| sed -z -E "s/\r?\n/↵/g"'
  let initial_command = s:logger . write_query_initial . s:logger . printf(command_fmt, shellescape(a:kwargs.query)) . fzf#shellescape(format) . ' -g --first-parent -m "$@" "stash" -- ' . remove_newlines
  let reload_command = s:logger . write_query_reload . s:logger . printf(command_fmt, '{q}').fzf#shellescape(format).' -- ' . remove_newlines

  let current = substitute(fnamemodify(expand('%'), ':p'), FugitiveFind(':/') . '/', '', '')
  let orderfile = tempname()
  call writefile([current], orderfile)

  let suffix = executable('delta') ? '| delta ' . g:siefe_delta_options  : ''

  let preview_all_command = 'echo -e "\033[0;35mgit show all\033[0m" && git -C `git rev-parse --show-toplevel` show --color=always -O'.fzf#shellescape(orderfile).' {1} '
  let preview_command_0 = preview_all_command . ' --patch --stat -- ' . suffix
  let preview_command_1 = preview_all_command . ' --format=format: --patch -- ' . suffix

  let preview_command_2 = 'echo -e "\033[0;35mgit show matching files\033[0m" && ' . s:bin.git_SG . ' -C `git rev-parse --show-toplevel` show ' . G .'"`cat '.query_file.'`" -O'.fzf#shellescape(orderfile).' ' . regex . '--color=always {1} '
    \ . ' --format=format: --patch --stat -- ' . suffix
  let quote = "'"
  let preview_pickaxe_hunks_command = ' bash -c ' . quote . ' echo -e "\033[0;35mgit show matching hunks\033[0m" && (export GREPDIFF_REGEX=`cat ' . query_file . '`; git -C `git rev-parse --show-toplevel` -c diff.external=' . s:bin.pickaxe_diff . ' show {1} -O' . fzf#shellescape(orderfile) . ' --ext-diff ' . regex . G . '"`cat ' . query_file . '`"'
  let no_grepdiff_message = 'echo install grepdiff from the patchutils package for this preview'
  let preview_command_3 = executable('grepdiff') ? preview_pickaxe_hunks_command . ' --format=format: --patch --stat --) ' . quote . suffix : no_grepdiff_message
  let preview_command_4 = 'echo -e "\033[0;35mgit diff\033[0m" && git -C `git rev-parse --show-toplevel` diff --color=always -O'.fzf#shellescape(orderfile).' --patch --stat {1} -- ' . suffix

  let preview_commands = [
    \ preview_command_0,
    \ preview_command_1,
    \ preview_command_2,
    \ preview_command_3,
    \ preview_command_4,
  \ ]


  let spec = {
    \ 'source': initial_command,
    \ 'options':
      \ [
        \ '--history', s:data_path . '/rg_branch_history',
        \ '--ansi',
        \ '--multi',
        \ '--read0',
        \ '--print-query',
        \ '--query', a:kwargs.query,
        \ '--layout=reverse-list',
        \ '--preview', preview_commands[ g:siefe_stash_default_preview_command ],
        \ '--bind', 'enter:ignore',
        \ '--bind', 'esc:ignore',
        \ '--bind', g:siefe_accept_key . ':accept',
        \ '--bind', g:siefe_abort_key . ':abort',
        \ '--bind', g:siefe_stash_preview_0_key . ':change-preview:'.preview_command_0,
        \ '--bind', g:siefe_stash_preview_1_key . ':change-preview:'.preview_command_1,
        \ '--bind', g:siefe_stash_preview_2_key . ':change-preview:'.preview_command_2,
        \ '--bind', g:siefe_stash_preview_3_key . ':change-preview:'.preview_command_3,
        \ '--bind', g:siefe_stash_preview_4_key . ':change-preview:'.preview_command_4,
        \ '--bind', g:siefe_toggle_up_key . ':toggle+down',
        \ '--bind', g:siefe_toggle_down_key . ':toggle+up',
        \ '--bind', g:siefe_down_key . ':down',
        \ '--bind', g:siefe_up_key . ':up',
        \ '--bind', g:siefe_next_history_key . ':next-history',
        \ '--bind', g:siefe_previous_history_key . ':previous-history',
        \ '--preview-window', default_preview_size,
        \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
        \ '--disabled',
        \ '--bind', 'change:reload:'.reload_command,
        \ '--bind', g:siefe_stash_fzf_key . ':unbind(change,' . g:siefe_stash_fzf_key . ')+change-prompt(stash/fzf> )+enable-search+rebind(' . g:siefe_stash_s_key . ')',
        \ '--bind', g:siefe_stash_s_key . ':unbind(change,' . g:siefe_stash_s_key . ')+change-prompt(' . G_prompt . regex . ignore_case_symbol . 'stash> '. ')+disable-search+reload(' . reload_command . ')+rebind(change,' . g:siefe_stash_fzf_key . ')',
        \ '--delimiter', '•',
        \ '--expect='
          \ . g:siefe_stash_apply_key . ','
          \ . g:siefe_stash_pop_key . ','
          \ . g:siefe_stash_drop_key . ','
          \ . g:siefe_stash_sg_key . ','
          \ . g:siefe_stash_pickaxe_regex_key,
        \ '--preview-window', default_preview_size,
        \ '--prompt', G_prompt . regex . ignore_case_symbol . 'stash> ',
        \ '--header='
          \ . s:prettify_header(g:siefe_abort_key, 'abort')
          \ . ' ╱ ' . s:prettify_header(g:siefe_stash_apply_key, 'apply')
          \ . ' ╱ ' . s:prettify_header(g:siefe_stash_pop_key, 'pop')
          \ . ' ╱ ' . s:prettify_header(g:siefe_stash_drop_key, 'drop')
          \ . ' ╱ '  . s:prettify_header(g:siefe_stash_sg_key, 'toggle S/G')
          \ . "\n" . s:prettify_header(g:siefe_stash_ignore_case_key, 'ignore case:' . ignore_case_toggle)
          \ . ' ╱ ' . s:prettify_header(g:siefe_stash_fzf_key,  'fzf messages')
          \ . ' ╱ ' . s:prettify_header(g:siefe_stash_s_key, 'pickaxe')
          \ . ' ╱ ' . s:prettify_header(g:siefe_stash_pickaxe_regex_key, 'regex')
      \ ],
      \ 'sink*': function('s:stash_sink', [a:fullscreen, a:kwargs]),
    \ 'placeholder': ''
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:stash_sink(fullscreen, kwargs, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  let a:kwargs.query = a:lines[0]
  let key = a:lines[1]
  let stashes = map(a:lines[2:], 'split(v:val, "•")[0]')

  if key ==# g:siefe_stash_apply_key
    for stash in stashes
      execute 'Git stash apply ' . stash
    endfor

  elseif key ==# g:siefe_stash_pop_key
    for stash in stashes
      execute 'Git stash pop ' . stash
    endfor

  elseif key ==# g:siefe_stash_drop_key
    for stash in stashes
      execute 'Git stash drop ' . stash
    endfor

  elseif key == g:siefe_stash_sg_key
    let a:kwargs.G = a:kwargs.G ? 0 : 1
    call siefe#gitstash(a:fullscreen, a:kwargs)

  elseif key == g:siefe_stash_ignore_case_key
    let a:kwargs.ignore_case = a:kwargs.ignore_case ? 0 : 1
    call siefe#gitstash(a:fullscreen, a:kwargs)

  elseif key == g:siefe_stash_pickaxe_regex_key
    let a:kwargs.regex = a:kwargs.regex ? 0 : 1
    call siefe#gitstash(a:fullscreen, a:kwargs)

  endif

endfunction

" " ------------------------------------------------------------------
" " Marks
" " ------------------------------------------------------------------
function! s:readbuf_or_file_line(bufnr, filename, pos) abort
  if len(getbufline(a:bufnr, a:pos)) > 0
    return getbufline(a:bufnr, a:pos)
  elseif filereadable(expand(fnameescape(a:filename)))
    let contents = readfile(expand(fnameescape(a:filename)), '', a:pos)
    return len(contents) > 0 ? contents[-1] : ''
  else
    return ''
  endif

endfunction
function! siefe#marks(fullscreen, kwargs) abort
  let a:kwargs.query = get(a:kwargs, 'query', '')

  let git_dir = FugitiveFind(':/')

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  let source = map(getmarklist(),
        \ 'printf("%s//://%s//://%s//://%s//://%s//://%s\t%s\t%s\t%s", v:val.mark[1:], fnameescape(v:val.file), v:val.pos[1], v:val.pos[2], v:val.pos[0], s:red(v:val.mark[1:]), v:val.pos[1], v:val.pos[2], s:get_relative_git_or_bufdir(v:val.file, l:git_dir) . ":". s:blue(s:readbuf_or_file_line(v:val.pos[0], v:val.file, v:val.pos[1])))')
           \ + map(getmarklist(bufnr()),
        \ 'printf("%s//://%s//://%s//://%s//://%s//://%s\t%s\t%s\t%s", v:val.mark[1:], fnameescape(bufname()), v:val.pos[1], v:val.pos[2], v:val.pos[0], s:red(v:val.mark[1:]), v:val.pos[1], v:val.pos[2], s:green(getline(v:val.pos[1])))')
  let spec = {
  \ 'source':  source,
  \ 'sink*':   function('s:marks_sink'),
  \ 'options': [
    \ '--ansi',
    \ '--multi',
    \ '--query', a:kwargs.query,
    \ '--delimiter', '//://',
    \ '--with-nth', '6..',
    \ '--tabstop', '4',
    \ '--preview', s:marks_preview_commands[g:siefe_marks_default_preview_command],
    \ '--preview-window', '+{2}-/2,' . default_preview_size,
    \ '--bind', 'enter:ignore',
    \ '--bind', 'esc:ignore',
    \ '--bind', g:siefe_accept_key . ':accept',
    \ '--bind', g:siefe_abort_key . ':abort',
    \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
    \ '--bind', g:siefe_marks_preview_key . ':change-preview:' . s:marks_preview_command,
    \ '--bind', g:siefe_marks_fast_preview_key . ':change-preview:' . s:marks_fast_preview_command,
    \ '--bind', g:siefe_accept_key . ':accept',
    \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
    \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
    \ '--header', "m\tl\tc\tfile/text"
      \ . "\n" . s:common_window_help,
    \ '--expect', s:common_window_expect_keys . ','
      \ . g:siefe_marks_delete_key . ','
      \ . g:siefe_marks_yank_key,
    \ '--prompt',  'Marks> '
    \ ],
  \ }
  return fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:marks_sink(lines) abort
  if len(a:lines) < 2
    return
  endif

  let filelist = []
  let key = a:lines[0]

  for line in a:lines[1:]
    let [mark, filename, lnum, col, buf_nr, text] = split(line, '//://')
    let file = {}
    let file.type = mark
    let file.filename = filename
    let file.lnum = lnum
    let file.col = col
    let file.text = s:readbuf_or_file_line(buf_nr, filename, lnum)
    let filelist += [file]
  endfor

  if key ==# ''
    augroup siefe_swap
    autocmd SwapExists * call s:swapchoice(v:swapname)
    augroup END

    if !empty(file.filename)
      echom file.filename
      execute 'e' fnameescape(file.filename)
      call cursor(file.lnum, file.col)
      normal! zvzz
    endif

    silent! autocmd! siefe_swap

    if g:siefe_marks_loclist
      call s:fill_loc(filelist)
    else
      call s:fill_quickfix(filelist)
    endif

  elseif key ==# g:siefe_marks_delete_key
    for f in filelist
      call setpos("'" . f.type, [0, 0, 0, 0])
    endfor

  elseif key ==# g:siefe_marks_yank_key
    return s:yank_to_register(join(map(filelist, 'v:val.text'), "\n"))

  elseif has_key(s:common_window_actions, key)
    let cmd = s:common_window_actions[key]

    augroup siefe_swap
    autocmd SwapExists * call s:swapchoice(v:swapname)
    augroup END

    for file in filelist
      execute 'silent' cmd fnameescape(file.filename)
      call cursor(file.line, file.column)
      normal! zvzz
    endfor

    silent! autocmd! siefe_swap
  endif
endfunction

" ------------------------------------------------------------------
" Jumps
" ------------------------------------------------------------------
function! s:jump_format(line) abort
  return substitute(a:line, '[0-9]\+', '\=s:yellow(submatch(0), "Number")', '')
endfunction

function! s:jumps_sink(lines) abort
  if len(a:lines) < 2
    return
  endif

  let key = a:lines[0]
  let [filename, lnum, coln, index , text] = split(a:lines[1], '//://')

  if key ==# ''
    if index < 0
      execute 'normal! ' . -index . "\<C-O>"
    else
      execute 'normal! ' . index . "\<C-I>"
    endif

  elseif key ==# g:siefe_jumps_clear_key
    clearjumps

  elseif key ==# g:siefe_jumps_yank_key
    return s:yank_to_register(text)

  elseif has_key(s:common_window_actions, key)
    let cmd = s:common_window_actions[key]

    augroup siefe_swap
    autocmd SwapExists * call s:swapchoice(v:swapname)
    augroup END

    execute 'silent' cmd fnameescape(filename)
    call cursor(lnum, coln)
    normal! zvzz

    silent! autocmd! siefe_swap
  endif
endfunction

function! s:printjump(git_dir, current, jump_max, lnum_max, index, jump) abort
  if a:jump.bufnr == -1
    return ' //:// //:// //://0//:// '
  endif
  let result = bufname(a:jump.bufnr)
    \ . '//://' . a:jump.lnum
    \ . '//://' . a:jump.col
    \ . '//://' . (a:index - a:current)
    \ . '//://' . abs(a:index - a:current) . repeat(' ', a:jump_max - len(abs(a:index - a:current)) + 1)
    \ . a:jump.lnum . repeat(' ', a:lnum_max - len(a:jump.lnum) + 1)
  if bufnr() == a:jump.bufnr
    return result . s:green(join(getbufline(a:jump.bufnr, a:jump.lnum)))
  else
    return result . s:get_relative_git_or_bufdir(bufname(a:jump.bufnr), a:git_dir) . ': ' . s:blue(s:readbuf_or_file_line(a:jump.bufnr, bufname(a:jump.bufnr), a:jump.lnum))
  endif
endfunction

function! siefe#jumps(fullscreen, kwargs) abort
  let git_dir = FugitiveFind(':/')
  let [jumplist, current] = getjumplist()
  let jump_max = len(abs(len(jumplist) - 2*current))
  let lnum_max =  max(map(copy(jumplist), 'v:val.lnum'))

  " not sure why this is possible, but it is the case when we haven't jumped yet
  if current >= len(jumplist)
    let jumplist += [{'lnum' : 0, 'bufnr' : '-1'}]
  endif

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  let source = map(jumplist, function('s:printjump', [l:git_dir, l:current, l:jump_max, len(l:lnum_max)]))
  let spec = {
  \ 'source':  source,
  \ 'sink*':   function('s:jumps_sink'),
  \ 'options': [
    \ '--ansi',
    \ '--query', a:kwargs.query,
    \ '--delimiter', '//://',
    \ '--with-nth', '5..',
    \ '--tac',
    \ '--sync',
    \ '--cycle',
    \ '--scroll-off', '999',
    \ '--bind', 'start:pos:' . (len(jumplist) - current),
    \ '--preview', s:jumps_preview_commands[g:siefe_jumps_default_preview_command],
    \ '--preview-window', '+{2}-/2,' . default_preview_size,
    \ '--bind', 'enter:ignore',
    \ '--bind', 'esc:ignore',
    \ '--bind', g:siefe_accept_key . ':accept',
    \ '--bind', g:siefe_abort_key . ':abort',
    \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
    \ '--bind', g:siefe_jumps_preview_key . ':change-preview:' . s:jumps_preview_command,
    \ '--bind', g:siefe_jumps_fast_preview_key . ':change-preview:' . s:jumps_fast_preview_command,
    \ '--bind', g:siefe_accept_key . ':accept',
    \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
    \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
    \ '--header', "m\tl\tc\tfile/text" . 'current:' . current
      \ . "\n" . s:common_window_help,
    \ '--expect', s:common_window_expect_keys . ','
      \ . g:siefe_jumps_yank_key,
    \ '--prompt',  'Jumps> '
    \ ],
  \ }
  return fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

" ------------------------------------------------------------------
" Maps
" ------------------------------------------------------------------
function! s:align_pairs(list) abort
  let maxlen = 0
  let pairs = []
  for elem in a:list
    let match = matchlist(elem, '^\(\S*\)\s*\(.*\)$')
    let [_, k, v] = match[0:2]
    let maxlen = max([maxlen, len(k)])
    call add(pairs, [k, substitute(v, '^\*\?[@ ]\?', '', '')])
  endfor
  let maxlen = min([maxlen, 35])
  return map(pairs, "printf('%-'.maxlen.'s', v:val[0]).' '.v:val[1]")
endfunction

function! s:highlight_keys(str) abort
  return substitute(
        \ substitute(a:str, '<[^ >]\+>', s:yellow('\0', 'Special'), 'g'),
        \ '<Plug>', s:blue('<Plug>', 'SpecialKey'), 'g')
endfunction

function! SiefeModeSelect(fullscreen, query) abort
  let options = [
    \ '--history', s:data_path . '/git_dir_history',
    \ '--ansi',
    \ '--multi',
    \ '--bind', 'enter:ignore',
    \ '--bind', 'esc:ignore',
    \ '--bind', g:siefe_accept_key . ':accept',
    \ '--bind', g:siefe_abort_key . ':abort',
    \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
    \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
    \ '--bind', g:siefe_down_key . ':down',
    \ '--bind', g:siefe_up_key . ':up',
    \ '--bind', g:siefe_next_history_key . ':next-history',
    \ '--bind', g:siefe_previous_history_key . ':previous-history',
    \ '--bind', g:siefe_modes_select_all_key . ':select-all',
    \ '--bind', g:siefe_modes_select_all_key . ':select-all',
    \ '--prompt', 'mode> ',
    \ '--header', s:prettify_header(g:siefe_abort_key, 'abort')
      \ . ' ╱ ' . s:prettify_header(g:siefe_modes_select_all_key, 'select all')
    \ ]

  call fzf#run(fzf#wrap({
        \ 'source': [
          \ s:red('n') . ' # Normal',
          \ s:red('v') . ' # Visual and Select',
          \ s:red('s') . ' # Select',
          \ s:red('x') . ' # Visual',
          \ s:red('o') . ' # Operator-pending',
          \ s:red('i') . ' # Insert',
          \ s:red('l') . ' # Insert, Command-line, Lang-Arg',
          \ s:red('c') . ' # Command-line',
          \ s:red('t') . ' # Terminal-Job',
        \ ],
        \ 'options': options,
        \ 'sink*': function('siefe#maps', [a:fullscreen, a:query] + a:000)
      \ }, a:fullscreen))
endfunction


function! s:key_sink(fullscreen, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  let query = a:lines[0]
  let key = a:lines[1]

  let file = split(a:lines[2], '•')[0]
  let lnum = split(a:lines[2], '•')[1]
  let mode = split(a:lines[2], '•')[2]
  let map  = split(a:lines[2], '•')[3]

  if key ==# g:siefe_maps_open_key
    execute 'e' fnameescape(file)
    call cursor(lnum, 0)
    normal! zvzz

  elseif key ==# g:siefe_maps_modes_key
    call SiefeModeSelect(a:fullscreen, query)

  else
    redraw
    let map_gv  = l:mode ==# 'x' ? 'gv' : ''
    let map_cnt = v:count ==# 0 ? '' : v:count
    let map_reg = empty(v:register) ? '' : ('"' . v:register)
    let map_op  = l:mode ==# 'o' ? v:operator : ''
    call feedkeys(l:map_gv . l:map_cnt . l:map_reg, 'n')
    call feedkeys(l:map_op .
          \ substitute(l:map, '<[^ >]\+>', '\=eval("\"\\".submatch(0)."\"")', 'g'))
  endif
endfunction

function! siefe#maps(fullscreen, query, modes) abort

  let l:modes = map(a:modes, 'split(v:val)[0]')
  let maps = filter(maplist(), 'index(l:modes, v:val.mode) >= 0')
  let max_len = max(map(copy(maps), 'len(v:val.lhs)'))
  let maps = map(copy(maps), 'getscriptinfo({"sid" : v:val.sid})[0].name . "•" . v:val.lnum . "•" . v:val.mode . "•" . v:val.lhs . "•" . s:red(v:val.mode) . " " .v:val.lhs . repeat(" ", max_len - len(v:val.lhs) + 1) . v:val.rhs . "\t" . s:blue(fnamemodify(getscriptinfo({"sid" : v:val.sid})[0].name, ":t") . ":" . v:val.lnum)')
  let sorted = sort(maps)
  let colored = map(sorted, 's:highlight_keys(v:val)')
  "let pcolor  = a:mode == 'x' ? 9 : a:mode == 'o' ? 10 : 12

  let spec =  {
  \ 'source':  colored,
  \ 'sink*':    function('s:key_sink', [a:fullscreen]),
  \ 'options': [
    \ '--prompt', 'Maps ('.join(l:modes, '/').')> ',
    \ '--delimiter', '•',
    \ '--with-nth', '5..',
    \ '--print-query',
    \ '--ansi',
    \ '--query', a:query,
    \ '--bind', 'enter:ignore',
    \ '--bind', 'esc:ignore',
    \ '--bind', g:siefe_accept_key . ':accept',
    \ '--bind', g:siefe_abort_key . ':abort',
    \ '--expect',
      \ g:siefe_maps_open_key . ','
      \ . g:siefe_maps_modes_key,
    \ '--header', s:prettify_header(g:siefe_accept_key, 'execute')
      \ . ' ╱ ' . s:prettify_header(g:siefe_maps_open_key, 'open location')
      \ . ' ╱ ' . s:prettify_header(g:siefe_maps_modes_key, 'modes')
      \ . ' ╱ ' . s:prettify_header(g:siefe_abort_key, 'abort'),
  \ ],
  \ }

  return fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

" ------------------------------------------------------------------
" Registers
" ------------------------------------------------------------------

function! s:get_all_registers() abort
  let regnames = map(range(char2nr('a'), char2nr('z')) + range(char2nr('0'), char2nr('9')), 'nr2char(v:val)') + ['"','-','*','%','/','.','#',':']
  return map(copy(regnames), '[v:val, getreginfo(v:val)]')
endfunction

function! s:printreg(reg) abort
  return s:red('"' . a:reg[0]) . ' ' . s:blue(join(a:reg[1].regcontents, '↵'))
endfunction

function! s:regsave() abort
  let file = getbufvar(bufnr(''), 'siefe_tempfile')
  let reg = getbufvar(bufnr(''), 'siefe_reg')
  let contents = readfile(file)[1:]
  let reg_amode = getregtype(reg)
  call setreg(reg, contents, reg_amode)
  call delete(file)
endfunction

function! s:registers_sink(lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  let key = a:lines[0]
  let reg = split(a:lines[1], ' ')[0][1]

  if key ==# g:siefe_registers_paste_key
    execute 'put ' . l:reg

  elseif key ==# g:siefe_registers_execute_key
    execute 'normal @' . l:reg

  elseif key ==# g:siefe_registers_clear_key
    execute 'normal @' . l:reg
    call setreg(l:reg, [], getregtype(l:reg))

  else
    let tempfile = tempname()
    execute 'split ' . tempfile
    call append(0, '### Editing register `' . l:reg . '`. Add control characters by preceding them with `ctrl-v` ###')
    execute 'put ' . l:reg
    execute '2delete _'
    call matchaddpos('Error', [1])
    call setbufvar(bufnr(''), 'siefe_reg', reg)
    call setbufvar(bufnr(''), 'siefe_tempfile', tempfile)

    augroup siefe_registers
    autocmd BufWritePost <buffer> call s:regsave()
    augroup END
  endif

endfunction

function! siefe#registers(fullscreen, kwargs) abort

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  let spec = {
        \ 'source': map(filter(s:get_all_registers(), 'v:val[1] != {}'), 's:printreg(v:val)'),
  \ 'sink*':  function('s:registers_sink'),
  \ 'options': [
    \ '--ansi',
    \ '--query', a:kwargs.query,
    \ '--delimiter', ' ',
    \ '--sync',
    \ '--bind', 'enter:ignore',
    \ '--bind', 'esc:ignore',
    \ '--bind', g:siefe_registers_edit_key . ':accept',
    \ '--bind', g:siefe_abort_key . ':abort',
    \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
    \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
    \ '--expect',
      \ g:siefe_registers_paste_key . ','
      \ . g:siefe_registers_execute_key . ','
      \ . g:siefe_registers_clear_key,
    \ '--header', s:prettify_header(g:siefe_registers_edit_key, 'edit')
      \ . ' ╱ ' . s:prettify_header(g:siefe_registers_paste_key, 'paste')
      \ . ' ╱ ' . s:prettify_header(g:siefe_registers_execute_key, 'execute')
      \ . ' ╱ ' . s:prettify_header(g:siefe_registers_clear_key, 'clear')
      \ . ' ╱ ' . s:prettify_header(g:siefe_abort_key, 'abort'),
    \ '--prompt',  'Regs> '
    \ ],
  \ }
  return fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction


""" helper functions
function! s:warn(message) abort
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function!  siefe#bufdir() abort
  if &ft ==# 'git'
    return FugitiveFind(':/')
  else
    return expand('%:p:h')
  endif
endfunction

function! siefe#get_git_root() abort
  return FugitiveFind(':/')
endfunction

function! siefe#get_git_basename_or_bufdir() abort
  let root = FugitiveFind(':/')
  if root ==# ''
    return expand('%:p:h')
  else
   return fnamemodify(root, ':t')
  endif
endfunction

function! siefe#get_relative_git_or_bufdir(...) abort
  let bufdir = siefe#bufdir()
  if a:0 == 0
    let rel_dir = trim(system('git -C '. fzf#shellescape(bufdir) .' rev-parse --show-prefix'))
    return v:shell_error ? bufdir : '#'.split(system('basename `git -C ' . fzf#shellescape(bufdir) . ' rev-parse --show-toplevel`'), '\n')[0].'/'.rel_dir
  else
    let dir = get(a:, 1, '')
    let git_dir = trim(system('git -C '. fzf#shellescape(bufdir) .' rev-parse --show-toplevel'))
    let rel_to_dir = v:shell_error ? bufdir : git_dir
    let prefix = v:shell_error ? '' : siefe#get_git_basename_or_bufdir().'/'
    return prefix.trim(system('realpath --relative-to='.rel_to_dir.' '.dir))
  endif
endfunction

function! siefe#get_relative_git_or_buf(...) abort
  if a:0 == 0
    return substitute(fnamemodify(expand('%'), ':p'), FugitiveFind(':/') . '/', '', '')
  else
    return substitute(fnamemodify(expand(a:1), ':p'), FugitiveFind(':/') . '/', '', '')
  endif

endfunction

function! siefe#recent_files_info() abort
  return siefe#_uniq_with_prefix(
        \ map(filter([expand('%')], 'len(v:val)'), 'line(".") . "//" . fnamemodify(v:val, ":~:.")')
        \ + map(filter(siefe#_buflisted_sorted(), 'len(bufname(v:val))'), "getbufinfo(v:val)[0]['lnum'] . '//' . fnamemodify(expand(bufname(v:val)), ':~:.')")
        \ + map(filter(map(siefe#oldfiles(), 'v:val'), "filereadable(fnamemodify(expand(v:val.name), ':p'))"),
        \ 'v:val.line . "//" . fnamemodify(expand(v:val.name), ":~:.")'), '//')
endfunction

function! siefe#recent_git_files_info() abort
  let git_dir = FugitiveFind(':/')
  if git_dir ==# ''
    echom 'not in a git dir'
  endif
  return siefe#_uniq_with_prefix(
        \ map(filter([expand('%')], 'len(v:val)'), 'line(".") . "//" . substitute(FugitiveReal(), l:git_dir . "/", "", "")')
        \ + map(filter(map(siefe#_buflisted_sorted(), 'fnameescape(bufname(v:val))'), 'len(v:val) && fnamemodify(expand(fnameescape(bufname(v:val))), ":p") =~# "^' . l:git_dir . '"'), "getbufinfo(v:val)[0]['lnum'] . '//' . substitute(fnamemodify(expand(fnameescape(bufname(v:val))), ':p'), l:git_dir . '/' , '', '')")
        \ + map(filter(map(siefe#oldfiles(), 'v:val'), "filereadable(fnamemodify(expand(fnameescape(v:val.name)), ':p')) && expand(fnameescape(v:val.name)) =~# '^" . l:git_dir . "'"),
        \ 'v:val.line . "//" . substitute(expand(fnameescape(v:val.name)), l:git_dir . "/", "", "")'), '//')
endfunction

function! siefe#recent_files(...) abort
  if a:0 == 0
    let dir = FugitiveFind(':/')
  else
    let dir = get(a:, 1, '')
  endif
  if dir ==# ''
    return siefe#_uniq_with_prefix(
          \ map(filter([expand('%')], 'len(v:val)'), 'fnamemodify(v:val, ":~:.")')
          \ + map(filter(siefe#_buflisted_sorted(), 'len(bufname(v:val))'), "fnamemodify(expand(bufname(v:val)), ':~:.')")
          \ + map(filter(map(siefe#oldfiles(), 'v:val'), "filereadable(fnamemodify(expand(v:val.name), ':p'))"),
          \ 'fnamemodify(expand(v:val.name), ":~:.")'), '')
  else
    return siefe#_uniq_with_prefix(
          \ map(filter([expand('%')], 'len(v:val)'), 'substitute(FugitiveReal(), l:dir . "/", "", "")')
          \ + map(filter(map(siefe#_buflisted_sorted(), 'fnameescape(bufname(v:val))'), 'len(v:val) && fnamemodify(expand(fnameescape(bufname(v:val))), ":p") =~# "^' . l:dir . '"'), "substitute(fnamemodify(expand(fnameescape(bufname(v:val))), ':p'), l:dir . '/' , '', '')")
          \ + map(filter(map(siefe#oldfiles(), 'v:val'), "filereadable(fnamemodify(expand(fnameescape(v:val.name)), ':p')) && expand(fnameescape(v:val.name)) =~# '^" . l:dir . "'"),
          \ 'substitute(expand(fnameescape(v:val.name)), l:dir . "/", "", "")'), '')
  endif
endfunction

function! siefe#_uniq_with_prefix(list, prefix) abort
  let visited = {}
  let ret = []
  for l in a:list
    let prefix_file = split(l, a:prefix)
    let f = len(prefix_file) == 1 ? prefix_file[0] : join(prefix_file[1:], '')
    if !empty(f) && !has_key(visited, f)
      call add(ret, l)
      let visited[f] = 1
    endif
  endfor
  return ret
endfunction


function! siefe#oldfiles() abort
  let viminfo = readfile($HOME . '/.viminfo')
  let oldfiles = []
  let name_found = v:false
  let long_line = v:false
  let loc_found = v:false
  let start = v:false
  for line in viminfo
    if !start
      if line ==# '# History of marks within files (newest to oldest):'
        let start = v:true
      endif
    elseif long_line
      let filename_match = matchlist(line, '^<\(.*\)$')
      let name_found = v:true
      let oldfile = [{'name' : filename_match[1], 'line' : 0, 'column' : 0}]
      let long_line = v:false
    elseif !name_found
      let filename_match = matchlist(line, '^> \(.*\)$')
      if len(filename_match) > 0
        if len(matchlist(filename_match[1], '[\x16]\([0-9]\+\)')) > 0
          let long_line = v:true
        else
          let name_found = v:true
          let oldfile = [{'name' : filename_match[1], 'line' : 0, 'column' : 0}]
        endif
      endif
    elseif !loc_found
        let mark_match = matchlist(line, '^\t\(.\)\t\([0-9]\+\)\t\([0-9]\+\)$')
        if mark_match[1] ==# '"'
          let oldfile[0].line   = mark_match[2]
          let oldfile[0].column = mark_match[3]
          let loc_found = v:true
        endif
    elseif line ==# ''
      let name_found = v:false
      let loc_found = v:false
      let oldfiles += oldfile
    endif
  endfor
  return oldfiles
endfunction

" ------------------------------------------------------------------
" Buffers
" ------------------------------------------------------------------
"

function! s:find_open_window(b) abort
  let [tcur, tcnt] = [tabpagenr() - 1, tabpagenr('$')]
  for toff in range(0, tabpagenr('$') - 1)
    let t = (tcur + toff) % tcnt + 1
    let buffers = tabpagebuflist(t)
    for w in range(1, len(buffers))
      let b = buffers[w - 1]
      if b == a:b
        return [t, w]
      endif
    endfor
  endfor
  return [0, 0]
endfunction

function! s:jump(t, w) abort
  execute a:t.'tabnext'
  execute a:w.'wincmd w'
endfunction

function! s:get_relative_git_or_bufdir(name, git_dir) abort
  if !empty(a:git_dir)
    return s:green('√') . substitute(fnameescape(fnamemodify(expand(a:name), ':p')), a:git_dir . '' , '', '')
  else
    return fnameescape(fnamemodify(expand(bufname(0)), ':p:~:.'))
  endif
endfunction

function! siefe#_format_buffer(b, git_dir) abort
  let name = fnameescape(bufname(a:b))
  let line = exists('*getbufinfo') ? getbufinfo(a:b)[0]['lnum'] : 0
  let name = empty(name) ? '[No Name]' : fnamemodify(name, ':p:~:.')
  let flag = a:b == bufnr('')  ? s:blue('%', 'Conditional') :
          \ (a:b == bufnr('#') ? s:magenta('#', 'Special') : ' ')
  let modified = getbufvar(a:b, '&modified') ? s:red('+', 'Exception') : ''
  let modifiable = getbufvar(a:b, '&modifiable') ? '' : s:red('-', 'Exception')
  let readonly = getbufvar(a:b, '&readonly') ? s:green(' RO', 'Constant') : ''
  let line_text = line == 0 ? '' : ' line ' . line
  let extra = modified . modifiable
  let extra = empty(extra) ? readonly : s:red(' [', 'Exception') . modified . modifiable . s:red('] ', 'Exception') . readonly
  let rel_name = substitute(fnamemodify(expand(fnameescape(bufname(a:b))), ':p'), a:git_dir . '/' , '', '')
  let rel_name = empty(a:git_dir) ? rel_name : s:green('√') . '/' .rel_name
  return s:strip(printf("%s//%d//[%s] %s\t%s%s\t%s", name, line, s:yellow(a:b, 'Number'), flag, rel_name, extra,  line_text))
endfunction

function! s:sort_buffers(...) abort
  let [b1, b2] = map(copy(a:000), 'get(g:siefe#buffers, v:val, v:val)')
  " Using minus between a float and a number in a sort function causes an error
  return b1 < b2 ? 1 : -1
endfunction

function! s:buflisted() abort
  return filter(range(1, bufnr('$')), 'buflisted(v:val) && getbufvar(v:val, "&filetype") !=# "qf"')
endfunction

function! siefe#_buflisted_sorted() abort
  return sort(s:buflisted(), 's:sort_buffers')
endfunction

function! siefe#buffers(fullscreen, kwargs) abort
  let a:kwargs.query = get(a:kwargs, 'query', '')
  let a:kwargs.project = get(a:kwargs, 'project', '')

  let git_dir = FugitiveFind(':/')
  if git_dir !=# ''
    let project_toggle = a:kwargs.project ? 'off' : 'on'
    let git_help =  ' ╱ ' . s:prettify_header(g:siefe_history_git_key, 'project history:' . project_toggle)
    let git_expect = g:siefe_buffers_git_key . ','
  else
    let git_help =  ''
    let git_expect = ''
  endif
  if git_dir !=# '' && a:kwargs.project
    let project = siefe#get_git_basename_or_bufdir() . ' '
    let sorted = filter(siefe#_buflisted_sorted(), 'len(v:val) && fnamemodify(fnameescape(expand(bufname(v:val))), ":p") =~# "^' . l:git_dir . '"')
  else
    let project = ''
    let sorted = siefe#_buflisted_sorted()
  endif
  let header_lines = '--header-lines=' . (bufnr('') == get(sorted, 0, 0) ? 1 : 0)
  let tabstop = len(max(sorted)) >= 4 ? 9 : 8

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  let spec = {
    \ 'source': map(sorted, 'siefe#_format_buffer(v:val, l:git_dir)'),
    \ 'options': [
      \ '--multi',
      \ '--tiebreak=index',
      \ '--header', s:prettify_header(g:siefe_buffers_delete_key, 'delete')
        \ . ' ╱ ' . s:prettify_header(g:siefe_buffers_history_key, 'history')
        \ . git_help
        \ . "\n" . s:common_window_help,
      \ header_lines,
      \ '--ansi',
      \ '--delimiter', '//',
      \ '--bind', 'enter:ignore',
      \ '--bind', 'esc:ignore',
      \ '--bind', g:siefe_buffers_preview_key . ':change-preview:' . s:buffers_preview_command,
      \ '--bind', g:siefe_buffers_fast_preview_key . ':change-preview:' . s:buffers_fast_preview_command,
      \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
      \ '--bind', g:siefe_toggle_up_key . ':toggle+up',
      \ '--bind', g:siefe_toggle_down_key . ':toggle+down',
      \ '--preview', s:buffers_preview_commands[g:siefe_buffers_default_preview_command],
      \ '--preview-window', '+{2}-/2,' . default_preview_size,
      \ '--with-nth', '3..',
      \ '-n', '2,1..2',
      \ '--prompt', project . 'Buf> ',
      \ '--query', a:kwargs.query,
      \ '--print-query',
      \ '--tabstop', tabstop,
      \ '--bind', g:siefe_accept_key . ':accept',
      \ '--bind', g:siefe_abort_key . ':abort',
      \ '--expect',
        \   g:siefe_buffers_delete_key . ','
        \ . g:siefe_buffers_history_key . ','
        \ . git_expect
        \ . s:common_window_expect_keys,
    \ ],
    \ 'sink*': function('s:buffers_sink', [a:fullscreen, a:kwargs]),
  \}

  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:buffers_sink(fullscreen, kwargs, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  let a:kwargs.query = a:lines[0]
  let key = a:lines[1]
  let buffer_numbers = map(a:lines[2:], {_idx, bufline -> str2nr(matchstr(bufline, '\[\zs[0-9]*\ze\]'))})

  if key ==# g:siefe_buffers_delete_key
    if len(buffer_numbers) == 0
      return
    endif

    for bufnr in buffer_numbers
      let readonly = getbufvar(bufnr, '&readonly')
      let modified = getbufvar(bufnr, '&modified')
      if !modified
        execute 'bdelete' bufnr
      elseif modified && !readonly
        while v:true
         let action = input('buffer "' . bufname(bufnr) . '" has been modified. Save, discard or abort? (s/d/a) ')
         if action ==# 's' || action ==# 'save'
           let cur_bufnr = bufnr('%')
           set lazyredraw
           execute 'buffer' bufnr
           update
           execute 'buffer' cur_bufnr
           set nolazyredraw
           break
         elseif action ==# 'd' || action ==# 'discard'
           execute 'bdelete!' bufnr
           break
         elseif action ==# 'a' || action ==# 'abort'
           break
         endif
        endwhile
      elseif modified && readonly
        while v:true
         let action = input('buffer "' . bufname(bufnr) . '" has been modified, but is readonly. Discard or abort? (d/a) ')
         if action ==# 'd' || action ==# 'discard'
           execute 'bdelete!' bufnr
           break
         elseif action ==# 'a' || action ==# 'abort'
           break
         endif
        endwhile
      endif
    endfor
    call siefe#buffers(a:fullscreen, a:kwargs)

  elseif key ==# g:siefe_buffers_git_key
    let a:kwargs.project = a:kwargs.project ? 0 : 1
    call siefe#buffers(a:fullscreen, a:kwargs)

  elseif key ==# g:siefe_buffers_history_key
    call siefe#history(a:fullscreen, a:kwargs)

  elseif has_key(s:common_window_actions, key)
    " no match
    if len(buffer_numbers) == 0
      return
    endif

    let cmd = s:common_window_actions[key]
    for bufnr in buffer_numbers
      execute 'silent' cmd
      execute 'silent buffer' bufnr
      normal! zvzz
    endfor

  else
    if len(buffer_numbers) == 0
      return
    endif

    let b = buffer_numbers[0]

    if empty(key) && get(g:, 'siefe_buffers_jump')
      let [t, w] = s:find_open_window(b)
      if t
        call s:jump(t, w)
        return
      endif
    endif

    execute 'buffer' b
  endif
endfunction

function! siefe#toggle_git_status() abort
  if len(map(filter(range(1, bufnr('$')), 'getbufvar(v:val, "&filetype") ==# "fugitive"'), { _,bufnr -> execute( 'bdelete ' . bufnr )})) == 0
    keepalt Git
  endif
endfunction

function! s:detect_dups(lst) abort
  let dict = {}
  let dups = ''
  for item in a:lst
    if has_key(dict, item)
      let dups .= ' ' . item
    endif
    let dict[item] = '0'
  endfor
  return dups
endfunction

function! s:reduce(list, f) abort
  if v:version < 900
    let [acc; tail] = a:list
    while !empty(tail)
      let [head; tail] = tail
      let acc = a:f(acc, head)
    endwhile
    return acc
  else
    return reduce(a:list, a:f)
  endif
endfunction

function! s:strip(str) abort
  return substitute(a:str, '^\s*\|\s*$', '', 'g')
endfunction


" https://stackoverflow.com/a/47051271
function! siefe#visual_selection() abort
    if mode() ==# 'v'
        let [line_start, column_start] = getpos('v')[1:2]
        let [line_end, column_end] = getpos('.')[1:2]
    else
        let [line_start, column_start] = getpos("'<")[1:2]
        let [line_end, column_end] = getpos("'>")[1:2]
    end
    if (line2byte(line_start)+column_start) > (line2byte(line_end)+column_end)
        let [line_start, column_start, line_end, column_end] =
        \   [line_end, column_end, line_start, column_start]
    end
    let lines = getline(line_start, line_end)
    if len(lines) == 0
            return ''
    endif
    let lines[-1] = lines[-1][: column_end - 1]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction

function! siefe#visual_line_nu() abort
    if mode() ==# 'v'
        let line_start = getpos('v')[1]
        let line_end = getpos('.')[1]
    else
        let line_start = getpos("'<")[1]
        let line_end = getpos("'>")[1]
    end
    return sort([line_start, line_end], 'n')

endfunction

" workaround for https://github.com/junegunn/fzf/issues/2895
function! s:swapchoice(swapname) abort
  let info = swapinfo(a:swapname)
  let modified =  info.dirty == 1 ? 'yes' : 'no'
   while v:swapchoice !=# 'o'
         \ && v:swapchoice !=# 'e'
         \ && v:swapchoice !=# 'r'
         \ && v:swapchoice !=# 'q'
         \ && v:swapchoice !=# 'a'
    let v:swapchoice = input('found a swap file by the name "' . a:swapname . '"'
       \ . "\nuser: " . info.user . '@' . info.host
       \ . "\npid: " . info.pid
       \ . "\nmodified: " .  modified
       \ . "\n[O]pen Read-Only (default), (E)dit anyway, (R)ecover, (Q)uit, (A)bort: ", 'o')
   endwhile
endfunction
