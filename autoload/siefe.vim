""" ripgrep function, commands and maps
function! siefe#ripgrepfzf(query, dir, prompt, word, case_sensitive, hidden, no_ignore, fixed_strings, orig_dir, fullscreen, ...)
  let extraargs = get(a:, 1, "")
  let extrapromptarg = get(a:, 2, "")
  let extraprompt = get(a:, 3, "")
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
  let command_fmt = 'rg --column -U --glob "!.git/objects" --line-number --no-heading --color=always --colors "column:fg:green" '.case_sensitive.' --field-match-separator="\x1b[9;31;31m//\x1b[0m" '.word.no_ignore.hidden.fixed_strings.extraargs.' '.extrapromptarg.' %s -- %s'
  let initial_command = printf(command_fmt, '', shellescape(a:query))
  let reload_command = printf(command_fmt, '', '{q}')
  let empty_command = printf(command_fmt, '', '""')
  let word_command = printf(command_fmt, '-w', '{q}')
  let files_command = 'rg --color=always --files '.extraargs.' '.extrapromptarg
  " https://github.com/junegunn/fzf.vim
  " https://github.com/junegunn/fzf/blob/master/ADVANCED.md#toggling-between-data-sources
  let rg_preview_command = 'bat --color=always --highlight-line={2} --style=numbers,changes --theme="Solarized (dark)" --pager=never -- {1}'
  let files_preview_command = 'bat --color=always --style=numbers --theme="Solarized (dark)" --pager=never -- {}'
  let spec = {
    \ 'options': [
      \ '--history', expand("~/.vim_fzf_history"),
      \ '--preview', rg_preview_command,
      \ '--print-query',
      \ '--ansi',
      \ '--phony',
      \ '--print0',
      \ '--expect=ctrl-t,ctrl-n,ctrl-w,alt-.,ctrl-s,alt-f,ctrl-u,ctrl-d,alt-p,ctrl-alt-p,ctrl-y',
      \ '--preview-window', '+{2}-/2',
      \ '--multi',
      \ '--bind','tab:toggle+up',
      \ '--bind','shift-tab:toggle+down',
      \ '--query', a:query,
      \ '--delimiter', '//',
      \ '--bind', 'ctrl-/:change-preview-window(hidden|right,90%|)',
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', 'change:+first',
      \ '--bind', 'ctrl-f:unbind(change,ctrl-f,alt-r)+change-prompt('.no_ignore.hidden.extraprompt.extrapromptarg.a:prompt.' fzf> )+enable-search+rebind(ctrl-r,ctrl-l)+reload('.empty_command.')+change-preview('.rg_preview_command.')',
      \ '--bind', 'alt-r:unbind(change,alt-r)+change-prompt('.no_ignore.hidden.extraprompt.extrapromptarg.a:prompt.' rg/fzf> )+enable-search+rebind(ctrl-r,ctrl-f,ctrl-l)+change-preview('.rg_preview_command.')',
      \ '--bind', 'ctrl-r:unbind(ctrl-r)+change-prompt('.word.no_ignore.hidden.case_symbol.fixed_strings.extraprompt.extrapromptarg.a:prompt.' rg> )+disable-search+reload('.reload_command.')+rebind(change,ctrl-f,ctrl-l,alt-r)+change-preview('.rg_preview_command.')',
      \ '--bind', 'ctrl-l:unbind(change,ctrl-l)+change-prompt('.no_ignore.hidden.fixed_strings.extraprompt.extrapromptarg.a:prompt.' Files> )+enable-search+rebind(ctrl-r,ctrl-f,alt-r)+reload('.files_command.')+change-preview('.files_preview_command.')',
      \ '--header', s:magenta('^-R', 'Special')." Rg ╱ ".s:magenta('^-F', 'Special')." fzf ╱ ".s:magenta('M-R', 'Special')." rg/fzf ╱ ".s:magenta('^-F', 'Special')." Fi\e[3ml\e[0mes / "
      \ .s:magenta('^-T', 'Special').' Type / '.s:magenta('^-N', 'Special')." !Type / ".s:magenta('^-D', 'Special')." c\e[3md\e[0m / ".s:magenta('^-Y', 'Special')." yank\n"
      \ .s:magenta('M-P', 'Special').' √git / '.s:magenta('^-M-P', 'Special').' √work / '
      \ .s:magenta('^-W', 'Special')." -w ".word_toggle.' / '.s:magenta('^-U', 'Special')." -u ".no_ignore_toggle.
      \ " / ".s:magenta('M-.', 'Special')." -. ".hidden_toggle." / ".s:magenta('^-S', 'Special')." / -s ".case_toggle." / ".s:magenta('^-F', 'Special')." / -F ".fixed_strings_toggle,
      \ '--prompt', word.no_ignore.hidden.case_symbol.fixed_strings.extraprompt.extrapromptarg.a:prompt.' rg> ',
      \ ],
   \ 'dir': a:dir,
   \ 'sink*': function('s:ripgrep_sink', [a:dir, a:prompt, a:word, a:case_sensitive, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, extraargs, extrapromptarg, extraprompt]),
   \ 'source': initial_command
  \ }
  call fzf#run(fzf#wrap(spec, 0))
endfunction

function! s:ripgrep_sink(dir, prompt, word, case, hidden, no_ignore, fixed_strings, orig_dir, fullscreen, extraargs, extrapromptarg, extraprompt, lines)

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
    " if it's bigger than 4 that means there was a // in there result
    " This doesn't matter because we don't use it (for now).
    if len(tmp2) >= 4
      let file.filename  = tmp2[0]
      let file.line  = tmp2[1]
      let file.column  = tmp2[2]

      if len(tmp2) == 4
        let file.content = tmp2[3]
      else
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
    call FzfTypeSelect('RipgrepFzfType', query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen)
  elseif key == 'ctrl-n'
    call FzfTypeSelect('RipgrepFzfTypeNot', query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen)
  elseif key == 'ctrl-w'
    let word = a:word ? 0 : 1
    call siefe#ripgrepfzf(query, ".", a:prompt, word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  elseif key == 'ctrl-s'
    let case = a:case ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  elseif key == 'alt-.'
    let hidden = a:hidden ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  elseif key == 'ctrl-u'
    let no_ignore = a:no_ignore ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, a:hidden, no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  elseif key == 'alt-f'
    let fixed_strings = a:fixed_strings ? 0 : 1
    call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  elseif key == 'ctrl-d'
    call FzfDirSelect('RipgrepFzfDir', 0, 0, a:orig_dir, a:dir, query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
    return
  elseif key == 'alt-p'
    call siefe#ripgrepfzf(query,  siefe#get_git_root(), siefe#get_git_basename_or_bufdir(), a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  elseif key == 'ctrl-alt-p'
    let workarea = '$WORKAREA'
    if expand(workarea) != workarea
      call siefe#ripgrepfzf(query,  expand(workarea), workarea, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
    else
      call s:warn('no '.workarea)
      execute 'sleep' 500 . 'm'
      call siefe#ripgrepfzf(query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
    endif
  elseif key == 'ctrl-y'
    return s:yank_to_register(join(map(filelist, 'v:val.content'), "\n"))
  return
  endif
endfunction

" Lots of functions to use fzf to also select ie rg types
function! FzfTypeSelect(func, ...)
  call fzf#run(fzf#wrap({
        \ 'source': 'rg --color=always --type-list',
        \ 'options': [
          \ '--prompt', 'Choose type> '
          \ ],
        \ 'sink': function(a:func, a:000)
      \ }, 0))
endfunction


function! FzfDirSelect(func, fd_hidden, fd_no_ignore, orig_dir, dir, ...)
  let fd_hidden = a:fd_hidden ? "-H " : ""
  let fd_hidden_toggle = a:fd_hidden ? "off" : "on"
  let fd_no_ignore = a:fd_no_ignore ? "-u " : ""
  let fd_no_ignore_toggle = a:fd_no_ignore ? "off" : "on"
  " fd does not print ., but we might want to select that
  call fzf#run(fzf#wrap({
          \ 'source': 'fd '.fd_hidden.fd_no_ignore.'--type d --search-path=`realpath --relative-to=. "'.a:dir.'"` --relative-path | ( realpath --relative-to=$PWD '.a:orig_dir.' && cat)',
        \ 'options': [
          \ '--print-query',
          \ '--prompt', fd_no_ignore.fd_hidden.'fd> ',
          \ '--expect=ctrl-h,ctrl-u',
          \ '--header', s:magenta('^-H', 'Special')." hidden ".fd_hidden_toggle." ╱ ".s:magenta('^-U', 'Special')." ignored ".fd_no_ignore_toggle
          \ ],
        \ 'sink*': function(a:func, [a:fd_hidden, a:fd_no_ignore, a:orig_dir, a:dir] + a:000)
      \ }, 0))
endfunction

function! RipgrepFzfDir(query, dir, prompt, word, case, hidden, no_ignore, fixed_strings, fd_hidden, fd_no_ignore, orig_dir, fullscreen, extraargs, extrapromptarg, extraprompt, lines)

  let fd_query = a:lines[0]
  let key = a:lines[1]
  let new_dir = a:lines[2]
  if key == 'ctrl-h'
    let fd_hidden = a:fd_hidden ? 0 : 1
    call FzfDirSelect('RipgrepFzfDir', fd_hidden, a:fd_no_ignore, a:orig_dir, a:dir, a:query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings,  a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  elseif key == 'ctrl-u'
    let fd_no_ignore = a:fd_no_ignore ? 0 : 1
    call FzfDirSelect('RipgrepFzfDir', a:fd_hidden, fd_no_ignore, a:orig_dir, a:dir, a:query, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings,  a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  else
    call siefe#ripgrepfzf(a:query, trim(system('realpath '.new_dir)), siefe#get_relative_git_or_bufdir(new_dir), a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, a:extraargs, a:extrapromptarg, a:extraprompt)
  endif
endfunction

function! RipgrepFzfType(query, dir, prompt, word, case, hidden, no_ignore, fixed_strings, orig_dir, fullscreen, type_string)
  let type = split(a:type_string, ":")[0]
  call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, "-t", type.' ')
endfunction

function! RipgrepFzfTypeNot(query, dir, prompt, word, case, hidden, no_ignore, fixed_strings, orig_dir, fullscreen, type_string)
  let type = split(a:type_string, ":")[0]
  call siefe#ripgrepfzf(a:query, a:dir, a:prompt, a:word, a:case, a:hidden, a:no_ignore, a:fixed_strings, a:orig_dir, a:fullscreen, "-T ", type.' ', "!")
endfunction

""" ripgrep function, commands and maps
function! siefe#gitlogfzf(query, branches, notbranches, authors, G, regex, fullscreen)
  let branches = join(map(a:branches, 'trim(v:val, " *")'), ' ')
  let notbranches = join(map(a:notbranches, '"^".trim(v:val, " *")'), ' ')
  let authors = join(map(copy(a:authors), '"--author=".shellescape(v:val)'), ' ')
  let query_file = tempname()
  let G = a:G ? "-G" : "-S"
  " --pickaxe-regex and -G are incompatible
  let regex = a:G ? "" : a:regex ? "--pickaxe-regex " : ""
  " git log -S/G doesn't work with empty value, so we strip it if the query is
  " empty. Not sure why we need to escape [ and ]
  let command_fmt = 'git log -z '.branches.' '.notbranches.' '.authors.' '.regex.' `echo '.G.'%s | sed s/^-\[SG\]$//g` '
  let write_query = 'echo {q} > '.query_file.' ;'
  let format = '--format=%C(auto)%h • %d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)%b'
  let initial_command = write_query. printf(command_fmt, shellescape(a:query)).fzf#shellescape(format).' -- '
  let reload_command = write_query. printf(command_fmt, '{q}').fzf#shellescape(format).' -- '
  let current = expand('%')
  let orderfile = tempname()
  call writefile([current], orderfile)
  let git_show_stat = 'git show --stat {1} -- && '
  let preview_command_1 = 'git show -O'.fzf#shellescape(orderfile).' '.regex.'`{echo -n '.G.'; cat '.query_file.'} | sed s/^-\[SG\]$//g` --format=format: {1} -- | delta --keep-plus-minus-markers'
  let preview_command_2 = git_show_stat.preview_command_1
  let preview_command_3 = '(export GREPDIFF_REGEX=`cat '.query_file.'`; git -c diff.external=pickaxe-diff show {1} -O'.fzf#shellescape(orderfile).' --format=format: --ext-diff '.regex.'`{echo -n '.G.'; cat '.query_file.'} | sed s/^-\[SG\]$//g` --) | delta --keep-plus-minus-markers'
  let preview_command_4 = git_show_stat.preview_command_3
  let preview_command_5 = 'git show -O'.fzf#shellescape(orderfile).' --format=format: {1}  -- | delta --keep-plus-minus-markers'
  let preview_command_6 = git_show_stat.preview_command_5
  let spec = {
    \ 'options': [
      \ '--history', expand("~/.vim_fzf_history"),
      \ '--preview', preview_command_1,
      \ '--bind', 'f1:change-preview:'.preview_command_1,
      \ '--bind', 'f2:change-preview:'.preview_command_2,
      \ '--bind', 'f3:change-preview:'.preview_command_3,
      \ '--bind', 'f4:change-preview:'.preview_command_4,
      \ '--bind', 'f5:change-preview:'.preview_command_5,
      \ '--bind', 'f6:change-preview:'.preview_command_6,
      \ '--print-query',
      \ '--ansi',
      \ '--phony',
      \ '--read0',
      \ '--expect=ctrl-r,ctrl-e,ctrl-b,ctrl-n,ctrl-a',
      \ '--multi',
      \ '--bind','tab:toggle+up',
      \ '--bind','shift-tab:toggle+down',
      \ '--query', a:query,
      \ '--delimiter', '•',
      \ '--bind', 'ctrl-/:change-preview-window(hidden|right,90%|)',
      \ '--bind', 'change:reload:'.reload_command,
      \ '--bind', 'ctrl-f:unbind(change,ctrl-f)+change-prompt(pickaxe/fzf> )+enable-search+rebind(ctrl-r,ctrl-l)',
      \ '--header', s:magenta('^-R', 'Special')." Rg ╱ ".s:magenta('^-F', 'Special')." fzf ╱ ".s:magenta('M-R', 'Special')
        \ ." rg/fzf ╱ ".s:prettify_help("^", "i", "files")
        \ ."\n".join(a:authors, ' '),
      \ '--prompt', regex.branches.' '.notbranches.' '.G.regex.' pickaxe> ',
      \ ],
   \ 'sink*': function('s:gitpickaxe_sink', [a:branches, a:notbranches, a:authors, a:G, a:regex, a:fullscreen]),
   \ 'source': initial_command
  \ }
  call fzf#run(fzf#wrap(spec, 0))
