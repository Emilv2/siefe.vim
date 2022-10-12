let s:min_version = '0.33.0'
let s:is_win = has('win32') || has('win64')
let s:is_wsl_bash = s:is_win && (exepath('bash') =~? 'Windows[/\\]system32[/\\]bash.exe$')
let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:p:h:h').'/bin/'
let s:bin = {
\ 'pickaxe_diff': s:bin_dir.'pickaxe-diff',
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

let s:checked = 0

function! s:check_requirements()
  if s:checked
    return
  endif

  if !exists('*fzf#run')
    throw "fzf#run function not found. You also need Vim plugin from the main fzf repository (i.e. junegunn/fzf *and* junegunn/fzf.vim)"
  endif
  if !exists('*fzf#exec')
    throw "fzf#exec function not found. You need to upgrade Vim plugin from the main fzf repository ('junegunn/fzf')"
  endif
  let gitlog_dups = s:detect_dups(s:gitlog_preview_keys)
  if gitlog_dups !=# ""
    throw 'duplicates found in `siefe_gitlog_*_key`s :'. gitlog_dups
  endif


  let s:checked = !empty(fzf#exec(s:min_version))
endfunction

""" load configuration options
let g:siefe_delta_options = get(g:, 'siefe_delta_options', '--keep-plus-minus-markers') . ' ' . get(g:, 'siefe_delta_extra_options', '')
let g:siefe_bat_options = get(g:, 'siefe_bat_options', '--style=numbers,changes --theme="Solarized (dark)"') . ' ' . get(g:, 'siefe_bat_extra_options', '')

let g:siefe_rg_preview_key = get(g:, 'siefe_rg_preview_key', 'f1')
let g:siefe_rg_fast_preview_key = get(g:, 'siefe_rg_fast_preview_key', 'f2')

let s:rg_preview_keys = [
  \ g:siefe_rg_preview_key,
  \ g:siefe_rg_fast_preview_key,
\ ]

let s:bat_command = executable('bat') ? 'bat' : executable('batcat') ? 'batcat' : ""
let s:files_preview_command = s:bat_command != "" ? s:bat_command . ' --color=always --pager=never ' . g:siefe_bat_options . ' -- {}' : 'cat {}'
let s:rg_preview_command = s:bat_command != "" ? s:bat_command . ' --color=always --highlight-line={2} --pager=never ' . g:siefe_bat_options . ' -- {1}' : 'cat {1}'
let s:rg_fast_preview_command = 'cat {1}'

let s:rg_preview_commands = [
  \ s:rg_preview_command,
  \ s:rg_fast_preview_command,
\ ]

let g:siefe_rg_default_preview_command = get(g:, 'siefe_rg_default_preview', 0)

let s:siefe_gitlog_ignore_case_key = 'alt-i'
let g:siefe_gitlog_vdiffsplit_key = get(g:, 'siefe_gitlog_vdiffsplit_key', 'ctrl-v')
let g:siefe_gitlog_type_key = get(g:, 'siefe_gitlog_type_key', 'ctrl-t')

let g:siefe_gitlog_preview_1_key = get(g:, 'siefe_gitlog_preview_1_key', 'f1')
let g:siefe_gitlog_preview_2_key = get(g:, 'siefe_gitlog_preview_2_key', 'f2')
let g:siefe_gitlog_preview_3_key = get(g:, 'siefe_gitlog_preview_3_key', 'f3')
let g:siefe_gitlog_preview_4_key = get(g:, 'siefe_gitlog_preview_4_key', 'f4')
let g:siefe_gitlog_preview_5_key = get(g:, 'siefe_gitlog_preview_5_key', 'f5')

let s:gitlog_preview_keys = [
  \ g:siefe_gitlog_preview_1_key,
  \ g:siefe_gitlog_preview_2_key,
  \ g:siefe_gitlog_preview_3_key,
  \ g:siefe_gitlog_preview_4_key,
  \ g:siefe_gitlog_preview_5_key,
\ ]

""" ripgrep function, commands and maps
function! siefe#ripgrepfzf(query, dir, prompt, word, case_sensitive, hidden, no_ignore, fixed_strings, orig_dir, type, fullscreen)
  call s:check_requirements()

  if empty(a:dir)
    return
  endif
  let word = a:word ? "-w " : ""
  let word_toggle = a:word ? "off" : "on"
  let hidden = a:hidden ? "-. " : ""
  let hidden_toggle = a:hidden ? "off" : "on"
  let case_sensitive = a:case_sensitive ? "--case-sensitive " : "--smart-case "
  let case_symbol = a:case_sensitive ? "-s " : ""
  let case_toggle = a:case_sensitive ? "off" : "on"
  let no_ignore = a:no_ignore ? "-u " : ""
  let no_ignore_toggle = a:no_ignore ? "off" : "on"
  let fixed_strings = a:fixed_strings ? "-F " : ""
  let fixed_strings_toggle = a:fixed_strings ? "off" : "on"
  let command_fmt = 'rg --column -U --glob "!.git/objects" --line-number --no-heading --color=always --colors "column:fg:green" '.case_sensitive.' --field-match-separator="\x1b[9;31;31m//\x1b[0m" '.word.no_ignore.hidden.fixed_strings.' '.a:type.' %s -- %s'
  let initial_command = printf(command_fmt, '', shellescape(a:query))
  let reload_command = printf(command_fmt, '', '{q}')
  let empty_command = printf(command_fmt, '', '""')
  let word_command = printf(command_fmt, '-w', '{q}')
  let files_command = 'rg --color=always --files '.a:type
  " https://github.com/junegunn/fzf.vim
  " https://github.com/junegunn/fzf/blob/master/ADVANCED.md#toggling-between-data-sources
  let spec = {
    \ 'options': [
      \ '--history', expand("~/.vim_fzf_history"),
      \ '--preview', s:rg_preview_commands[g:siefe_rg_default_preview_command],
      \ '--bind', g:siefe_rg_preview_key . ':change-preview:'.s:rg_preview_command,
      \ '--bind', g:siefe_rg_fast_preview_key . ':change-preview:'.s:rg_fast_preview_command,
      \ '--print-query',
      \ '--ansi',
      \ '--phony',
      \ '--print0',
      \ '--expect=ctrl-t,ctrl-n,ctrl-w,alt-.,ctrl-s,alt-f,ctrl-u,ctrl-d,ctrl-y',
      \ '--preview-window', '+{2}-/2',
      \ '--multi',
      \ '--bind','tab:toggle+up',
      \ '--bind','shift-tab:toggle+down',
      \ '--query', a:query,
      \ '--delimiter', '//',
      \ '--bind', 'ctrl-/:change-preview-window(hidden|right,90%|)',
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', 'change:+first',
      \ '--bind', 'ctrl-f:unbind(change,ctrl-f,alt-r)+change-prompt('.no_ignore.hidden.a:type . ' ' . a:prompt.' fzf> )+enable-search+rebind(ctrl-r,ctrl-l)+reload('.empty_command.')+change-preview(' . s:rg_preview_commands[g:siefe_rg_default_preview_command] . ')',
      \ '--bind', 'alt-r:unbind(change,alt-r)+change-prompt('.no_ignore.hidden.a:type . ' ' . a:prompt.' rg/fzf> )+enable-search+rebind(ctrl-r,ctrl-f,ctrl-l)+change-preview(' . s:rg_preview_commands[g:siefe_rg_default_preview_command] . ')',
      \ '--bind', 'ctrl-r:unbind(ctrl-r)+change-prompt('.word.no_ignore.hidden.case_symbol.fixed_strings.a:type . ' ' . a:prompt.' rg> )+disable-search+reload('.reload_command.')+rebind(change,ctrl-f,ctrl-l,alt-r)+change-preview(' . s:rg_preview_commands[g:siefe_rg_default_preview_command] . ')',
      \ '--bind', 'ctrl-l:unbind(change,ctrl-l)+change-prompt('.no_ignore.hidden.fixed_strings.a:type . ' ' . a:prompt.' Files> )+enable-search+rebind(ctrl-r,ctrl-f,alt-r)+reload('.files_command.')+change-preview('.s:files_preview_command.')',
      \ '--header', s:magenta('^-R', 'Special')." Rg ╱ ".s:magenta('^-F', 'Special')." fzf ╱ ".s:magenta('M-R', 'Special')." rg/fzf ╱ ".s:magenta('^-F', 'Special')." Fi\e[3ml\e[0mes / "
      \ .s:magenta('^-T', 'Special').' Type / '.s:magenta('^-N', 'Special')." !Type / ".s:magenta('^-D', 'Special')." c\e[3md\e[0m / ".s:magenta('^-Y', 'Special')." yank\n"
      \ .s:magenta('^-W', 'Special')." -w ".word_toggle.' / '.s:magenta('^-U', 'Special')." -u ".no_ignore_toggle.
      \ " / ".s:magenta('M-.', 'Special')." -. ".hidden_toggle." / ".s:magenta('^-S', 'Special')." / -s ".case_toggle." / ".s:magenta('^-F', 'Special')." / -F ".fixed_strings_toggle
      \ . ' / ' . s:magenta(s:preview_help(s:rg_preview_keys), 'Special') . ' change preview',
      \ '--prompt', word.no_ignore.hidden.case_symbol.fixed_strings.a:type . ' ' . a:prompt.' rg> ',
      \ ],
   \ 'dir': a:dir,
   \ 'sink*': function('s:ripgrep_sink', [a:dir, a:prompt, a:word, a:case_sensitive, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen]),
   \ 'source': initial_command
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:ripgrep_sink(dir, prompt, word, case, hidden, no_ignore, fixed_strings, orig_dir, type, fullscreen, lines)

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
    let tmp2 = split(item, '\/\/', 1)
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
        let file.content = join(tmp2[3:], '//')."\n"
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


  if key == ''
    execute 'e' file.filename
    call cursor(file.line, file.column)
    normal! zvzz

    call s:fill_quickfix(filelist)
  endif

  " work around for strange nested fzf change directory behaviour
  " when nested it will not cd back to the original directory
  exe 'cd' a:orig_dir

  if key == 'ctrl-t'
    call FzfTypeSelect('RipgrepFzfType', a:fullscreen, query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir)
  elseif key == 'ctrl-n'
    call FzfTypeSelect('RipgrepFzfTypeNot', a:fullscreen, query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir)
  elseif key == 'ctrl-w'
    let word = a:word ? 0 : 1
    call siefe#ripgrepfzf(query, ".", a:prompt, word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen)
  elseif key == 'ctrl-s'
    let case = a:case ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen)
  elseif key == 'alt-.'
    let hidden = a:hidden ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen)
  elseif key == 'ctrl-u'
    let no_ignore = a:no_ignore ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, a:hidden, no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen)
  elseif key == 'alt-f'
    let fixed_strings = a:fixed_strings ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, fixed_strings, a:orig_dir, a:type, a:fullscreen)
  elseif key == 'ctrl-d'
    call FzfDirSelect('RipgrepFzfDir', a:fullscreen, 0, 0, "d", 0, a:orig_dir, a:dir, query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:type)
  elseif key == 'ctrl-y'
    return s:yank_to_register(join(map(filelist, 'v:val.content'), "\n"))
  return
  endif
