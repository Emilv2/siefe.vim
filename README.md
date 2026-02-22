# siefe.vim
## Neovim search plugin — fzf-lua on steroids

siefe.vim is a Neovim plugin that wraps [fzf-lua](https://github.com/ibhagwan/fzf-lua) with a rich set of
search commands, live-reload ripgrep integration, git log/status/stash/branch pickers, history with saved
cursor positions, and much more.

> **Neovim only.** The plugin is written in Lua and requires Neovim ≥ 0.8.

## Dependencies

| Dependency | Required | Notes |
| --- | --- | --- |
| [Emilv2/fzf-lua](https://github.com/Emilv2/fzf-lua) | ✓ | Neovim fzf integration |
| [fzf](https://github.com/junegunn/fzf) | ✓ | fuzzy finder binary |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | ✓ | `rg` for search commands |
| [fd](https://github.com/sharkdp/fd) | recommended | fast file finder for dir-select |
| [bat](https://github.com/sharkdp/bat) | recommended | syntax-highlighted previews |
| [delta](https://github.com/dandavison/delta) | optional | coloured git diff preview |

## Installation

```lua
-- lazy.nvim
{
  "Emilv2/siefe.vim",
  dependencies = { "Emilv2/fzf-lua" },
  build = "make build",   -- compiles Rust helper binaries into bin/
  config = function()
    require("siefe").setup({
      -- All options are optional; shown here with their defaults.
      -- loclist = false,          -- use location list instead of quickfix
      -- rg_default_hidden = false,
      -- rg_default_case_sensitive = 1,  -- 1=smart, 2=sensitive, 3=insensitive
      -- bat_options = "--style=numbers,changes",
    })
  end,
}
```

## Rust helper binaries

`make build` compiles four small Rust binaries and copies them into `bin/`:

| Binary | Purpose |
| --- | --- |
| `rg2fzf` | Translates `rg --null` output (`file\0line:col:text\n`) to NUL-terminated records for `fzf --read0`, preserving correct field boundaries without `fs_stat` |
| `shada2fzf` | Parses Neovim's shada file to extract MRU file positions (line + col) for the history picker |
| `diffgrep` | Filters a unified diff to only hunks whose `+`/`-` lines match a pattern (replaces the broken Perl version) |
| `pickaxe-diff` | External diff driver for git pickaxe (`-S`/`-G`) that colours output and calls `diffgrep` |

## Commands

### Ripgrep

| Command | Default map | Description |
| --- | --- | --- |
| `SiefeRg [PATTERN]` | `<leader>rg` | Live rg search from buffer directory |
| `SiefeRgVisual` | `<leader>rv` | rg search of visual selection |
| `SiefeRgWord` | `<leader>rw` | rg search of word under cursor |
| `SiefeRgWORD` | `<leader>rW` | rg search of WORD under cursor |
| `SiefeRgLine` | `<leader>rl` | rg search of current line |
| `SiefeRgConflict` | `<leader>rc` | rg search for merge conflict markers |
| `SiefeProjectRg [PATTERN]` | `<leader>Rg` | rg from git root |
| `SiefeProjectRgVisual` | `<leader>Rv` | project rg of visual selection |
| `SiefeProjectRgWord` | `<leader>Rw` | project rg of word under cursor |
| `SiefeProjectRgWORD` | `<leader>RW` | project rg of WORD under cursor |
| `SiefeProjectRgLine` | `<leader>Rl` | project rg of current line |
| `SiefeProjectRgConflict` | `<leader>Rc` | project conflict markers |
| `SiefeBuffersRg` | | rg limited to open buffers |
| `SiefeBuffersRgWord` | | buffer rg of word under cursor |
| `SiefeBuffersRgWORD` | | buffer rg of WORD under cursor |

**Key bindings inside the rg picker** (press `F9` for full help):

| Key | Action |
| --- | --- |
| `ctrl-w` | Toggle `-w` (whole-word matching) — disabled in files mode |
| `ctrl-s` | Cycle case: smart / sensitive / insensitive |
| `ctrl-f` | Switch to files mode (`rg --files`) |
| `ctrl-r` | Toggle fzf-mode (fuzzy match on rg lines) |
| `alt-f` | rg+fzf combined mode |
| `ctrl-t` | Select file types to include |
| `ctrl-^` | Select file types to exclude |
| `ctrl-d` | Change search directory |
| `ctrl-b` | Limit search to open buffers |
| `ctrl-h` | Limit search to history / project history |
| `ctrl-a` | Show only first match per file (`--max-count=1`) |
| `ctrl-e` | `--maxdepth=1` (no recursion) |
| `ctrl-u` | Toggle `--no-ignore` |
| `alt-.` | Toggle `--hidden` |
| `ctrl-x` | Toggle `--fixed-strings` |
| `alt-z` | Toggle `--search-zip` |
| `alt-t` | Toggle `--text` (binary as text) |
| `ctrl-y` | Yank selected line to `"` register |
| `ctrl-]` | Open in split |
| `ctrl-\` | Open in vsplit |
| `alt-enter` | Open in new tab |

### Files

| Command | Default map |
| --- | --- |
| `SiefeFiles` | `<leader>ff` |
| `SiefeFilesVisual` | `<leader>fv` |
| `SiefeFilesWord` | `<leader>fw` |
| `SiefeFilesWORD` | `<leader>fW` |
| `SiefeFilesLine` | `<leader>fl` |
| `SiefeProjectFiles` | `<leader>Ff` |
| `SiefeProjectFilesVisual` | `<leader>Fv` |
| `SiefeProjectFilesWord` | `<leader>Fw` |
| `SiefeProjectFilesWORD` | `<leader>FW` |
| `SiefeProjectFilesLine` | `<leader>Fl` |

### Git

| Command | Default map | Description |
| --- | --- | --- |
| `SiefeGitLog` | `<leader>gl` | git log (pickaxe -S search) |
| `SiefeGitLogWord` | `<leader>gw` | git log for word under cursor |
| `SiefeGitLogWORD` | `<leader>gW` | git log for WORD under cursor |
| `SiefeGitLogVisual` | `<leader>gv` | git log for visual selection |
| `SiefeGitBufferLog` | `<leader>gbl` | git log for current file |
| `SiefeGitBufferLogWord` | `<leader>gbw` | buffer log for word |
| `SiefeGitBufferLogWORD` | `<leader>gbW` | buffer log for WORD |
| `SiefeGitBufferLogVisual` | `<leader>gbv` | buffer log for selection |
| `SiefeGitLLog` | `<leader>gL` | git log for current line range |
| `SiefeGitStatus` | `<leader>gs` | git status picker |
| `SiefeToggleGitStatus` | `<leader>gS` | toggle persistent git status window |
| `SiefeGitBranch` | `<leader>gb` | git branch picker |
| `SiefeGitStash` | `<leader>gx` | git stash picker |

### History / Buffers / Other

| Command | Default map | Description |
| --- | --- | --- |
| `SiefeHistory` | `<leader>fh` | MRU file history (with line + col from shada) |
| `SiefeProjectHistory` | `<leader>Fh` | MRU history limited to git repo |
| `SiefeBuffers` | `<leader>fb` | open buffers |
| `SiefeMarks` | `<leader>m` | marks |
| `SiefeJumps` | `<leader>j` | jump list |
| `SiefeRegisters` | `<leader>'" ` | registers |
| `SiefeMaps` | `<leader>?` | key mappings |

## Configuration

All options are passed to `require("siefe").setup({})`. None are required.

```lua
require("siefe").setup({
  -- Use location list instead of quickfix for multi-select
  loclist = false,

  -- bat syntax highlighting options
  bat_options = "--style=numbers,changes",

  -- delta diff viewer options
  delta_options = "--keep-plus-minus-markers",

  -- Default rg toggle states
  rg_default_hidden = false,
  rg_default_no_ignore = 0,          -- 0=off, 1=--no-ignore, 2=--no-ignore-vcs
  rg_default_case_sensitive = 1,     -- 1=smart, 2=sensitive, 3=insensitive
  rg_default_fixed_strings = false,
  rg_default_word = false,
  rg_default_max_1 = false,
  rg_default_search_zip = false,
  rg_default_text = false,
  rg_default_depth1 = false,

  -- Key overrides (any fzf key string is accepted)
  rg_word_key = "ctrl-w",
  rg_case_key = "ctrl-s",
  rg_files_key = "ctrl-f",
  -- ... see lua/siefe/config.lua for the full list
})
```

## Development

```sh
# Build Rust binaries
make build

# Run all tests (Rust + Lua unit)
make test

# Run integration tests (requires make build first)
make test-integration

# Lint
make lint        # runs luacheck + stylua --check + cargo clippy + cargo fmt --check

# Format
make fmt         # runs stylua + cargo fmt

# Coverage
make coverage    # Rust llvm-cov summary + Lua luacov report
make coverage-rust   # HTML report in coverage/rust/index.html
make coverage-lua    # luacov.report.out
```