endfunction

function! s:gitpickaxe_sink(branches, notbranches, authors, G, regex, fullscreen, lines)
  let query = a:lines[0]
  let key = a:lines[1]

  if key == 'ctrl-e'
    let G = a:G ? 0 : 1
    call GitPickaxeFzf(query, a:branches, a:notbranches, G, a:regex, a:fullscreen)
  elseif key == 'ctrl-b'
    call FzfBranchSelect('GitPickaxeFzfBranch', query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:fullscreen)
  elseif key == 'ctrl-n'
    call FzfBranchSelect('GitPickaxeFzfNotBranch', query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:fullscreen)
  elseif key == 'ctrl-a'
    call FzfAuthorSelect('GitPickaxeFzfAuthor', query, a:branches, a:notbranches, a:authors, a:G, a:regex, a:fullscreen)
  else
    execute s:warn(a:lines)
  endif
endfunction

function! FzfBranchSelect(func, ...)
  let preview_command_1 = 'echo git log {1} ; echo {2} -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_2 = 'echo git log ..{1} \(what they have, we dont\); echo ..{2} -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_3 = 'echo git log {1}.. \(what we have, they dont\); echo {2}.. -- | xargs git log --format="%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'
  let preview_command_4 = 'echo git log {1}... \(what we both have, common ancester not\); echo {2}... -- | xargs git log --format="%m%C(auto)%h •%d %s %C(green)%cr %C(blue)(%aN <%aE>) %C(reset)"'

  let spec = {
    \ 'source':  "git branch -a --sort='-authordate' --color --format='%(HEAD) %(if:equals=refs/remotes)%(refname:rstrip=-2)%(then)%(color:cyan)%(align:0)%(refname:lstrip=2)%(end)%(else)%(if)%(HEAD)%(then)%(color:reverse yellow)%(align:0)%(refname:lstrip=-1)%(end)%(else)%(color:yellow)%(align:0)%(refname:lstrip=-1)%(end)%(end)%(end)%(color:reset) %(color:red): %(if)%(symref)%(then)%(color:yellow)%(objectname:short)%(color:reset) %(color:red):%(color:reset) %(color:green)-> %(symref:lstrip=-2)%(else)%(color:yellow)%(objectname:short)%(color:reset) %(if)%(upstream)%(then)%(color:red): %(color:reset)%(color:green)[%(upstream:short)%(if)%(upstream:track)%(then):%(color:blue)%(upstream:track,nobracket)%(symref:lstrip=-2)%(color:green)%(end)]%(color:reset) %(end)%(color:red):%(color:reset) %(contents:subject)%(end) • %(color:blue)(%(authordate:short))'",
    \ 'sink*':   function(a:func, a:000),
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
  call fzf#run(fzf#wrap(spec, 0))
endfunction

function! FzfAuthorSelect(func, ...)
  let spec = {
    \ 'source':  "git log --format='%aN <%aE>' | awk '!x[$0]++'",
    \ 'sink*':   function(a:func, a:000),
    \ 'options':
      \ [
        \ '--multi',
        \ '--bind','tab:toggle+up',
        \ '--bind','shift-tab:toggle+down',
      \ ],
    \ 'placeholder': ''
  \ }
  call fzf#run(fzf#wrap(spec, 0))
endfunction

function! GitPickaxeFzfAuthor(query, branch, notbranches, authors, G, regex, fullscreen, ...)
  call GitPickaxeFzf(a:query, a:branch, a:notbranches, a:000[0], a:G, a:regex, a:fullscreen)
endfunction

function! GitPickaxeFzfBranch(query, branches, notbranches, authors, G, regex, fullscreen, ...)
  "let branches = join(map(a:000, 'trim(v:val.split(':')[0], " *")'), ' ')
  let branches = map(a:000[0], 'trim(split(v:val, ":")[0], " *")')
  call GitPickaxeFzf(a:query, branches, a:notbranches, a:authors, a:G, a:regex, a:fullscreen)
endfunction

function! GitPickaxeFzfNotBranch(query, branches, notbranches, authors, G, regex, fullscreen, ...)
  call GitPickaxeFzf(a:query, a:branches, a:000[0], a:authors, a:G, a:regex, a:authors, a:fullscreen)
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

function! s:prettify_help(control, char, text)
  return s:magenta(a:control.'-'.toupper(a:char), 'Special') . " " . a:text[0] . substitute(a:text[1:], '\<'.a:char, "\e[3m".a:char."\e[m", "")
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