endfunction

" Lots of functions to use fzf to also select ie rg types
function! FzfTypeSelect(func, fullscreen, ...)
  call fzf#run(fzf#wrap({
        \ 'source': 'rg --color=always --type-list',
        \ 'options': [
          \ '--prompt', 'Choose type> ',
          \ '--multi',
          \ '--bind','tab:toggle+up',
          \ '--bind','shift-tab:toggle+down',
          \ ],
        \ 'sink*': function(a:func, a:000 + [a:fullscreen])
      \ }, a:fullscreen))
endfunction


function! FzfDirSelect(func, fullscreen, fd_hidden, fd_no_ignore, fd_type, multi, orig_dir, dir, ...)
  let fd_hidden = a:fd_hidden ? "-H " : ""
  let fd_hidden_toggle = a:fd_hidden ? "off" : "on"
  let fd_no_ignore = a:fd_no_ignore ? "-u " : ""
  let fd_no_ignore_toggle = a:fd_no_ignore ? "off" : "on"
  let fd_type = a:fd_type != "" ? " --type " . a:fd_type : ""
  let options = [
    \ '--print-query',
    \ '--ansi',
    \ '--scheme=path',
    \ '--bind', 'tab:toggle+up',
    \ '--bind', 'shift-tab:toggle+down',
    \ '--prompt', fd_no_ignore.fd_hidden.'fd> ',
    \ '--expect=ctrl-h,ctrl-u,alt-p,ctrl-alt-p',
    \ '--header', s:magenta('^-H', 'Special')." hidden ".fd_hidden_toggle." ╱ ".s:magenta('^-U', 'Special')." ignored ".fd_no_ignore_toggle
      \ . ' ╱ ' .s:magenta('M-P', 'Special').' √git / '.s:magenta('^-M-P', 'Special').' √work / '
    \ ]
  if a:multi
    let options += ['--multi']
  endif

  " fd does not print ., but we might want to select that
         " \ 'source': 'fd --color=always '.fd_hidden.fd_no_ignore.fd_type.' --search-path=`realpath --relative-to=. "'.a:dir.'"` --relative-path | ( realpath --relative-to=$PWD '.a:orig_dir.' && cat)',
  call fzf#run(fzf#wrap({
          \ 'source': 'fd --color=always '.fd_hidden.fd_no_ignore.fd_type.' --search-path=`realpath --relative-to=. "'.a:dir.'"` --relative-path ',
        \ 'options': options,
        \ 'sink*': function(a:func, [a:fd_hidden, a:fd_no_ignore, a:orig_dir, a:dir] + a:000 + [a:fullscreen])
      \ }, a:fullscreen))
