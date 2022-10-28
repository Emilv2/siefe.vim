scriptencoding utf-8

let s:min_version = '0.33.0'
let s:is_win = has('win32') || has('win64')
let s:is_wsl_bash = s:is_win && (exepath('bash') =~? 'Windows[/\\]system32[/\\]bash.exe$')
let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:p:h:h').'/bin/'
let s:bin = {
\ 'pickaxe_diff': s:bin_dir.'pickaxe-diff',
\ 'git_SG': s:bin_dir.'git_SG',
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


  let s:checked = !empty(fzf#exec(s:min_version))
endfunction

""" load configuration options
let g:siefe_delta_options = get(g:, 'siefe_delta_options', '--keep-plus-minus-markers') . ' ' . get(g:, 'siefe_delta_extra_options', '')
let g:siefe_bat_options = get(g:, 'siefe_bat_options', '--style=numbers,changes') . ' ' . get(g:, 'siefe_bat_extra_options', '')

let g:siefe_abort_key = get(g:, 'siefe_abort_key', 'esc')
let g:siefe_history_next_key = get(g:, 'siefe_history_next_key', 'ctrl-n')
let g:siefe_history_prev_key = get(g:, 'siefe_history_prev_key', 'ctrl-p')
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
let g:siefe_rg_dir_key = get(g:, 'siefe_rg_dir_key', 'ctrl-d')
let g:siefe_rg_yank_key = get(g:, 'siefe_rg_yank_key', 'ctrl-y')

let g:siefe_rg_preview_key = get(g:, 'siefe_rg_preview_key', 'f1')
let g:siefe_rg_fast_preview_key = get(g:, 'siefe_rg_fast_preview_key', 'f2')

let s:rg_preview_keys = [
  \ g:siefe_rg_preview_key,
  \ g:siefe_rg_fast_preview_key,
\ ]

let s:bat_command = executable('batcat') ? 'batcat' : executable('bat') ? 'bat' : ''
let s:fd_command = executable('fdfind') ? 'fdfind' : executable('fd') ? 'fd' : ''
let s:files_preview_command = s:bat_command !=# '' ? s:bat_command . ' --color=always --pager=never ' . g:siefe_bat_options . ' -- {}' : 'cat {}'
let s:rg_preview_command = s:bat_command !=# '' ? s:bat_command . ' --color=always --highlight-line={2} --pager=never ' . g:siefe_bat_options . ' -- {1}' : 'cat {1}'
let s:rg_fast_preview_command = 'cat {1}'

let s:rg_preview_commands = [
  \ s:rg_preview_command,
  \ s:rg_fast_preview_command,
\ ]


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
let g:siefe_gitlog_dir_key = get(g:, 'siefe_gitlog_dir_key', 'ctrl-d')

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
  \ g:siefe_gitlog_dir_key,
\ ] + s:gitlog_preview_keys


let g:siefe_fd_hidden_key = get(g:, 'siefe_fd_hidden_key', 'ctrl-h')
let g:siefe_fd_no_ignore_key = get(g:, 'siefe_fd_no_ignore_key', 'ctrl-i')
let g:siefe_fd_git_root_key = get(g:, 'siefe_fd_git_root_key', 'ctrl-r')
let g:siefe_fd_project_root_key = get(g:, 'siefe_fd_git_root_key', 'ctrl-p')

let g:siefe_fd_project_root_env = get(g:, 'siefe_fd_git_root_env', '')

let g:siefe_branches_all_key = get(g:, 'siefe_branches_all_key', 'ctrl-a')

function! siefe#ripgrepfzf(query, dir, prompt, word, case_sensitive, hidden, no_ignore, fixed_strings, max_1, orig_dir, type, paths, tmp_cfg, fullscreen) abort
  call s:check_requirements()

  if empty(a:dir)
    return
  endif

  if empty(a:tmp_cfg)
    let tmp_cfg = tempname()
    let files = 0
    call writefile([files], tmp_cfg)
  else
    let tmp_cfg = a:tmp_cfg
    let files = readfile(tmp_cfg)[0]
  endif

  let paths = join(map(a:paths, 'shellescape(v:val)'), ' ')

  let word = a:word ? '-w ' : ''
  let word_toggle = a:word ? 'off' : 'on'
  let hidden = a:hidden ? '-. ' : ''
  let hidden_option = a:hidden ? '--hidden ' : ''
  let hidden_toggle = a:hidden ? 'off' : 'on'
  let case_sensitive = a:case_sensitive ? '--case-sensitive ' : '--smart-case '
  let case_symbol = a:case_sensitive ? '-s ' : ''
  let case_toggle = a:case_sensitive ? 'off' : 'on'
  let no_ignore = a:no_ignore ? '-u ' : ''
  let no_ignore_toggle = a:no_ignore ? 'off' : 'on'
  let fixed_strings = a:fixed_strings ? '-F ' : ''
  let fixed_strings_toggle = a:fixed_strings ? 'off' : 'on'
  let max_1 = a:max_1 ? '-m1 ' : ''
  let max_1_toggle = a:max_1 ? 'off' : 'on'
  let command_fmt = 'echo 0 > ' . tmp_cfg . '; rg --column -U --glob ' . shellescape('!git/objects')
    \ . ' --line-number --no-heading --color=always --colors "column:fg:green" --with-filename '
    \ . case_sensitive
    \ . s:field_match_separator . ' '
    \ . word
    \ . no_ignore
    \ . hidden_option
    \ . fixed_strings
    \ . max_1
    \ . a:type
    \ . ' %s -- %s '
    \ . paths
  let rg_command = printf(command_fmt, '', shellescape(a:query))
  let reload_command = printf(command_fmt, '', '{q}')
  let empty_command = printf(command_fmt, '', '""')
  let files_command = 'echo 1 > ' . tmp_cfg . '; rg --color=always --files '.a:type

  let rg_prompt = word
    \ . no_ignore
    \ . hidden
    \ . case_symbol
    \ . fixed_strings
    \ . max_1
    \ . a:type . ' '
    \ . a:prompt
    \ . ' rg> '

  let files_prompt = no_ignore
    \ . hidden
    \ . a:type . ' '
    \ . a:prompt
    \ . ' Files> '

  if files
    let initial_command = files_command
    let initial_prompt = files_prompt
  else
    let initial_command = rg_command
    let initial_prompt = rg_prompt
  endif

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  " https://github.com/junegunn/fzf.vim
  " https://github.com/junegunn/fzf/blob/master/ADVANCED.md#toggling-between-data-sources
  let spec = {
    \ 'options': [
      \ '--history', expand('~/.vim_fzf_history'),
      \ '--preview', s:rg_preview_commands[g:siefe_rg_default_preview_command],
      \ '--bind', g:siefe_rg_preview_key . ':change-preview:'.s:rg_preview_command,
      \ '--bind', g:siefe_rg_fast_preview_key . ':change-preview:'.s:rg_fast_preview_command,
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
        \ . g:siefe_rg_dir_key . ','
        \ . g:siefe_rg_yank_key . ',',
      \ '--preview-window', '+{2}-/2,' . default_preview_size,
      \ '--multi',
      \ '--bind','tab:toggle+up',
      \ '--bind','shift-tab:toggle+down',
      \ '--query', a:query,
      \ '--delimiter', s:delimiter,
      \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', 'change:+first',
      \ '--bind', g:siefe_rg_fzf_key
        \ . ':unbind(change,' . g:siefe_rg_fzf_key . ',' . g:siefe_rg_rgfzf_key . ')'
        \ . '+change-prompt('.no_ignore.hidden.a:type . ' ' . a:prompt.' fzf> )'
        \ . '+enable-search+rebind(' . g:siefe_rg_rg_key . ',' . g:siefe_rg_files_key . ')'
        \ . '+reload('.empty_command.')'
        \ . '+change-preview(' . s:rg_preview_commands[g:siefe_rg_default_preview_command] . ')',
      \ '--bind',  g:siefe_rg_rgfzf_key
        \ . ':unbind(change,' . g:siefe_rg_rgfzf_key . ')'
        \ . '+change-prompt('.no_ignore.hidden.a:type . ' ' . a:prompt.' rg/fzf> )'
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
        \ . "\n" . s:prettify_help(g:siefe_rg_dir_key, 'cd')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_yank_key, 'yank')
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_word_key, 'word:' . word_toggle)
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_no_ignore_key, 'no ignore:' . no_ignore_toggle)
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_fixed_strings_key, 'fixed strings:' . fixed_strings_toggle)
        \ . ' ╱ ' . s:prettify_help(g:siefe_rg_max_1_key, 'max count 1:' . max_1_toggle)
        \ . ' ╱ ' . s:magenta(s:preview_help(s:rg_preview_keys), 'Special') . ' change preview',
      \ '--prompt', initial_prompt,
      \ ],
   \ 'dir': a:dir,
   \ 'sink*': function('s:ripgrep_sink', [a:dir, a:prompt, a:word, a:case_sensitive, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, tmp_cfg, a:fullscreen]),
   \ 'source': initial_command
  \ }

  if files == 0
    let spec.options += ['--disabled']
  endif

  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:ripgrep_sink(dir, prompt, word, case, hidden, no_ignore, fixed_strings, max_1, orig_dir, type, paths, tmp_cfg, fullscreen, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  " query can contain newlines, we have to reconstruct it
  let tmp = split(a:lines[-1], "\n", 1)[0:-2]
  if len(a:lines) == 1
    let query = tmp[0]
  else
    let query = join(a:lines[0:-2], "\n")."\n".tmp[0]
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
  exe 'cd' a:orig_dir

  if key ==# g:siefe_rg_type_key
    call FzfTypeSelect('RipgrepFzfType', a:fullscreen, query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:paths, a:tmp_cfg)
  elseif key ==# g:siefe_rg_type_not_key
    call FzfTypeSelect('RipgrepFzfTypeNot', a:fullscreen, query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:paths, a:tmp_cfg)
  elseif key ==# g:siefe_rg_word_key
    let word = a:word ? 0 : 1
    call siefe#ripgrepfzf(query, '.', a:prompt, word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  elseif key ==# g:siefe_rg_case_key
    let case = a:case ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  elseif key ==# g:siefe_rg_hidden_key
    let hidden = a:hidden ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  elseif key ==# g:siefe_rg_no_ignore_key
    let no_ignore = a:no_ignore ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, a:hidden, no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  elseif key ==# g:siefe_rg_fixed_strings_key
    let fixed_strings = a:fixed_strings ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  elseif key ==# g:siefe_rg_max_1_key
    let max_1 = a:max_1 ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  elseif key ==# g:siefe_rg_dir_key
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, 0, 0, 'd', 0, a:orig_dir, a:dir, query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:type, a:paths, a:tmp_cfg)
  elseif key ==# 'ctrl-y'
    return s:yank_to_register(join(map(filelist, 'v:val.content'), "\n"))
  return
  endif
endfunction

" Lots of functions to use fzf to also select ie rg types
function! FzfTypeSelect(func, fullscreen, ...) abort
  call fzf#run(fzf#wrap({
        \ 'source': 'rg --color=always --type-list',
        \ 'options': [
          \ '--prompt', 'Choose type> ',
          \ '--multi',
          \ '--bind','tab:toggle+up',
          \ '--bind','shift-tab:toggle+down',
          \ '--expect', g:siefe_abort_key,
          \ '--header', s:prettify_help(g:siefe_abort_key, 'abort'),
          \ ],
        \ 'sink*': function(a:func, a:000 + [a:fullscreen])
      \ }, a:fullscreen))
endfunction


function! FzfDirSelect(func, fullscreen, fd_hidden, fd_no_ignore, fd_type, multi, orig_dir, dir, ...) abort
  let fd_hidden = a:fd_hidden ? '-H ' : ''
  let fd_hidden_toggle = a:fd_hidden ? 'off' : 'on'
  let fd_no_ignore = a:fd_no_ignore ? '-u ' : ''
  let fd_no_ignore_toggle = a:fd_no_ignore ? 'off' : 'on'
  let fd_type = a:fd_type !=# '' ? ' --type ' . a:fd_type : ''

  let siefe_fd_project_root_key = g:siefe_fd_project_root_env ==# '' ? '' : g:siefe_fd_project_root_key . ','
  let siefe_fd_project_root_help = g:siefe_fd_project_root_env ==# '' ? '' : ' ╱ ' . s:prettify_help(g:siefe_fd_project_root_key, '√work')

  let options = [
    \ '--print-query',
    \ '--ansi',
    \ '--scheme=path',
    \ '--bind', 'tab:toggle+up',
    \ '--bind', 'shift-tab:toggle+down',
    \ '--prompt', fd_no_ignore.fd_hidden.'fd> ',
    \ '--expect='
    \ . g:siefe_fd_hidden_key . ','
    \ . g:siefe_fd_no_ignore_key . ','
    \ . g:siefe_fd_git_root_key . ','
    \ . siefe_fd_project_root_key
    \ . g:siefe_abort_key,
    \ '--header', s:prettify_help(g:siefe_fd_hidden_key, 'hidden:' . fd_hidden_toggle)
      \ . ' ╱ ' . s:prettify_help(g:siefe_fd_no_ignore_key, 'no ignore:' . fd_no_ignore_toggle)
      \ . ' ╱ ' . s:prettify_help(g:siefe_fd_git_root_key, '√git')
      \ . siefe_fd_project_root_help
      \ . ' ╱ ' . s:prettify_help(g:siefe_abort_key, 'abort')
    \ ]
  if a:multi
    let options += ['--multi']
  endif

  call fzf#run(fzf#wrap({
          \ 'source': s:fd_command . ' --color=always '.fd_hidden.fd_no_ignore.fd_type.' --search-path=`realpath --relative-to=. "'.a:dir.'"` --relative-path ',
        \ 'options': options,
        \ 'sink*': function(a:func, [a:fd_hidden, a:fd_no_ignore, a:orig_dir, a:dir] + a:000 + [a:fullscreen])
      \ }, a:fullscreen))
endfunction

function! RipgrepFzfDir(fd_hidden, fd_no_ignore, orig_dir, dir, query, prompt, word, case, hidden, no_ignore, fixed_strings, max_1, type, paths, tmp_cfg, fullscreen, lines) abort
  let fd_query = a:lines[0]
  let key = a:lines[1]

  if len(a:lines) == 3
    let new_dir = a:lines[2]
  else
    let new_dir = a:dir
  endif

  if key ==# g:siefe_abort_key
    call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  elseif key ==# g:siefe_fd_hidden_key
    let fd_hidden = a:fd_hidden ? 0 : 1
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, fd_hidden, a:fd_no_ignore, 'd', 0, a:orig_dir, a:dir, a:query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:type, a:paths, a:tmp_cfg)
  elseif key ==# g:siefe_fd_no_ignore_key
    let fd_no_ignore = a:fd_no_ignore ? 0 : 1
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, a:fd_hidden, fd_no_ignore, 'd', 0, a:orig_dir, a:dir, a:query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:type, a:paths, a:tmp_cfg)
  elseif key ==# g:siefe_fd_git_root_key
    call siefe#ripgrepfzf(a:query,  siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  elseif key ==# g:siefe_fd_project_root_key
    call siefe#ripgrepfzf(a:query, expand(g:siefe_fd_project_root_env), g:siefe_fd_project_root_env, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  else
    call siefe#ripgrepfzf(a:query, trim(system('realpath '.new_dir)), siefe#get_relative_git_or_bufdir(new_dir), a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, a:type, a:paths, a:tmp_cfg, a:fullscreen)
  endif
endfunction

function! RipgrepFzfType(query, dir, prompt, word, case, hidden, no_ignore, fixed_strings, max_1, orig_dir, paths, tmp_cfg, fullscreen, lines) abort
  if a:lines[0] ==# g:siefe_abort_key
    call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, '', a:paths, a:tmp_cfg, a:fullscreen)
  else
    let type = join(map(a:lines[1:], '"-t" . split(v:val, ":")[0]'))
    call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, type, a:paths, a:tmp_cfg, a:fullscreen)
  endif
endfunction

function! RipgrepFzfTypeNot(query, dir, prompt, word, case, hidden, no_ignore, fixed_strings, max_1, orig_dir, paths, tmp_cfg, fullscreen, lines) abort
  if a:lines[0] ==# g:siefe_abort_key
    call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, '', a:paths, a:tmp_cfg, a:fullscreen)
  else
    let type = join(map(a:lines[1:], '"-T" . split(v:val, ":")[0]'))
    call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:max_1, a:orig_dir, type, a:paths, a:tmp_cfg, a:fullscreen)
  endif
endfunction

function! siefe#gitlogfzf(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, type, fullscreen) abort
  call s:check_requirements()

  if a:branches ==# '--all'
    let branches = '--all '
    let notbranches = ''
  else
    let branches = a:branches ==# '' ? '' : a:branches . ' '
    let notbranches = a:notbranches ==# '' ? '' : a:notbranches . ' '
  endif
  let authors = join(map(copy(a:authors), '"--author=".shellescape(v:val)'))
  let paths = join(a:paths)
  let query_file = tempname()
  let G = a:G ? '-G ' : '-S '
  let follow = paths ==# '' ? '' : a:follow ? '--follow' : ''
  " --pickaxe-regex and -G are incompatible
  let regex = a:G ? '' : a:regex ? '--pickaxe-regex ' : ''
  let ignore_case = a:ignore_case ? '--regexp-ignore-case ' : ''
  let ignore_case_toggle = a:ignore_case ? 'off' : 'on'
  let ignore_case_symbol = a:ignore_case ? '-i ' : ''
  " git log -S/G doesn't work with empty value, so we strip it if the query is
  " empty. Not sure why we need to escape [ and ]
  let command_fmt = s:bin.git_SG . ' log '. G . '%s -z ' . follow . ' ' . branches . ' ' . notbranches . ' ' . authors . ' ' . regex . ' ' . ignore_case
  let write_query_initial = 'echo '. shellescape(a:query) .' > '.query_file.' ;'
  let write_query_reload = 'echo {q} > '.query_file.' ;'
  let remove_newlines = '| sed -z -E "s/\r?\n/↵/g"'
  let format = '--format=%C(auto)%h • %d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)%b'
  let initial_command = write_query_initial . printf(command_fmt, shellescape(a:query)).fzf#shellescape(format).' -- ' . paths . remove_newlines
  let reload_command = write_query_reload . printf(command_fmt, '{q}').fzf#shellescape(format).' -- ' . paths . remove_newlines
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

  let authors_info = a:authors ==# [] ? '' : "\nauthors: ".join(a:authors)
  let paths_info = a:paths ==# [] ? '' : "\npaths: ".join(a:paths)
  let type_info = a:type ==# '' ? '' : "\ntypes: " . a:type

  let default_preview_size = &columns < g:siefe_preview_hide_threshold ? '0%' : g:siefe_default_preview_size . '%'
  let other_preview_size = &columns < g:siefe_preview_hide_threshold ? g:siefe_default_preview_size . '%' : 'hidden'
  let spec = {
    \ 'options': [
      \ '--history', expand('~/.vim_fzf_history'),
      \ '--preview', preview_commands[ g:siefe_gitlog_default_preview_command ],
      \ '--bind', g:siefe_gitlog_preview_0_key . ':change-preview:'.preview_command_0,
      \ '--bind', g:siefe_gitlog_preview_1_key . ':change-preview:'.preview_command_1,
      \ '--bind', g:siefe_gitlog_preview_2_key . ':change-preview:'.preview_command_2,
      \ '--bind', g:siefe_gitlog_preview_3_key . ':change-preview:'.preview_command_3,
      \ '--bind', g:siefe_gitlog_preview_4_key . ':change-preview:'.preview_command_4,
      \ '--print-query',
      \ '--layout=reverse-list',
      \ '--ansi',
      \ '--disabled',
      \ '--read0',
      \ '--expect='
        \ . g:siefe_gitlog_author_key . ','
        \ . g:siefe_gitlog_sg_key . ','
        \ . g:siefe_gitlog_branch_key . ','
        \ . g:siefe_gitlog_not_branch_key . ','
        \ . g:siefe_gitlog_ignore_case_key . ','
        \ . g:siefe_gitlog_vdiffsplit_key . ','
        \ . g:siefe_gitlog_type_key . ','
        \ . g:siefe_gitlog_dir_key . ',',
      \ '--multi',
      \ '--bind','tab:toggle+up',
      \ '--bind','shift-tab:toggle+down',
      \ '--query', a:query,
      \ '--delimiter', '•',
      \ '--preview-window', default_preview_size,
      \ '--bind', g:siefe_toggle_preview_key . ':change-preview-window(' . other_preview_size . '|' . g:siefe_2nd_preview_size . '%|)',
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', g:siefe_gitlog_fzf_key . ':unbind(change,' . g:siefe_gitlog_fzf_key . ')+change-prompt(pickaxe/fzf> )+enable-search+rebind(' . g:siefe_gitlog_s_key . ')',
      \ '--bind', g:siefe_gitlog_s_key . ':unbind(change,' . g:siefe_gitlog_s_key . ')+change-prompt(' . branches . notbranches . G . regex . ignore_case_symbol . 'pickaxe> '. ')+disable-search+reload(' . reload_command . '"+rebind(change,' . g:siefe_gitlog_fzf_key . ')',
      \ '--header', s:prettify_help(g:siefe_gitlog_ignore_case_key, 'ignore case')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_fzf_key,  'fzf messages')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_author_key, 'authors')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_branch_key, 'branches')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_sg_key, 'toggle S/G')
        \ . "\n" . s:prettify_help(g:siefe_gitlog_not_branch_key, '^branches')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_type_key, 'type')
        \ . ' ╱ ' . s:prettify_help(g:siefe_gitlog_s_key, 'pickaxe')
        \ . ' ╱ ' . s:magenta(s:preview_help(s:gitlog_preview_keys), 'Special') . ' change preview'
        \ . authors_info
        \ . paths_info
        \ . type_info,
      \ '--prompt', branches . notbranches . G . regex . ignore_case_symbol . 'pickaxe> ',
      \ ],
   \ 'sink*': function('s:gitpickaxe_sink', [a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen]),
   \ 'source': initial_command
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:gitpickaxe_sink(branches, notbranches, authors, G, regex, paths, follow, ignore_case, type, fullscreen, lines) abort
  " required when using fullscreen and abort, not sure why
  if len(a:lines) == 0
    return
  endif

  let query = a:lines[0]
  let key = a:lines[1]
  " split(v:val, " ")[0]) == commit hash
  " join(split(v:val, " ")[1:] == full commit message
  let quickfix_list = map(a:lines[2:], '{'
    \ . '"bufnr":bufadd(trim(fugitive#Open("", 0, "<mods>", split(v:val, " ")[0]))),'
    \ . '"text":join(split(v:val, " ")[1:], " ")[:(winwidth(0) - (len(split(v:val, " ")[0]) + 7))] . ( len(join(split(v:val, " ")[1:], " ")) > winwidth(0) ? "..." : ""),'
    \ . '"module":split(v:val, " ")[0],'
    \ . '}')

  if key == g:siefe_gitlog_sg_key
    let G = a:G ? 0 : 1
    call siefe#gitlogfzf(query, a:branches, a:notbranches, a:authors, G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen)
  elseif key == g:siefe_gitlog_ignore_case_key
    let ignore_case = a:ignore_case ? 0 : 1
    call siefe#gitlogfzf(query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, ignore_case, a:type, a:fullscreen)
  elseif key == g:siefe_gitlog_branch_key
    call FzfBranchSelect('GitPickaxeFzfBranch', a:fullscreen, 0, query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type)
  elseif key == g:siefe_gitlog_not_branch_key
    call FzfBranchSelect('GitPickaxeFzfNotBranch', a:fullscreen, 1, query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type)
  elseif key == g:siefe_gitlog_author_key
    call FzfAuthorSelect('GitPickaxeFzfAuthor', a:fullscreen, query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type)
  elseif key == g:siefe_gitlog_dir_key
    call FzfDirSelect('GitPickaxeFzfPath', a:fullscreen ,0, 0, '', 1, siefe#bufdir(), siefe#bufdir(), query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type)
  elseif key == g:siefe_gitlog_type_key
    " git understands rg --type-list globs :)
    call FzfTypeSelect('GitlogFzfType', a:fullscreen, query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type)
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

function! GitlogFzfType(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, type, fullscreen, lines) abort
  let type = substitute(join(map(a:lines[1:], 'split(v:val, ":")[1]'), ' '), ',', '', 'g')
  call siefe#gitlogfzf(a:query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, type, a:fullscreen)
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
    \ 'sink*':   function(a:func, a:000 + [a:fullscreen]),
    \ 'options':
      \ [
        \ '--ansi',
        \ '--multi',
        \ '--delimiter', ':',
        \ '--bind', 'f1:change-preview:'.preview_command_1,
        \ '--bind', 'f2:change-preview:'.preview_command_2,
        \ '--bind', 'f3:change-preview:'.preview_command_3,
        \ '--bind', 'f4:change-preview:'.preview_command_4,
        \ '--bind','tab:toggle+up',
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
    \ 'sink*':   function(a:func, a:000 + [a:fullscreen]),
    \ 'options':
      \ [
        \ '--multi',
        \ '--bind','tab:toggle+up',
        \ '--expect', g:siefe_abort_key,
        \ '--header', s:prettify_help(g:siefe_abort_key, 'abort'),
        \ '--bind','shift-tab:toggle+down',
      \ ],
    \ 'placeholder': ''
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! GitPickaxeFzfAuthor(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, type, fullscreen, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    call siefe#gitlogfzf(a:query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen)
  else
    call siefe#gitlogfzf(a:query, a:branches, a:notbranches, a:000[0][1:], a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen)
  endif
endfunction

function! GitPickaxeFzfBranch(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, type, fullscreen, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    call siefe#gitlogfzf(a:query, '', a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen)
  elseif a:000[0][0] == g:siefe_branches_all_key
    call siefe#gitlogfzf(a:query, '--all', a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen)
  else
    let branches = join(map(a:000[0][1:], 'trim(split(v:val, ":")[0], " *")'))
    call siefe#gitlogfzf(a:query, branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen)
  endif
endfunction

function! GitPickaxeFzfNotBranch(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, type, fullscreen, ...) abort
  if a:000[0][0] == g:siefe_abort_key
    call siefe#gitlogfzf(a:query, a:branches, '', a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen)
  else
    let notbranches = join(map(a:000[0][1:], '"^" . trim(split(v:val, ":")[0], " *")'))
    call siefe#gitlogfzf(a:query, a:branches, notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen)
  endif
endfunction

function! GitPickaxeFzfPath(fd_hidden, fd_no_ignore, orig_dir, dir, query, branch, notbranches, authors, G, regex, paths, follow, ignore_case, type, fullscreen, ...) abort
  let paths = a:000[0][2:]
  call siefe#gitlogfzf(a:query, a:branch, a:notbranches, a:authors, a:G, a:regex, paths, a:follow, a:ignore_case, a:type, a:fullscreen)
endfunction

function! siefe#gitllogfzf(query, branches, notbranches, authors, G, regex, path, follow, ignore_case, line_range, fullscreen) abort
  " git -L is a bit crippled and ignores --format, so we have to make our own with sed
  let command = 'git log  -s -z -L' . a:line_range[0] . ',' . a:line_range[1] . ':' . a:path . ' --abbrev-commit -- '
    \ . '| sed -E -z "s/commit ([0-9a-f]*)([^\n]*)*.*\n\n/\1\2 •/" '
    \ . '| sed -E -z "s/ {2,}/ /g"'
    \ . '| sed -z -E "s/\r?\n/↵/g"'
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
