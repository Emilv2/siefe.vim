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

let s:data_path = expand($XDG_DATA_HOME) != '' ?  expand($XDG_DATA_HOME) . '/siefe.vim' : expand($HOME) . '/.local/share/siefe.vim'
if !isdirectory(s:data_path)
  call mkdir(s:data_path, 'p')
endif

let s:logger = s:bin.logger . ' '. s:data_path . '/error_log '

""" load configuration options
let g:siefe_delta_options = get(g:, 'siefe_delta_options', '--keep-plus-minus-markers') . ' ' . get(g:, 'siefe_delta_extra_options', '')
let g:siefe_bat_options = get(g:, 'siefe_bat_options', '--style=numbers,changes') . ' ' . get(g:, 'siefe_bat_extra_options', '')

let g:siefe_abort_key = get(g:, 'siefe_abort_key', 'esc')
let g:siefe_next_history_key = get(g:, 'siefe_next_history_key', 'ctrl-n')
let g:siefe_previous_history_key = get(g:, 'siefe_previous_history_key', 'ctrl-p')
let g:siefe_up_key = get(g:, 'siefe_up_key', 'ctrl-k')
let g:siefe_down_key = get(g:, 'siefe_down_key', 'ctrl-j')
let g:siefe_accept_key = get(g:, 'siefe_accept_key', 'ctrl-m')

let s:common_keys = [
  \ g:siefe_abort_key,
  \ g:siefe_next_history_key,
  \ g:siefe_previous_history_key,
  \ g:siefe_up_key,
  \ g:siefe_down_key,
  \ g:siefe_accept_key,
\ ]

let g:siefe_preview_hide_threshold = str2nr(get(g:, 'siefe_preview_hide_threshold', 80))
let g:siefe_default_preview_size = str2nr(get(g:, 'siefe_default_preview_size', 50))
let g:siefe_2nd_preview_size = str2nr(get(g:, 'siefe_2nd_preview_size', 80))


let g:siefe_rg_fzf_key = get(g:, 'siefe_rg_fzf_key', 'ctrl-f')
let g:siefe_rg_rg_key = get(g:, 'siefe_rg_rg_key', 'ctrl-r')
let g:siefe_rg_rgfzf_key = get(g:, 'siefe_rg_rgfzf_key', 'alt-f')
let g:siefe_rg_files_key = get(g:, 'siefe_rg_files_key', 'ctrl-l')
let g:siefe_rg_type_key = get(g:, 'siefe_rg_type_key', 'ctrl-t')
let g:siefe_rg_type_not_key = get(g:, 'siefe_rg_type_not_key', 'ctrl-^')
let g:siefe_rg_word_key = get(g:, 'siefe_rg_word_key', 'ctrl-w')
let g:siefe_rg_case_key = get(g:, 'siefe_rg_case_key', 'ctrl-s')
let g:siefe_rg_hidden_key = get(g:, 'siefe_rg_hidden_key', 'alt-.')
let g:siefe_rg_no_ignore_key = get(g:, 'siefe_rg_no_ignore_key', 'ctrl-u')
let g:siefe_rg_fixed_strings_key = get(g:, 'siefe_rg_fixed_strings_key', 'ctrl-x')
let g:siefe_rg_max_1_key = get(g:, 'siefe_rg_max_1_key', 'ctrl-a')
let g:siefe_rg_search_zip_key = get(g:, 'siefe_rg_search_zip_key', 'alt-z')
let g:siefe_rg_dir_key = get(g:, 'siefe_rg_dir_key', 'ctrl-d')
let g:siefe_rg_buffers_key = get(g:, 'siefe_rg_buffers_key', 'ctrl-b')
let g:siefe_rg_yank_key = get(g:, 'siefe_rg_yank_key', 'ctrl-y')

let g:siefe_rg_preview_key = get(g:, 'siefe_rg_preview_key', 'f1')
let g:siefe_rg_fast_preview_key = get(g:, 'siefe_rg_fast_preview_key', 'f2')

let s:rg_preview_keys = [
  \ g:siefe_rg_preview_key,
  \ g:siefe_rg_fast_preview_key,
\ ]

let s:bat_command = executable('batcat') ? 'batcat' : executable('bat') ? 'bat' : ''
let s:fd_command = executable('fdfind') ? 'fdfind' : executable('fd') ? 'fd' : ''
let s:files_preview_command = s:bat_command !=# '' ? s:bin.preview . ' {} '. s:bat_command . ' --color=always --pager=never ' . g:siefe_bat_options . ' -- ' : s:bin.preview . ' {} cat'
let s:rg_preview_command = s:bat_command !=# '' ? s:bin.preview . ' {1} ' . s:bat_command . ' --color=always --highlight-line={2} --pager=never ' . g:siefe_bat_options . ' -- ' : s:bin.preview . ' {1} cat'
let s:rg_fast_preview_command = s:bin.preview . ' {1} cat'

let s:rg_preview_commands = [
  \ s:rg_preview_command,
  \ s:rg_fast_preview_command,
\ ]

let s:rg_keys = [
  \ g:siefe_rg_fzf_key,
  \ g:siefe_rg_rg_key,
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
  \ g:siefe_rg_dir_key,
  \ g:siefe_rg_buffers_key,
  \ g:siefe_rg_yank_key,
\ ] + s:rg_preview_commands
  \ + s:common_keys

let g:siefe_toggle_preview_key = get(g:, 'siefe_toggle_preview_key', 'ctrl-/')

let g:siefe_rg_default_preview_command = get(g:, 'siefe_rg_default_preview', 0)

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

let g:siefe_gitlog_default_G = get(g:, 'siefe_gitlog_default_G', 0)
let g:siefe_gitlog_default_regex = get(g:, 'siefe_gitlog_default_regex', 0)
let g:siefe_gitlog_default_follow = get(g:, 'siefe_gitlog_default_follow', 0)
let g:siefe_gitlog_default_ignore_case = get(g:, 'siefe_gitlog_default_ignore_case', 0)

let g:siefe_rg_default_word = get(g:, 'siefe_rg_default_word', 0)
let g:siefe_rg_default_case_sensitive = get(g:, 'siefe_rg_default_case_sensitive', 0)
let g:siefe_rg_default_hidden = get(g:, 'siefe_rg_default_hidden', 0)
let g:siefe_rg_default_no_ignore = get(g:, 'siefe_rg_default_no_ignore', 0)
let g:siefe_rg_default_fixed_strings = get(g:, 'siefe_rg_default_fixed_strings', 0)
let g:siefe_rg_default_max_1 = get(g:, 'siefe_rg_default_max_1', 0)
let g:siefe_rg_default_search_zip = get(g:, 'siefe_rg_default_search_zip', 0)

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
  let a:kwargs.orig_dir = get(a:kwargs, 'orig_dir', a:dir)
  let a:kwargs.paths = get(a:kwargs, 'paths', [])
  let a:kwargs.type = get(a:kwargs, 'type', '')
  let a:kwargs.files = get(a:kwargs, 'files', '')

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

  let paths = join(map(copy(a:kwargs.paths), 'shellescape(v:val)'), ' ')

  let word = a:kwargs.word ? '-w ' : ''
  let word_toggle = a:kwargs.word ? 'off' : 'on'
  let hidden = a:kwargs.hidden ? '-. ' : ''
  let hidden_option = a:kwargs.hidden ? '--hidden ' : ''
  let hidden_toggle = a:kwargs.hidden ? 'off' : 'on'
  let case_sensitive = a:kwargs.case_sensitive ? '--case-sensitive ' : '--smart-case '
  let case_symbol = a:kwargs.case_sensitive ? '-s ' : ''
  let no_ignore = a:kwargs.no_ignore ? '-u ' : ''
  let no_ignore_toggle = a:kwargs.no_ignore ? 'off' : 'on'
  let fixed_strings = a:kwargs.fixed_strings ? '-F ' : ''
  let fixed_strings_toggle = a:kwargs.fixed_strings ? 'off' : 'on'
  let max_1 = a:kwargs.max_1 ? '-m1 ' : ''
  let max_1_toggle = a:kwargs.max_1 ? 'off' : 'on'
  let search_zip = a:kwargs.search_zip ? '-z ' : ''
  let search_zip_toggle = a:kwargs.search_zip ? 'off' : 'on'
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
    \ . a:kwargs.type
    \ . ' -- %s '
    \ . paths
  let rg_command = printf(command_fmt, shellescape(a:kwargs.query))
  let reload_command = printf(command_fmt, '{q}')
  let empty_command = printf(command_fmt, '""')
  let files_command = 'echo 1 > ' . a:kwargs.files . '; rg ' . search_zip  . no_ignore . hidden_option .  ' --color=always --files '.a:kwargs.type

  let type_prompt = a:kwargs.type ==# '' ? '' : a:kwargs.type . ' '
  let rg_prompt = word
    \ . no_ignore
    \ . hidden
    \ . case_symbol
    \ . fixed_strings
    \ . max_1
    \ . search_zip
    \ . type_prompt
    \ . a:kwargs.prompt
    \ . ' rg> '

  let files_prompt = no_ignore
    \ . hidden
    \ . search_zip
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
    let preview = s:rg_preview_commands[g:siefe_rg_default_preview_command]
  endif

  let paths_info = a:kwargs.paths ==# [] ? '' : "\npaths: ".join(a:kwargs.paths)

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  " https://github.com/junegunn/fzf.vim
  " https://github.com/junegunn/fzf/blob/master/ADVANCED.md#toggling-between-data-sources
  let spec = {
    \ 'options': [
      \ '--history', s:data_path . '/rg_fzf_history',
      \ '--preview', preview,
      \ '--bind', g:siefe_rg_preview_key . ':change-preview:'.s:rg_preview_command,
      \ '--bind', g:siefe_rg_fast_preview_key . ':change-preview:'.s:rg_fast_preview_command,
      \ '--bind', 'f9:change-preview:echo -e "'.s:prettify_help(g:siefe_rg_rg_key, '').'search with ripgrep"',
      \ '--bind', g:siefe_down_key . ':down',
      \ '--bind', g:siefe_up_key . ':up',
      \ '--bind', g:siefe_next_history_key . ':next-history',
      \ '--bind', g:siefe_previous_history_key . ':previous-history',
      \ '--bind', g:siefe_accept_key . ':accept',
      \ '--print-query',
      \ '--ansi',
      \ '--print0',
      \ '--expect='
        \ . g:siefe_rg_type_key . ','
        \ . g:siefe_rg_type_not_key . ','
        \ . g:siefe_rg_word_key . ','
        \ . g:siefe_rg_case_key . ','
        \ . g:siefe_rg_hidden_key . ','
        \ . g:siefe_rg_no_ignore_key . ','
        \ . g:siefe_rg_fixed_strings_key . ','
        \ . g:siefe_rg_max_1_key . ','
        \ . g:siefe_rg_search_zip_key . ','
        \ . g:siefe_rg_dir_key . ','
        \ . g:siefe_rg_buffers_key . ','
        \ . g:siefe_rg_yank_key . ',',
      \ '--preview-window', '+{2}-/2,' . default_preview_size,
      \ '--multi',
      \ '--bind','tab:toggle+up',
      \ '--bind','shift-tab:toggle+down',
      \ '--query', a:kwargs.query,
      \ '--delimiter', s:delimiter,
      \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', 'change:+first',
      \ '--bind', g:siefe_rg_fzf_key
        \ . ':unbind(change,' . g:siefe_rg_fzf_key . ',' . g:siefe_rg_rgfzf_key . ')'
        \ . '+change-prompt(' . no_ignore . hidden . type_prompt . a:kwargs.prompt . ' fzf> )'
        \ . '+enable-search+rebind(' . g:siefe_rg_rg_key . ',' . g:siefe_rg_files_key . ')'
        \ . '+reload('.empty_command.')'
        \ . '+change-preview(' . s:rg_preview_commands[g:siefe_rg_default_preview_command] . ')',
      \ '--bind',  g:siefe_rg_rgfzf_key
        \ . ':unbind(change,' . g:siefe_rg_rgfzf_key . ')'
        \ . '+change-prompt('.no_ignore.hidden.a:kwargs.type . ' ' . a:kwargs.prompt.' rg/fzf> )'
        \ . '+enable-search+rebind(' . g:siefe_rg_rg_key . ',' . g:siefe_rg_fzf_key . ',' . g:siefe_rg_files_key . ')'
        \ . '+change-preview(' . s:rg_preview_commands[g:siefe_rg_default_preview_command] . ')',
      \ '--bind', g:siefe_rg_rg_key
        \ . ':unbind(' . g:siefe_rg_rg_key . ')'
        \ . '+change-prompt(' . rg_prompt . ')'
        \ . '+disable-search+reload('.reload_command.')'
        \ . '+rebind(change,' . g:siefe_rg_fzf_key . ',' . g:siefe_rg_files_key . ',' . g:siefe_rg_rgfzf_key . ')'
        \ . '+change-preview(' . s:rg_preview_commands[g:siefe_rg_default_preview_command] . ')',
      \ '--bind', g:siefe_rg_files_key
        \ . ':unbind(change,' . g:siefe_rg_files_key . ',' . g:siefe_rg_rgfzf_key . ')'
        \ . '+change-prompt(' . files_prompt . ')'
        \ . '+enable-search+rebind(' . g:siefe_rg_rg_key . ',' . g:siefe_rg_fzf_key . ')'
        \ . '+reload('.files_command.')'
        \ . '+change-preview('.s:files_preview_command.')',
      \ '--header', s:prettify_help(g:siefe_rg_rg_key, 'Rg')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_fzf_key,  'fzf')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_rgfzf_key, 'rg/fzf')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_files_key, 'Files')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_type_key, 'Type')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_type_not_key, '!Type')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_buffers_key, 'Buffers')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_no_ignore_key, 'no ignore:' . no_ignore_toggle)
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_hidden_key, 'hidden:' . hidden_toggle)
        \ . "\n" . s:prettify_help(g:siefe_rg_dir_key, 'cd')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_yank_key, 'yank')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_word_key, 'word:' . word_toggle)
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_fixed_strings_key, 'fixed strings:' . fixed_strings_toggle)
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_max_1_key, 'max count 1:' . max_1_toggle)
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_search_zip_key, 'search zip:' . search_zip_toggle)
        \ . ' ╱ ' . s:magenta(s:preview_help(s:rg_preview_keys), 'Special') . ' change preview'
        \ . paths_info,
      \ '--prompt', initial_prompt,
      \ ],
   \ 'dir': a:dir,
   \ 'sink*': function('s:ripgrep_sink', [a:fullscreen, a:dir, a:kwargs]),
   \ 'source': initial_command
  \ }

  if files == 0
    let spec.options += ['--disabled']
  else
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
  let tmp = split(a:lines[-1], "\n", 1)[0:-2]
  if len(a:lines) == 1
    let a:kwargs.query = tmp[0]
  else
    let a:kwargs.query = join(a:lines[0:-2], "\n")."\n".tmp[0]
  endif

  let key = tmp[1]
  let filelist = []

  for item in tmp[2:]
    let tmp2 = split(item, s:delimiter, 1)
    let file = {}

    " rg/fzf '//' delimited result
    if len(tmp2) >= 4
      let file.filename  = tmp2[0]
      let file.line  = tmp2[1]
      let file.column  = tmp2[2]

      if len(tmp2) == 4
        let file.content = tmp2[3]
      else
        " If it's bigger than 4 that means there was a // in there result,
        " so we recreate the original content
        let file.content = join(tmp2[3:], s:delimiter)."\n"
      endif

    " files result
    elseif len(tmp2) == 1
      let file.filename = tmp2[0]
      let file.line  = 1
      let file.column  = 1

      " this should never happen
      else
        return s:warn('Something went wrong... tmp2 = '.string(tmp2).'lines = '.string(a:lines))
      endif
        let filelist += [file]
  endfor


  if key ==# ''
    " no match
    if len(tmp[2:]) == 0
      return
    endif
    execute 'e' file.filename
    call cursor(file.line, file.column)
    normal! zvzz

    call s:fill_quickfix(filelist)
  endif

  " work around for strange nested fzf change directory behaviour
  " when nested it will not cd back to the original directory
  exe 'cd' a:kwargs.orig_dir

  if key ==# g:siefe_rg_type_key
    call FzfTypeSelect('RipgrepFzfType', a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_type_not_key
    call FzfTypeSelect('RipgrepFzfTypeNot', a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_word_key
    let a:kwargs.word = a:kwargs.word ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_case_key
    let a:kwargs.case = a:kwargs.case ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_hidden_key
    let a:kwargs.hidden = a:kwargs.hidden ? 0 : 1
    call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)

  elseif key ==# g:siefe_rg_no_ignore_key
    let a:kwargs.no_ignore = a:kwargs.no_ignore ? 0 : 1
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

  elseif key ==# g:siefe_rg_buffers_key
    if a:kwargs.paths == []
      let a:kwargs.paths = map(filter(copy(getbufinfo()), 'v:val.listed'), 'fnamemodify(v:val.name, ":p:~:.")')
      call siefe#ripgrepfzf( a:fullscreen, a:dir, a:kwargs)
    else
      let a:kwargs.paths = []
      call siefe#ripgrepfzf( a:fullscreen, a:dir, a:kwargs)
    endif

  elseif key ==# g:siefe_rg_dir_key
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, a:dir, 0, 0, 'd', 0, '', a:kwargs)

  elseif key ==# g:siefe_rg_yank_key
    return s:yank_to_register(join(map(filelist, 'v:val.content'), "\n"))
  return
  endif
endfunction

" Lots of functions to use fzf to also select ie rg types
function! FzfTypeSelect(func, fullscreen, ...) abort
  call fzf#run(fzf#wrap({
        \ 'source': s:logger . 'rg --color=always --type-list ',
        \ 'options': [
          \ '--prompt', 'Choose type> ',
          \ '--multi',
          \ '--history', s:data_path . '/type_fzf_history',
          \ '--bind', g:siefe_down_key . ':down',
          \ '--bind', g:siefe_up_key . ':up',
          \ '--bind', g:siefe_next_history_key . ':next-history',
          \ '--bind', g:siefe_previous_history_key . ':previous-history',
          \ '--bind', g:siefe_accept_key . ':accept',
          \ '--bind','tab:toggle+up',
          \ '--bind','shift-tab:toggle+down',
          \ '--expect', g:siefe_abort_key,
          \ '--header', s:prettify_help(g:siefe_abort_key, 'abort'),
          \ ],
        \ 'sink*': function(a:func, [a:fullscreen] + a:000)
      \ }, a:fullscreen))
endfunction


function! FzfDirSelect(func, fullscreen, dir, fd_hidden, fd_no_ignore, fd_type, multi, base_dir, ...) abort
  let fd_hidden = a:fd_hidden ? '-H ' : ''
  let fd_hidden_toggle = a:fd_hidden ? 'off' : 'on'
  let fd_no_ignore = a:fd_no_ignore ? '-u ' : ''
  let fd_no_ignore_toggle = a:fd_no_ignore ? 'off' : 'on'
  let fd_type = a:fd_type !=# '' ? ' --type ' . a:fd_type : ''
  let base_dir = a:base_dir !=# '' ? ' --strip-cwd-prefix --base-directory ' . a:base_dir : ' --search-path=`realpath --relative-to=. "'.a:dir.'"` --relative-path '

  let siefe_fd_project_root_key = g:siefe_fd_project_root_env ==# '' ? '' : g:siefe_fd_project_root_key . ','
  let siefe_fd_project_root_help = g:siefe_fd_project_root_env ==# '' ? '' : ' ╱ ' . s:prettify_help(g:siefe_fd_project_root_key, '√work')
  let siefe_fd_search_project_root_key = g:siefe_fd_project_root_env ==# '' ? '' : g:siefe_fd_search_project_root_key . ','
  let siefe_fd_search_project_root_help = g:siefe_fd_project_root_env ==# '' ? '' : ' ╱ ' . s:prettify_help(g:siefe_fd_search_project_root_key, 'search √work')

  " TODO disable git/project root for git log

  let options = [
    \ '--history', s:data_path . '/git_dir_history',
    \ '--print-query',
    \ '--ansi',
    \ '--scheme=path',
    \ '--bind', 'tab:toggle+up',
    \ '--bind', 'shift-tab:toggle+down',
    \ '--bind', g:siefe_down_key . ':down',
    \ '--bind', g:siefe_up_key . ':up',
    \ '--bind', g:siefe_next_history_key . ':next-history',
    \ '--bind', g:siefe_previous_history_key . ':previous-history',
    \ '--bind', g:siefe_accept_key . ':accept',
    \ '--prompt', fd_no_ignore.fd_hidden.'fd> ',
    \ '--expect='
    \ . g:siefe_fd_hidden_key . ','
    \ . g:siefe_fd_no_ignore_key . ','
    \ . g:siefe_fd_git_root_key . ','
    \ . g:siefe_fd_search_git_root_key . ','
    \ . siefe_fd_project_root_key
    \ . siefe_fd_search_project_root_key
    \ . g:siefe_abort_key,
    \ '--header', s:prettify_help(g:siefe_fd_hidden_key, 'hidden:' . fd_hidden_toggle)
      \ . ' ╱ ' . s:prettify_help(g:siefe_fd_no_ignore_key, 'no ignore:' . fd_no_ignore_toggle)
      \ . ' ╱ ' . s:prettify_help(g:siefe_fd_git_root_key, '√git')
      \ . siefe_fd_project_root_help
      \ . ' ╱ ' . s:prettify_help(g:siefe_abort_key, 'abort')
      \ . "\n" . s:prettify_help(g:siefe_fd_search_git_root_key, 'search √git')
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

function! RipgrepFzfDir(fullscreen, dir, fd_hidden, fd_no_ignore, kwargs, lines) abort
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
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, a:dir, fd_hidden, a:fd_no_ignore, 'd', 0, '', a:kwargs)

  elseif key ==# g:siefe_fd_no_ignore_key
    let fd_no_ignore = a:fd_no_ignore ? 0 : 1
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, a:dir, a:fd_hidden, fd_no_ignore, 'd', 0, '', a:kwargs)

  elseif key ==# g:siefe_fd_git_root_key
    let a:kwargs.prompt = siefe#get_relative_git_or_bufdir()
    call siefe#ripgrepfzf(a:fullscreen, siefe#get_git_root(), a:kwargs)

  elseif key ==# g:siefe_fd_project_root_key
    let a:kwargs.prompt = g:siefe_fd_project_root_env
    call siefe#ripgrepfzf(a:fullscreen, expand(g:siefe_fd_project_root_env), a:kwargs)

  elseif key ==# g:siefe_fd_search_git_root_key
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, siefe#get_git_root(), a:fd_hidden, a:fd_no_ignore, 'd', 0, '', a:kwargs)

  elseif key ==# g:siefe_fd_search_project_root_key
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, expand(g:siefe_fd_project_root_env), a:fd_hidden, a:fd_no_ignore, 'd', 0, '', a:kwargs)

  else
    let a:kwargs.prompt = siefe#get_relative_git_or_bufdir(new_dir)
    call siefe#ripgrepfzf(a:fullscreen, trim(system('realpath '.new_dir)), a:kwargs)
  endif
endfunction

function! RipgrepFzfType(fullscreen, dir, kwargs, lines) abort
  if a:lines[0] ==# g:siefe_abort_key
    let a:kwargs.type = ''
  else
    let a:kwargs.type = join(map(a:lines[1:], '"-t" . split(v:val, ":")[0]'))
  endif
  call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)
endfunction

function! RipgrepFzfTypeNot(fullscreen, dir, kwargs, lines) abort
  if a:lines[0] ==# g:siefe_abort_key
    let a:kwargs.type = ''
  else
    let a:kwargs.type = join(map(a:lines[1:], '"-T" . split(v:val, ":")[0]'))
  endif
  call siefe#ripgrepfzf(a:fullscreen, a:dir, a:kwargs)
endfunction

"function! siefe#gitlogfzf(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, type, line_range, fullscreen) abort
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

  if a:kwargs.branches ==# '--all'
    let branches = '--all '
    let notbranches = ''
  else
    let branches = a:kwargs.branches ==# '' ? '' : a:kwargs.branches . ' '
    let notbranches = a:kwargs.notbranches ==# '' ? '' : a:kwargs.notbranches . ' '
  endif

  let authors = join(map(copy(a:kwargs.authors), '"--author=".shellescape(v:val)'))

  if len(a:kwargs.paths)  == 1 && filereadable(a:kwargs.paths[0]) && a:kwargs.line_range == []
    let siefe_gitlog_follow_key = g:siefe_gitlog_follow_key . ','
    let siefe_gitlog_follow_help = ' ╱ ' . s:prettify_help( g:siefe_gitlog_follow_key, 'follow')
    let follow = a:kwargs.follow ? '--follow' : ''
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
    let paths = join(map(copy(a:kwargs.paths), 'shellescape(v:val)'))
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
      \ . ' --abbrev-commit -- '
      \ . ' | sed -E -z "s/commit ([0-9a-f]*)([^\n]*)*.*\n\n/\1\2 •/" '
      \ . ' | sed -E -z "s/[ ][ ]*/ /g"'
      \ . remove_newlines
    let reload_command = ''
    let SG_expect = ''
    let SG_help = ''
    let query_file = '/dev/null'
  else
    let SG_expect = g:siefe_gitlog_sg_key . ','
        \ . g:siefe_gitlog_ignore_case_key . ','
        \ . g:siefe_gitlog_type_key . ','
        \ . g:siefe_gitlog_pickaxe_regex_key . ','
        \ . g:siefe_gitlog_dir_key . ','
        \ . g:siefe_gitlog_follow_key . ','
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
        \ . follow
        \ . ' ' . branches
        \ . ' ' . notbranches
        \ . ' ' . authors
        \ . ' ' . regex
        \ . ' ' . ignore_case
    let initial_command = s:logger . write_query_initial . printf(command_fmt, shellescape(a:kwargs.query)).fzf#shellescape(format).' -- ' . paths . remove_newlines
    let reload_command = s:logger . write_query_reload . printf(command_fmt, '{q}').fzf#shellescape(format).' -- ' . paths . remove_newlines
    let SG_help = " \n " . s:prettify_help(g:siefe_gitlog_sg_key, 'toggle S/G')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_ignore_case_key, 'ignore case')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_fzf_key,  'fzf messages')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_s_key, 'pickaxe')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_pickaxe_regex_key, 'regex')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_dir_key, 'pathspec')
  endif

  let current = expand('%')
  let orderfile = tempname()
  call writefile([current], orderfile)

  let suffix = executable('delta') ? '| delta ' . g:siefe_delta_options  : ''

  let preview_all_command = 'echo -e "\033[0;35mgit show all\033[0m" && git show -O'.fzf#shellescape(orderfile).' {1} '
  let preview_command_0 = preview_all_command . ' --patch --stat -- ' . suffix
  let preview_command_1 = preview_all_command . ' --format=format: --patch --stat -- ' . suffix

  let preview_command_2 = 'echo -e "\033[0;35mgit show matching files\033[0m" && ' . s:bin.git_SG . ' show ' . G .'"`cat '.query_file.'`" -O'.fzf#shellescape(orderfile).' ' . regex . ' {1} '
    \ . ' --format=format: --patch --stat -- ' . suffix

  let preview_pickaxe_hunks_command = 'echo -e "\033[0;35mgit show matching hunks\033[0m" && (export GREPDIFF_REGEX=`cat '.query_file.'`; git -c diff.external=' . s:bin.pickaxe_diff . ' show {1} -O'.fzf#shellescape(orderfile).' --ext-diff '.regex . G . '"`cat '.query_file.'`"'
  let no_grepdiff_message = 'echo install grepdiff from the patchutils package for this preview'
  let preview_command_3 = executable('grepdiff') ? preview_pickaxe_hunks_command . ' --format=format: --patch --stat --) ' . suffix : no_grepdiff_message
  let preview_command_4 = 'echo -e "\033[0;35mgit diff\033[0m" && git diff -O'.fzf#shellescape(orderfile).' --patch --stat {1} -- ' . suffix

  let preview_commands = [
    \ preview_command_0,
    \ preview_command_1,
    \ preview_command_2,
    \ preview_command_3,
    \ preview_command_4,
  \ ]

  let authors_info = a:kwargs.authors ==# [] ? '' : "\nauthors: ".join(a:kwargs.authors)
  let paths_info = paths ==# '' ? '' : "\npaths: ". paths

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  let spec = {
    \ 'options': [
      \ '--history', s:data_path . '/git_fzf_history',
      \ '--preview', preview_commands[ g:siefe_gitlog_default_preview_command ],
      \ '--bind', g:siefe_gitlog_preview_0_key . ':change-preview:'.preview_command_0,
      \ '--bind', g:siefe_gitlog_preview_1_key . ':change-preview:'.preview_command_1,
      \ '--bind', g:siefe_gitlog_preview_2_key . ':change-preview:'.preview_command_2,
      \ '--bind', g:siefe_gitlog_preview_3_key . ':change-preview:'.preview_command_3,
      \ '--bind', g:siefe_gitlog_preview_4_key . ':change-preview:'.preview_command_4,
      \ '--bind', g:siefe_down_key . ':down',
      \ '--bind', g:siefe_up_key . ':up',
      \ '--bind', g:siefe_next_history_key . ':next-history',
      \ '--bind', g:siefe_previous_history_key . ':previous-history',
      \ '--bind', g:siefe_accept_key . ':accept',
      \ '--print-query',
      \ '--layout=reverse-list',
      \ '--ansi',
      \ '--read0',
      \ '--expect='
        \ . g:siefe_gitlog_author_key . ','
        \ . g:siefe_gitlog_branch_key . ','
        \ . g:siefe_gitlog_not_branch_key . ','
        \ . g:siefe_gitlog_vdiffsplit_key . ','
        \ . SG_expect,
      \ '--multi',
      \ '--bind','tab:toggle+down',
      \ '--bind','shift-tab:toggle+up',
      \ '--query', a:kwargs.query,
      \ '--delimiter', '•',
      \ '--preview-window', default_preview_size,
      \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
      \ '--header',
        \ s:prettify_help(g:siefe_gitlog_author_key, 'authors')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_branch_key, 'branches')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_type_key, 'type')
        \ . ' ╱ ' . s:magenta(s:preview_help(s:gitlog_preview_keys), 'Special') . ' change preview'
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_not_branch_key, '^branches')
        \ . SG_help
        \ . siefe_gitlog_follow_help
        \ . authors_info
        \ . paths_info,
      \ '--prompt', branches . notbranches . G_prompt . regex . ignore_case_symbol . 'pickaxe> ',
      \ ],
   \ 'sink*': function('s:gitpickaxe_sink', [a:fullscreen, a:kwargs]),
   \ 'source': initial_command
  \ }

  if a:kwargs.line_range == []
    let spec.options += [
      \ '--disabled',
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', g:siefe_gitlog_fzf_key . ':unbind(change,' . g:siefe_gitlog_fzf_key . ')+change-prompt(pickaxe/fzf> )+enable-search+rebind(' . g:siefe_gitlog_s_key . ')',
      \ '--bind', g:siefe_gitlog_s_key . ':unbind(change,' . g:siefe_gitlog_s_key . ')+change-prompt(' . branches . notbranches . G_prompt . regex . ignore_case_symbol . 'pickaxe> '. ')+disable-search+reload(' . reload_command . '"+rebind(change,' . g:siefe_gitlog_fzf_key . ')',
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
  " split(v:val, " ")[0]) == commit hash
  " join(split(v:val, " ")[1:] == full commit message
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
    call FzfBranchSelect('GitPickaxeFzfBranch', a:fullscreen, 0, a:kwargs)

  elseif key == g:siefe_gitlog_not_branch_key
    call FzfBranchSelect('GitPickaxeFzfNotBranch', a:fullscreen, 1, a:kwargs)

  elseif key == g:siefe_gitlog_author_key
    call FzfAuthorSelect('GitPickaxeFzfAuthor', a:fullscreen, a:kwargs)

  elseif key == g:siefe_gitlog_dir_key
    call FzfDirSelect('GitPickaxeFzfPath', a:fullscreen, siefe#bufdir(), 0, 0, '', 1, siefe#get_git_root(), a:kwargs)

  elseif key == g:siefe_gitlog_type_key
    " git understands rg --type-list globs :)
    call FzfTypeSelect('GitlogFzfType', a:fullscreen, a:kwargs)

  elseif key == g:siefe_gitlog_vdiffsplit_key
    if len(quickfix_list) == 2
      execute 'Gedit '. quickfix_list[0].module . ':%'
      execute 'Gvdiffsplit '. quickfix_list[1].module . ':%'
    elseif len(quickfix_list) == 1
      execute 'Gedit HEAD:%'
      execute 'Gvdiffsplit '. quickfix_list[0].module . ':%'
    endif

  else
  execute 'Gedit '. quickfix_list[0].module
  call s:fill_quickfix(quickfix_list)
  endif
endfunction

function! GitlogFzfType(fullscreen, kwargs, lines) abort
  if a:lines[0] == g:siefe_abort_key
    let a:kwargs.type = ''
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)
  else
    let a:kwargs.type = s:reduce(map(a:lines[1:], 'split(substitute(split(v:val, ":")[1], ",", "", "g"))'), { acc, val -> type(val) == 3 ? extend(acc, val) : add(acc, val)})
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)
  endif
endfunction

function! FzfBranchSelect(func, fullscreen, not, ...) abort
  let preview_command_1 = 'echo git log {1} ; echo {2} -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_2 = 'echo git log ..{1} \(what they have, we dont\); echo ..{2} -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_3 = 'echo git log {1}.. \(what we have, they dont\); echo {2}.. -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_4 = 'echo git log {1}... \(what we both have, common ancester not\); echo {2}... -- | xargs git log --format="%m%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'

  let not = a:not ? '^' : ''
  let siefe_branches_all_key = a:not ? '' : g:siefe_branches_all_key . ','
  let siefe_branches_all_help = a:not ? '' : ' ╱ ' . s:prettify_help(g:siefe_branches_all_key, '--all')

  let spec = {
    \ 'source':  "git branch -a --sort='-authordate' --color --format='%(HEAD) %(if:equals=refs/remotes)%(refname:rstrip=-2)%(then)%(color:cyan)%(align:0)%(refname:lstrip=2)%(end)%(else)%(if)%(HEAD)%(then)%(color:reverse yellow)%(align:0)%(refname:lstrip=-1)%(end)%(else)%(color:yellow)%(align:0)%(refname:lstrip=-1)%(end)%(end)%(end)%(color:reset) %(color:red): %(if)%(symref)%(then)%(color:yellow)%(objectname:short)%(color:reset) %(color:red):%(color:reset) %(color:green)-> %(symref:lstrip=-2)%(else)%(color:yellow)%(objectname:short)%(color:reset) %(if)%(upstream)%(then)%(color:red): %(color:reset)%(color:green)[%(upstream:short)%(if)%(upstream:track)%(then):%(color:blue)%(upstream:track,nobracket)%(symref:lstrip=-2)%(color:green)%(end)]%(color:reset) %(end)%(color:red):%(color:reset) %(contents:subject)%(end) • %(color:blue)(%(authordate:short))'",
    \ 'sink*':   function(a:func, [a:fullscreen] + a:000),
    \ 'options':
      \ [
        \ '--history', s:data_path . '/rg_branch_history',
        \ '--ansi',
        \ '--multi',
        \ '--delimiter', ':',
        \ '--bind', 'f1:change-preview:'.preview_command_1,
        \ '--bind', 'f2:change-preview:'.preview_command_2,
        \ '--bind', 'f3:change-preview:'.preview_command_3,
        \ '--bind', 'f4:change-preview:'.preview_command_4,
        \ '--bind','tab:toggle+up',
        \ '--bind', g:siefe_down_key . ':down',
        \ '--bind', g:siefe_up_key . ':up',
        \ '--bind', g:siefe_next_history_key . ':next-history',
        \ '--bind', g:siefe_previous_history_key . ':previous-history',
        \ '--bind', g:siefe_accept_key . ':accept',
        \ '--expect='
          \ . g:siefe_abort_key . ','
          \ . siefe_branches_all_key,
        \ '--bind','shift-tab:toggle+down',
        \ '--preview', 'echo git log {1} ; echo {2} -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"' ,
        \ '--prompt', not . 'branches> ',
        \ '--header='
          \ . s:prettify_help(g:siefe_abort_key, 'abort')
          \ . siefe_branches_all_help
      \ ],
    \ 'placeholder': ''
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! FzfAuthorSelect(func, fullscreen, ...) abort
  let spec = {
    \ 'source':  "git log --format='%aN <%aE>' | awk '!x[$0]++'",
    \ 'sink*':   function(a:func, [a:fullscreen] + a:000),
    \ 'options':
      \ [
        \ '--history', s:data_path . '/rg_author_history',
        \ '--multi',
        \ '--bind','tab:toggle+up',
        \ '--expect', g:siefe_abort_key,
        \ '--header', s:prettify_help(g:siefe_abort_key, 'abort'),
        \ '--bind','shift-tab:toggle+down',
        \ '--bind', g:siefe_down_key . ':down',
        \ '--bind', g:siefe_up_key . ':up',
        \ '--bind', g:siefe_next_history_key . ':next-history',
        \ '--bind', g:siefe_previous_history_key . ':previous-history',
        \ '--bind', g:siefe_accept_key . ':accept',
        \ ],
    \ 'placeholder': ''
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! GitPickaxeFzfAuthor(fullscreen, kwargs, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    let a:kwargs.authors = []

  else
    let a:kwargs.authors = a:000[0][1:]

  endif
  call siefe#gitlogfzf(a:fullscreen, a:kwargs)
endfunction

function! GitPickaxeFzfBranch(fullscreen, kwargs, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    let a:kwargs.branches = ''

  elseif a:000[0][0] == g:siefe_branches_all_key
    let a:kwargs.branches = '--all'

  else
    let a:kwargs.branches = join(map(a:000[0][1:], 'trim(split(v:val, ":")[0], " *")'))

  endif
  call siefe#gitlogfzf(a:fullscreen, a:kwargs)
endfunction

function! GitPickaxeFzfNotBranch(fullscreen, kwargs, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    let a:kwargs.branches = ''
  else
    let a:kwargs.notbranches = join(map(a:000[0][1:], '"^" . trim(split(v:val, ":")[0], " *")'))
  endif
  call siefe#gitlogfzf(a:fullscreen, a:kwargs)
endfunction

function! GitPickaxeFzfPath(fullscreen, dir, fd_hidden, fd_no_ignore, kwargs, ...) abort
  let key = a:000[0][1]

  if key ==# g:siefe_abort_key
    let a:kwargs.paths = []
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)

  elseif key ==# g:siefe_fd_hidden_key
    let fd_hidden = a:fd_hidden ? 0 : 1
    call FzfDirSelect('GitPickaxeFzfPath', a:fullscreen, siefe#bufdir(), fd_hidden, a:fd_no_ignore, '', 1, siefe#bufdir(), a:kwargs)

  elseif key ==# g:siefe_fd_no_ignore_key
    let fd_no_ignore = a:fd_no_ignore ? 0 : 1
    call FzfDirSelect('GitPickaxeFzfPath', a:fullscreen, siefe#bufdir(), fd_hidden, a:fd_no_ignore, '', 1, siefe#bufdir(), a:kwargs)

  elseif key ==# g:siefe_fd_search_git_root_key
    call FzfDirSelect('GitPickaxeFzfPath', a:fullscreen, siefe#bufdir(), fd_hidden, a:fd_no_ignore, '', 1, siefe#get_git_root(), a:kwargs)

  else
    let a:kwargs.paths = a:000[0][2:]
    call siefe#gitlogfzf(a:fullscreen, a:kwargs)
  endif
endfunction


""" helper functions
function! s:warn(message) abort
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function!  siefe#bufdir() abort
  return substitute(split(expand('%:p:h'), '[/\\]\.git\([/\\]\|$\)')[0], '^fugitive://', '', '')
endfunction

function! siefe#get_git_root() abort
  let bufdir = siefe#bufdir()
  let root = systemlist('git -C ' . fzf#shellescape(bufdir) . ' rev-parse --show-toplevel')[0]
  return v:shell_error ? s:warn('Not in a git repository') : root
endfunction

function! siefe#get_git_basename_or_bufdir() abort
  let bufdir = siefe#bufdir()
  let basename = '#'.systemlist('basename `git -C '. fzf#shellescape(bufdir) .' rev-parse --show-toplevel`')[0]
  return v:shell_error ? bufdir : basename
endfunction

function! siefe#get_relative_git_or_bufdir(...) abort
  let bufdir = siefe#bufdir()
  if a:0 == 0
    let dir = get(a:, 1, '')
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

function! s:yank_to_register(data) abort
  let @" = a:data
  silent! let @* = a:data
  silent! let @+ = a:data
endfunction

function! s:prettify_help(key, text) abort
  let char = split(a:key, '-')[-1]
  if char == a:text[0]
    return s:magenta(toupper(a:key), 'Special') . ' ' . a:text
  else
    return s:magenta(toupper(a:key), 'Special') . ' ' . a:text[0] . substitute(a:text[1:], char, "\e[3m".char."\e[m", '')
  endif
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