endfunction

function! RipgrepFzfDir(fd_hidden, fd_no_ignore, orig_dir, dir, query, prompt, word, case, hidden, no_ignore, fixed_strings, type, fullscreen, lines)

  let fd_query = a:lines[0]
  let key = a:lines[1]
  let new_dir = a:lines[2]
  if key == 'ctrl-h'
    let fd_hidden = a:fd_hidden ? 0 : 1
    call FzfDirSelect('RipgrepFzfDir', fd_hidden, a:fd_no_ignore, "d", a:orig_dir, a:dir, a:query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:type, a:fullscreen)
  elseif key == 'ctrl-u'
    let fd_no_ignore = a:fd_no_ignore ? 0 : 1
    call FzfDirSelect('RipgrepFzfDir', a:fd_hidden, fd_no_ignore, "d", a:orig_dir, a:dir, a:query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:type, a:fullscreen)
  elseif key == 'alt-p'
    call siefe#ripgrepfzf(a:query,  siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen)
  elseif key == 'ctrl-alt-p'
    let workarea = '$WORKAREA'
    if expand(workarea) != workarea
      call siefe#ripgrepfzf(a:query, expand(workarea), workarea, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen)
    else
      call s:warn('no '.workarea)
      execute 'sleep' 500 . 'm'
      call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen)
    endif
  else
    call siefe#ripgrepfzf(a:query, trim(system('realpath '.new_dir)), siefe#get_relative_git_or_bufdir(new_dir), a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:type, a:fullscreen)
  endif
