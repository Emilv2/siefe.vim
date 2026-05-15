# siefe.vim — agent instructions

## Run Neovim non-headlessly

This project provides scripts to start a Neovim instance with a visible TUI
that can be controlled via RPC.  The nvim process gets a real pty (so the TUI
renders), and opens a Unix socket for remote commands.

### Start nvim

```bash
python3 scripts/nvim_daemon.py [file] &
DAEMON_PID=$!
sleep 0.3
```

nvim stays alive only while the daemon runs.  If you need to do multiple things,
keep the daemon alive for the entire bash call (background it and kill it at the
end).  On the next turn you must restart it.

### Control nvim

```bash
# Send keys (like typing in the editor)
nvim --server /tmp/nvim-server --remote-send ":e somefile.lua<CR>"
nvim --server /tmp/nvim-server --remote-send "ggdG"

# Evaluate Vimscript expression
nvim --server /tmp/nvim-server --remote-expr "getcwd()"
nvim --server /tmp/nvim-server --remote-expr "line('$')"

# Evaluate Lua expression (wrap in luaeval)
nvim --server /tmp/nvim-server --remote-expr 'luaeval("vim.bo.filetype")'
```

### Capture rendered TUI (text)

```bash
nvim --server /tmp/nvim-server --remote-expr \
  "luaeval(\"dofile('scripts/nvim_capture.lua')\")"
```

Returns the full visible screen as text — line numbers, sign column, folds,
statusline, command line, everything that is *rendered* on screen.

### Read buffer content (raw, programmatic)

```bash
# All lines from buffer 0 (current)
nvim --server /tmp/nvim-server --remote-expr \
  "luaeval(\"vim.api.nvim_buf_get_lines(0, 0, -1, false)\")"

# Cursor position
nvim --server /tmp/nvim-server --remote-expr \
  'luaeval("vim.api.nvim_win_get_cursor(0)")'
```

### Full example (single bash call)

```bash
python3 scripts/nvim_daemon.py README.md &
DAEMON_PID=$!
sleep 0.3

nvim --server /tmp/nvim-server --remote-send ":set number<CR>"
sleep 0.1
nvim --server /tmp/nvim-server --remote-expr \
  "luaeval(\"dofile('scripts/nvim_capture.lua')\")"

kill $DAEMON_PID 2>/dev/null
wait 2>/dev/null
```

### Important notes

- nvim has **no user config** loaded (bare neovim).  `screenstring()` captures
  whatever is rendered; if you need syntax highlighting, treesitter, etc., source
  the relevant config first.
- The socket path is hard-coded to `/tmp/nvim-server`.
- `screenstring()` returns **rendered** characters — tabs are expanded to spaces,
  folds show as their fold text, wrapped lines reflect the actual window width.
