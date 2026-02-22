-- .luacheckrc — luacheck configuration for siefe.vim

-- Global environment: Neovim provides `vim`, standard I/O, and OS
globals = { "vim" }
read_globals = { "vim", "io", "os", "table", "string", "math", "pcall", "require", "ipairs", "pairs", "unpack", "type", "tostring", "tonumber", "select", "error", "assert", "setmetatable", "getmetatable", "rawget", "rawset", "next" }

-- Ignore long lines — some git command strings cannot be meaningfully shortened
max_line_length = false

-- Ignore "unused argument" warnings for fzf-lua action callbacks.
-- Action functions must accept (selected, opts) as their signature because
-- fzf-lua calls them that way, even when a particular action does not need
-- both arguments.
ignore = {
  "212", -- unused argument
  "213", -- unused loop variable (for _ patterns)
}
