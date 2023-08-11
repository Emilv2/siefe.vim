# siefe.vim
## Vim search plugin
Based on [fzf.vim](https://github.com/junegunn/fzf.vim), but with some more options.

## Ripgrep

Search with ripgrep.
### Commands

| Command           | List                                                                                  |
| ---               | ---                                                                                   |
| `SiefeRg`         | rg search                                                                             |
| `SiefeRgVisual`   | rg search of the visual selection                                                     |
| `SiefeRgWord`     | rg search of the word under the cursor                                                |
| `SiefeRgWORD`     | rg search of the WORD under the cursor                                                |
| `SiefeRgLine`     | rg search of the line under the cursor                                                |
| `SiefeFiles`      | fzf search filenames                                                                     |
| `SiefeFilesVisual`      | fzf search files                                                                      |
| `SiefeFilesWord`      | fzf search files                                                                      |
| `SiefeFilesWORD`      | fzf search files                                                                      |
| `SiefeFilesLine`      | fzf search files                                                                      |
| `SiefeProjectRg`  | rg search in the current git repository                                               |
| `SiefeProjectRgVisual`   | rg search of the visual selection                                              |
| `SiefeProjectRgWord`     | rg search of the word under the cursor                                         |
| `SiefeProjectRgWORD`     | rg search of the WORD under the cursor                                         |
| `SiefeProjectRgLine`     | rg search of the line under the cursor                                         |
| `SiefeProjectFiles`    | fzf filenames
| `SiefeProjectFilesVisual`    | fzf filenames
| `SiefeProjectFilesWord`    | fzf filenames
| `SiefeProjectFilesWORD`    | fzf filenames
| `SiefeProjectFilesLine`    | fzf filenames
| `SiefeBuffersRg`    | fzf list files
| `SiefeBuffersRgWord`    | fzf list files
| `SiefeBuffersRgWORD`    | fzf list files

### Keys
| action (default key) |                                                                                    |
| ---               | ---                                                                                   |
| `word` (`ctrl-w`  | Enable ripgrep's `-w` option to only show matches surrounded by word boundaries       |

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