endfunction

function! RipgrepFzfType(query, dir, prompt, word, case, hidden, no_ignore, fixed_strings, orig_dir, fullscreen, type_string)
  let type = join(map(a:type_string, '"-t" . split(v:val, ":")[0]'))
  call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, type, a:fullscreen)
endfunction

function! RipgrepFzfTypeNot(query, dir, prompt, word, case, hidden, no_ignore, fixed_strings, orig_dir, fullscreen, type_string)
  let type = join(map(a:type_string, '"-T" . split(v:val, ":")[0]'))
  call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, type, a:fullscreen)
endfunction

""" ripgrep function, commands and maps
function! siefe#gitlogfzf(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, type, fullscreen)
  call s:check_requirements()

  let branches = join(map(a:branches, 'trim(v:val, " *")'))
  let notbranches = join(map(a:notbranches, '"^".trim(v:val, " *")'))
  let authors = join(map(copy(a:authors), '"--author=".shellescape(v:val)'))
  let paths = join(a:paths)
  let query_file = tempname()
  let G = a:G ? "-G" : "-S"
  let follow = paths == "" ? "" : a:follow ? "--follow" : ""
  " --pickaxe-regex and -G are incompatible
  let regex = a:G ? "" : a:regex ? "--pickaxe-regex " : ""
  let ignore_case = a:ignore_case ? "--regexp-ignore-case " : ""
  let ignore_case_toggle = a:ignore_case ? "off" : "on"
  let ignore_case_symbol = a:ignore_case ? "-i " : ""
  " git log -S/G doesn't work with empty value, so we strip it if the query is
  " empty. Not sure why we need to escape [ and ]
  let command_fmt = 'git log -z '.follow.' '.branches.' '.notbranches.' '.authors.' '.regex.' ' . ignore_case . '`echo '.G.'%s | sed s/^-\[SG\]$//g` '
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
  let preview_command_1 = preview_all_command . ' --patch --stat -- ' . suffix
  let preview_command_2 = preview_all_command . ' --format=format: --patch --stat -- ' . suffix

  let preview_command_3 = 'echo -e "\033[0;35mgit show matching files\033[0m" && git show -O'.fzf#shellescape(orderfile).' '.regex.'`{echo -n '.G.'; cat '.query_file.'} | sed s/^-\[SG\]$//g` {1} '
    \ . ' --format=format: --patch --stat -- ' . suffix

  let preview_pickaxe_hunks_command = 'echo "\033[0;35mgit show matching hunks\033[0m" && (export GREPDIFF_REGEX=`cat '.query_file.'`; git -c diff.external=' . s:bin.pickaxe_diff . ' show {1} -O'.fzf#shellescape(orderfile).' --ext-diff '.regex.'`{echo -n '.G.'; cat '.query_file.'} | sed s/^-\[SG\]$//g` '
  let no_grepdiff_message = 'echo install grepdiff from the patchutils package for this preview'
  let preview_command_4 = executable('grepdiff') ? preview_pickaxe_hunks_command . ' --format=format: --patch --stat --) ' . suffix : no_grepdiff_message
  let preview_command_5 = 'echo -e "\033[0;35mgit diff\033[0m" && git diff -O'.fzf#shellescape(orderfile).' {1} ' . suffix

  let authors_info = a:authors == [] ? '' : "\nauthors: ".join(a:authors)
  let paths_info = a:paths == [] ? '' : "\npaths: ".join(a:paths)
  let type_info = a:type == '' ? '' : "\ntypes: " . a:type

  let spec = {
    \ 'options': [
      \ '--history', expand("~/.vim_fzf_history"),
      \ '--preview', preview_command_1,
      \ '--bind', g:siefe_gitlog_preview_1_key . ':change-preview:'.preview_command_1,
      \ '--bind', g:siefe_gitlog_preview_2_key . ':change-preview:'.preview_command_2,
      \ '--bind', g:siefe_gitlog_preview_3_key . ':change-preview:'.preview_command_3,
      \ '--bind', g:siefe_gitlog_preview_4_key . ':change-preview:'.preview_command_4,
      \ '--bind', g:siefe_gitlog_preview_5_key . ':change-preview:'.preview_command_5,
      \ '--print-query',
      \ '--ansi',
      \ '--phony',
      \ '--read0',
      \ '--expect=ctrl-r,ctrl-e,ctrl-b,ctrl-n,ctrl-a,ctrl-d,'
        \ . s:siefe_gitlog_ignore_case_key . ','
        \ . g:siefe_gitlog_vdiffsplit_key . ','
        \ . g:siefe_gitlog_type_key . ',',
      \ '--multi',
      \ '--bind','tab:toggle+up',
      \ '--bind','shift-tab:toggle+down',
      \ '--query', a:query,
      \ '--delimiter', '•',
      \ '--bind', 'ctrl-/:change-preview-window(hidden|right,90%|)',
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', 'ctrl-f:unbind(change,ctrl-f)+change-prompt(pickaxe/fzf> )+enable-search+rebind(ctrl-r,ctrl-l)',
      \ '--header', s:magenta('^-R', 'Special')." Rg ╱ ".s:magenta('^-F', 'Special')." fzf ╱ ".s:prettify_help(s:siefe_gitlog_ignore_case_key, "ignore case")
        \ ." ╱ ".s:prettify_help("ctrl-e", "cde") . ' / ' . s:magenta(s:preview_help(s:gitlog_preview_keys), 'Special') . ' change preview'
        \ .' ╱  '.s:prettify_help(g:siefe_gitlog_type_key, 'type')
        \ . authors_info 
        \ . paths_info
        \ . type_info,
      \ '--prompt', regex.branches.' '.notbranches.' '.G.regex.' ' . ignore_case_symbol . ' pickaxe> ',
      \ ],
   \ 'sink*': function('s:gitpickaxe_sink', [a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:type, a:fullscreen]),
   \ 'source': initial_command
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! s:gitpickaxe_sink(branches, notbranches, authors, G, regex, paths, follow, ignore_case, fullscreen, type, lines)
  let query = a:lines[0]
  let key = a:lines[1]
  " split(v:val, " ")[0]) == commit hash
  " join(split(v:val, " ")[1:] == full commit message
  let quickfix_list = map(a:lines[2:], '{'
    \ . '"bufnr":bufadd(trim(fugitive#Open("", 0, "<mods>", split(v:val, " ")[0]))),'
    \ . '"text":join(split(v:val, " ")[1:], " ")[:(winwidth(0) - (len(split(v:val, " ")[0]) + 7))] . ( len(join(split(v:val, " ")[1:], " ")) > winwidth(0) ? "..." : ""),'
    \ . '"module":split(v:val, " ")[0],'
    \ . '}')

  if key == 'ctrl-e'
    let G = a:G ? 0 : 1
    call siefe#gitlogfzf(query, a:branches, a:notbranches, a:authors, G, a:regex, a:paths, a:follow, a:ignore_case, a:fullscreen)
  elseif key == s:siefe_gitlog_ignore_case_key
    let ignore_case = a:ignore_case ? 0 : 1
    call siefe#gitlogfzf(query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, ignore_case, a:fullscreen)
  elseif key == 'ctrl-b'
    call FzfBranchSelect('GitPickaxeFzfBranch', a:fullscreen, query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case)
  elseif key == 'ctrl-n'
    call FzfBranchSelect('GitPickaxeFzfNotBranch', a:fullscreen, query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case)
  elseif key == 'ctrl-a'
    call FzfAuthorSelect('GitPickaxeFzfAuthor', a:fullscreen, query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case)
  elseif key == 'ctrl-d'
    call FzfDirSelect('GitPickaxeFzfPath', a:fullscreen ,0, 0, "", 1, siefe#bufdir(), siefe#bufdir(), query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case)
  elseif key == g:siefe_gitlog_type_key
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
  call s:fill_quickfix(quickfix_list)
  endif
endfunction

function! GitlogFzfType(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, fullscreen, ...)
  let type = substitute(join(map(a:000[1], 'split(v:val, ":")[1]'), ' '), ',', '', 'g')
  call siefe#gitlogfzf(a:query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, type, a:fullscreen)
endfunction

function! FzfBranchSelect(func, fullscreen, ...)
  let preview_command_1 = 'echo git log {1} ; echo {2} -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_2 = 'echo git log ..{1} \(what they have, we dont\); echo ..{2} -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_3 = 'echo git log {1}.. \(what we have, they dont\); echo {2}.. -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_4 = 'echo git log {1}... \(what we both have, common ancester not\); echo {2}... -- | xargs git log --format="%m%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'

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
        \ '--bind','shift-tab:toggle+down',
        \ '--preview', 'echo git log {1} ; echo {2} -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"' ,
      \ ],
    \ 'placeholder': ''
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! FzfAuthorSelect(func, fullscreen, ...)
  let spec = {
    \ 'source':  "git log --format='%aN <%aE>' | awk '!x[$0]++'",
    \ 'sink*':   function(a:func, a:000 + a:fullscreen),
    \ 'options':
      \ [
        \ '--multi',
        \ '--bind','tab:toggle+up',
        \ '--bind','shift-tab:toggle+down',
      \ ],
    \ 'placeholder': ''
  \ }
  call fzf#run(fzf#wrap(spec, a:fullscreen))
endfunction

function! GitPickaxeFzfAuthor(query, branch, notbranches, authors, G, regex, paths, follow, ignore_case, fullscreen, ...)
  call siefe#gitlogfzf(a:query, a:branch, a:notbranches, a:000[0], a:G, a:regex, a:paths, a:follow, a:ignore_case, a:fullscreen)
endfunction

function! GitPickaxeFzfBranch(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, fullscreen, ...)
  let branches = map(a:000[0], 'trim(split(v:val, ":")[0], " *")')
  call siefe#gitlogfzf(a:query, branches, a:notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:fullscreen)
endfunction

function! GitPickaxeFzfNotBranch(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, fullscreen, ...)
  let notbranches = map(a:000[0], 'trim(split(v:val, ":")[0], " *")')
  call siefe#gitlogfzf(a:query, a:branches, notbranches, a:authors, a:G, a:regex, a:paths, a:follow, a:ignore_case, a:fullscreen)
endfunction
"a:fd_hidden, a:fd_no_ignore, a:orig_dir, a:dir
function! GitPickaxeFzfPath(fd_hidden, fd_no_ignore, orig_dir, dir, query, branch, notbranches, authors, G, regex, paths, follow, ignore_case, fullscreen, ...)
  let paths = a:000[0][2:]

  call siefe#gitlogfzf(a:query, a:branch, a:notbranches, a:authors, a:G, a:regex, paths, a:follow, a:ignore_case, a:fullscreen)
endfunction

function! siefe#gitllogfzf(query, branches, notbranches, authors, G, regex, paths, follow, ignore_case, line_range, fullscreen)
  " git -L is a bit crippled and ignores --format, so we have to make our own with sed
  let command = 'git log  -s -z -L' . line_range[0] . ',' . line_range[1] . ':' . a:path . ' --abbrev-commit -- '
    \ '| sed -E -z "s/commit ([0-9a-f]*)([^\n]*)*.*\n\n/\1\2 •/" '
    \ '| sed -E -z "s/ {2,}/ /g"'
    \ '| sed -z -E "s/\r?\n/↵/g"'
endfunction

""" helper functions
function! s:warn(message)
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function!  siefe#bufdir()
  return substitute(split(expand('%:p:h'), '[/\\]\.git\([/\\]\|$\)')[0], '^fugitive://', '', '')
