# siefe.vim
## Vim search plugin
[fzf.vim](https://github.com/junegunn/fzf.vim) on steroids.

## Ripgrep

Search with ripgrep.
### Commands

| Command           | default map | List                                                                                  |
| ---               | | ---                                                                                   |
| `SiefeRg`         | <leader>rg | rg search                                                                             |
| `SiefeRgVisual`   | <leader>rg | rg search of the visual selection                                                     |
| `SiefeRgWord`     | <leader>rw | rg search of the word under the cursor                                                |
| `SiefeRgWORD`     | <leader>rW | rg search of the WORD under the cursor                                                |
| `SiefeRgLine`     | <leader>rl | rg search of the line under the cursor                                                |
| `SiefeFiles`      | <leader>ff | fzf search filenames                                                                     |
| `SiefeFilesVisual`      | <leader>ff | fzf search files                                                                      |
| `SiefeFilesWord`      | <leader>fw | fzf search files                                                                      |
| `SiefeFilesWORD`      | <leader>fW | fzf search files                                                                      |
| `SiefeFilesLine`      | <leader>fl | fzf search files                                                                      |
| `SiefeProjectRg`  | <leader>Rg | rg search in the current git repository                                               |
| `SiefeProjectRgVisual`   | <leader>Rg | rg search of the visual selection                                              |
| `SiefeProjectRgWord`     | <leader>Rg | rg search of the word under the cursor                                         |
| `SiefeProjectRgWORD`     | <leader>Rg | rg search of the WORD under the cursor                                         |
| `SiefeProjectRgLine`     | <leader>Rg | rg search of the line under the cursor                                         |
| `SiefeProjectFiles`    | <leader>Rg | fzf filenames
| `SiefeProjectFilesVisual`  | <leader>Rg | fzf filenames
| `SiefeProjectFilesWord`    | <leader>Rw | fzf filenames
| `SiefeProjectFilesWORD`    | <leader>RW | fzf filenames
| `SiefeProjectFilesLine`    | <leader>Rl | fzf filenames
| `SiefeBuffersRg`    | | fzf list files
| `SiefeBuffersRgWord`    | | fzf list files
| `SiefeBuffersRgWORD`    | | fzf list files

### Keys
| action | default key |                                                                                    |
| ---    |           | ---                                                                                   |
| `word` | `ctrl-w`  | Enable ripgrep's `-w` option to only show matches surrounded by word boundaries       |
| `max1` | `ctrl-a`  | Show only 1 match per file |
| `files` | `ctrl-f`  | Switch to files view
| `type` | `ctrl-t`  | select file types to search
| `type not` | `ctrl-^`  | select file types to exclude from search

### Git

## log

| Command           | List                                                                                  |
| ---               | ---                                                                                   |
| SiefeGitLog       |                                                                                       |
| SiefeGitLogWord   |                                                                                       |
| SiefeGitLogWORD   |                                                                                       |
| SiefeGitBufferLog       |                                                                                       |
| SiefeGitBufferLogWord   |                                                                                       |
| SiefeGitBufferLogWORD   |                                                                                       |
| SiefeGitLLog      |                                                                                       |

### History
