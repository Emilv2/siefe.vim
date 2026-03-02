# siefe.vim
## Neovim search plugin — fzf-lua on steroids

siefe.vim is a Neovim plugin that wraps [fzf-lua](https://github.com/Emilv2/fzf-lua) with a rich set of
search commands, live-reload ripgrep integration, git log/status/stash/branch pickers, history with saved
cursor positions (from shada), and much more.

> **Neovim only.** The plugin is written in Lua and requires Neovim ≥ 0.9.

## Dependencies

| Dependency | Required | Notes |
| --- | --- | --- |
| [Emilv2/fzf-lua](https://github.com/Emilv2/fzf-lua) | ✓ | Neovim fzf integration (fork) |
| [fzf](https://github.com/junegunn/fzf) | ✓ | fuzzy finder binary |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | ✓ | `rg` for search/files commands |
| [fd](https://github.com/sharkdp/fd) | recommended | fast file finder for dir-select |
| [delta](https://github.com/dandavison/delta) | optional | coloured git diff previews |
| `cargo` / Rust toolchain | build-time | to compile helper binaries from source |

> File previews use the **Neovim built-in previewer** (Treesitter / LSP syntax, no `bat` required).
> Git diff previews use `git show`/`git diff` output, optionally styled with `delta`.

## Installation

```lua
-- lazy.nvim
{
  "Emilv2/siefe.vim",
  dependencies = { "Emilv2/fzf-lua" },
  -- Builds Rust helper binaries. If cargo is available, compiles from source;
  -- otherwise downloads a pre-built tarball from the latest GitHub release.
  build = "bash scripts/setup.sh",
  config = function()
    require("siefe").setup({
      -- All options are optional. See Configuration section below.
    })
  end,
}
```

### Binary installation

On first `setup()`, siefe checks that its four Rust helper binaries are present in `bin/`.
If they are missing or outdated it runs `scripts/setup.sh` automatically (async, no blocking).

You can also invoke it manually:

```vim
:SiefeInstall    " install if missing
:SiefeInstall!   " force reinstall (e.g. after updating the plugin)
```

The setup script prefers `cargo build --release` when `cargo` is available and falls back to
downloading the pre-built tarball for your platform from the latest GitHub release.

## Rust helper binaries

`scripts/setup.sh` (or `make build`) compiles four small Rust binaries and copies them into `bin/`.
Each binary embeds the git commit hash of the plugin at build time (`--version` shows it).
`setup()` warns if the installed binaries are older than the plugin's current HEAD.

| Binary | Purpose |
| --- | --- |
| `rg2fzf` | Translates `rg --null` output (`file\0line:col:text\n`) to NUL-terminated records for `fzf --read0` — unambiguous field boundaries, no `fs_stat` calls |
| `shada2fzf` | Parses Neovim's shada file to extract MRU file positions (line + col) for the history picker |
| `diffgrep` | Filters a unified diff to only hunks whose `+`/`-` lines match a pattern; supports `-S` (literal pickaxe) and `-G` (regex pickaxe) flags matching git's exact semantics |
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

**Key bindings inside the rg picker** (press `F1` for fzf-lua's built-in help):

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
| `SiefeGitLog` | `<leader>gl` | git log (pickaxe `-S` literal search) |
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

**Key bindings inside the git log picker:**

| Key | Action |
| --- | --- |
| `ctrl-s` | Toggle between `-S` (literal count diff) and `-G` (regex) pickaxe mode |
| `ctrl-x` | Toggle regex mode for `-G` pattern matching |
| `ctrl-i` / `alt-i` | Toggle case-insensitive search |
| `ctrl-o` | Toggle `--follow` (follow file renames) |
| `ctrl-b` | Filter by branch |
| `ctrl-^` | Exclude branch |
| `ctrl-a` | Filter by author |
| `ctrl-t` | Filter by file type |
| `ctrl-v` | Open commit in vertical diff split |
| `F7` | **Cycle preview mode**: full diff → matching files → matching hunks (via `diffgrep`) → plain diff |
| `F1` | fzf-lua built-in help |

### History / Buffers / Other

| Command | Default map | Description |
| --- | --- | --- |
| `SiefeHistory` | `<leader>fh` | MRU file history (with line + col from shada) |
| `SiefeProjectHistory` | `<leader>Fh` | MRU history limited to git repo |
| `SiefeBuffers` | `<leader>fb` | open buffers (terminals sorted last) |
| `SiefeWindows` | `<leader>W` | all windows across all tabs |
| `SiefeMarks` | `<leader>m` | marks |
| `SiefeJumps` | `<leader>j` | jump list |
| `SiefeRegisters` | `<leader>'"` | registers |
| `SiefeMaps` | `<leader>?` | key mappings |
| `SiefeInstall` | — | install/update Rust helper binaries |

## Configuration

All options are passed to `require("siefe").setup({})`. Calling `setup()` is optional —
all defaults apply automatically. None of the options are required.

```lua
require("siefe").setup({
  -- Use location list instead of quickfix for multi-select
  loclist = false,

  -- delta diff viewer options (used in git log/stash/branch previews)
  delta_options = "--keep-plus-minus-markers",

  -- Default rg toggle states (all false / 1=smart-case by default)
  rg_default_hidden = false,
  rg_default_no_ignore = 0,          -- 0=off, 1=--no-ignore, 2=--no-ignore-vcs
  rg_default_case_sensitive = 1,     -- 1=smart, 2=sensitive, 3=insensitive
  rg_default_fixed_strings = false,
  rg_default_word = false,
  rg_default_max_1 = false,
  rg_default_search_zip = false,
  rg_default_text = false,
  rg_default_depth1 = false,

  -- Key overrides — any fzf key string is accepted (e.g. "alt-w", "ctrl-f", "f5")
  rg_word_key = "ctrl-w",   -- toggle word-boundary matching (disabled in files mode)
  rg_case_key = "ctrl-s",   -- cycle case modes
  rg_files_key = "ctrl-f",  -- switch to files mode
  rg_dir_key = "ctrl-d",    -- change search directory
  -- ... see lua/siefe/config.lua for the full list of ~60 configurable keys

  -- Disable all default <leader> mappings (use your own <Plug> mappings instead)
  map_keys = false,
})
```

### Disabling default key mappings

Default mappings (e.g. `<leader>rg`, `<leader>gl`) are created automatically.
Pass `map_keys = false` to `setup()` to disable them:

```lua
require('siefe').setup({ map_keys = false })
```

Then define your own mappings with `<Plug>` targets:

```lua
vim.keymap.set("n", "<leader>s", "<Plug>SiefeRg")
vim.keymap.set("n", "<leader>G", "<Plug>SiefeGitLog")
```

## Development

```sh
# Install / update Rust binaries (cargo preferred, falls back to GitHub release download)
bash scripts/setup.sh
# or, to always build from source:
make build

# Run all tests (Rust unit + Lua unit)
make test

# Run integration tests (requires `make build` first, needs rg + git in PATH)
make test-integration

# Lint (luacheck + stylua --check + cargo clippy + cargo fmt --check)
make lint

# Format (stylua + cargo fmt)
make fmt

# Coverage
make coverage-rust-summary  # Rust line coverage summary to stdout
make coverage-rust           # HTML report at coverage/rust/index.html
make coverage-lua            # Lua line coverage report at luacov.report.out
```