endfunction

function! siefe#get_git_root()
  let bufdir = siefe#bufdir()
  let root = systemlist('git -C ' . fzf#shellescape(bufdir) . ' rev-parse --show-toplevel')[0]
  return v:shell_error ? s:warn('Not in a git repository') : root
endfunction

function! siefe#get_git_basename_or_bufdir()
  let bufdir = siefe#bufdir()
  let basename = '#'.systemlist('basename `git -C '. fzf#shellescape(bufdir) .' rev-parse --show-toplevel`')[0]
  return v:shell_error ? bufdir : basename
endfunction

function! siefe#get_relative_git_or_bufdir(...)
  let bufdir = siefe#bufdir()
  if a:0 == 0
    let dir = get(a:, 1, "")
    let rel_dir = trim(system('git -C '. fzf#shellescape(bufdir) .' rev-parse --show-prefix'))
    return v:shell_error ? bufdir : '#'.split(system('basename `git -C ' . fzf#shellescape(bufdir) . ' rev-parse --show-toplevel`'), '\n')[0].'/'.rel_dir
  else
    let dir = get(a:, 1, "")
    let git_dir = trim(system('git -C '. fzf#shellescape(bufdir) .' rev-parse --show-toplevel'))
    let rel_to_dir = v:shell_error ? bufdir : git_dir
    let prefix = v:shell_error ? "" : siefe#get_git_basename_or_bufdir()."/"
    return prefix.trim(system('realpath --relative-to='.rel_to_dir.' '.dir))
  endif
endfunction

function! s:get_color(attr, ...)
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

function! s:csi(color, fg)
  let prefix = a:fg ? '38;' : '48;'
  if a:color[0] == '#'
    return prefix.'2;'.join(map([a:color[1:2], a:color[3:4], a:color[5:6]], 'str2nr(v:val, 16)'), ';')
  endif
  return prefix.'5;'.a:color
endfunction

function! s:ansi(str, group, default, ...)
  let fg = s:get_color('fg', a:group)
  let bg = s:get_color('bg', a:group)
  let color = (empty(fg) ? s:ansi[a:default] : s:csi(fg, 1)) .
        \ (empty(bg) ? '' : ';'.s:csi(bg, 0))
  return printf("\x1b[%s%sm%s\x1b[m", color, a:0 ? ';1' : '', a:str)
endfunction

for s:color_name in keys(s:ansi)
  execute "function! s:".s:color_name."(str, ...)\n"
        \ "  return s:ansi(a:str, get(a:, 1, ''), '".s:color_name."')\n"
        \ "endfunction"
endfor

function! s:fill_quickfix(list, ...)
  if len(a:list) > 1
    call setqflist(a:list)
    copen
    wincmd p
    if a:0
      execute a:1
    endif
  endif
endfunction

function! s:yank_to_register(data)
  let @" = a:data
  silent! let @* = a:data
  silent! let @+ = a:data
endfunction

function! s:prettify_help(key, text)
  let char = split(a:key, '-')[-1]
  return s:magenta(toupper(a:key), 'Special') . " " . a:text[0] . substitute(a:text[1:], char, "\e[3m".char."\e[m", "")
endfunction

function! s:preview_help(preview_keys)
  let f_keys = filter(copy(a:preview_keys), 'v:val[0] ==? "f"')
  let non_f_keys = filter(copy(a:preview_keys), 'v:val[0] !=? "f"')
  let f_ints = sort(map(f_keys, 'str2nr(v:val[1:])'), 'n')
  let last_val = f_ints[0]
  let result = ""
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

function! s:detect_dups(lst)
  let dict = {}
  let dups = ""
  for item in a:lst
    if has_key(dict, item)
      let dups .= ' ' . item
    endif
    let dict[item] = '0'
  endfor
  return dups
endfunction

" https://stackoverflow.com/a/47051271
function! siefe#visual_selection()
    if mode()=="v"
        let [line_start, column_start] = getpos("v")[1:2]
        let [line_end, column_end] = getpos(".")[1:2]
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

function! siefe#visual_line_nu()
    if mode()=='v'
        let line_start = getpos('v')[1]
        let line_end = getpos('.')[1]
    else
        let line_start = getpos("'<")[1]
        let line_end = getpos("'>")[1]
    end
    return sort([line_start, line_end], 'n')
endfunction
