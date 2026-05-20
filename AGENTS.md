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
SOCKET=$(cat /tmp/nvim-socket-path)
```

The daemon writes the socket path to `/tmp/nvim-socket-path` — capture it
before running remote commands.  The daemon automatically finds a free socket
path (tries `/tmp/nvim-server`, then `-1`, `-2`…) and cleans up on exit.

nvim stays alive only while the daemon runs.  If you need to do multiple things,
keep the daemon alive for the entire bash call (background it and kill it at the
end).  On the next turn you must restart it.

### Load siefe.vim plugin

When testing the plugin itself, create a minimal init file and pass `setup()` via
`-c` (NOT in the init file — calling `vim.fn.system()` during init blocks the
RPC listener):

```bash
cat > /tmp/siefe_init.lua <<'EOF'
vim.opt.runtimepath:prepend("/path/to/siefe.vim")
vim.opt.runtimepath:prepend("/path/to/fzf-lua")
EOF

python3 scripts/nvim_daemon.py \
  -u /tmp/siefe_init.lua \
  -c 'lua require("siefe").setup({})' \
  [file] &
DAEMON_PID=$!
sleep 0.5
SOCKET=$(cat /tmp/nvim-socket-path)
```

### Control nvim

```bash
# Send keys (like typing in the editor)
nvim --server "$SOCKET" --remote-send ":e somefile.lua<CR>"
nvim --server "$SOCKET" --remote-send "ggdG"

# Evaluate Vimscript expression
nvim --server "$SOCKET" --remote-expr "getcwd()"
nvim --server "$SOCKET" --remote-expr "line('$')"

# Evaluate Lua expression (wrap in luaeval)
nvim --server "$SOCKET" --remote-expr 'luaeval("vim.bo.filetype")'
```

### Capture rendered TUI (text)

```bash
nvim --server "$SOCKET" --remote-expr \
  "luaeval(\"dofile('scripts/nvim_capture.lua')\")"
```

Returns the full visible screen as text — line numbers, sign column, folds,
statusline, command line, everything that is *rendered* on screen.

### Read buffer content (raw, programmatic)

```bash
# All lines from buffer 0 (current)
nvim --server "$SOCKET" --remote-expr \
  "luaeval(\"vim.api.nvim_buf_get_lines(0, 0, -1, false)\")"

# Cursor position
nvim --server "$SOCKET" --remote-expr \
  'luaeval("vim.api.nvim_win_get_cursor(0)")'
```

### Full example (single bash call)

```bash
python3 scripts/nvim_daemon.py README.md &
DAEMON_PID=$!
sleep 0.3
SOCKET=$(cat /tmp/nvim-socket-path)

nvim --server "$SOCKET" --remote-send ":set number<CR>"
sleep 0.1
nvim --server "$SOCKET" --remote-expr \
  "luaeval(\"dofile('scripts/nvim_capture.lua')\")"

kill $DAEMON_PID 2>/dev/null
wait 2>/dev/null
```

### Important notes

- nvim has **no user config** loaded (bare neovim).  `screenstring()` captures
  whatever is rendered; if you need syntax highlighting, treesitter, etc., source
  the relevant config first.
- The daemon automatically finds an available socket path (tries
  `/tmp/nvim-server`, then `-1`, `-2`…) and writes it to `/tmp/nvim-socket-path`.
  Both the socket and the path file are cleaned up when the daemon exits.
- `screenstring()` returns **rendered** characters — tabs are expanded to spaces,
  folds show as their fold text, wrapped lines reflect the actual window width.
