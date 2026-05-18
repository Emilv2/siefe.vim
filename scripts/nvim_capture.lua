-- Capture nvim's rendered TUI as plain text via screenstring().
-- Call via: nvim --server "$SOCKET" --remote-expr 'luaeval("dofile(\"<path>\")")'

local lines = {}
for row = 1, vim.o.lines do
  local line_chars = {}
  for col = 1, vim.o.columns do
    local s = vim.fn.screenstring(row, col)
    line_chars[col] = (s == "" or s == "\0") and " " or s
  end
  lines[row] = table.concat(line_chars):gsub("%s+$", "")
end
return table.concat(lines, "\n")
