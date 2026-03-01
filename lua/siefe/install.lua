-- lua/siefe/install.lua
-- Ensures siefe's Rust binaries (rg2fzf, shada2fzf, diffgrep, pickaxe-diff)
-- are present in the plugin's bin/ directory.
--
-- Called from siefe.setup() and can also be invoked manually:
--   :lua require('siefe.install').ensure_binaries()
--   :lua require('siefe.install').ensure_binaries({ force = true })
local M = {}

local BINARIES = { "rg2fzf", "shada2fzf", "diffgrep", "pickaxe-diff" }

-- Return the absolute path to the plugin root (three directories above this file:
-- lua/siefe/install.lua → lua/siefe → lua → <plugin root>).
local function plugin_dir()
  local src = debug.getinfo(1, "S").source:sub(2) -- strip leading '@'
  return vim.fn.fnamemodify(src, ":h:h:h")
end

-- Check whether all four binaries are executable in bin/.
local function all_present(bin_dir)
  for _, b in ipairs(BINARIES) do
    if vim.fn.executable(bin_dir .. "/" .. b) ~= 1 then
      return false
    end
  end
  return true
end

-- Extract the git hash embedded by build.rs from a binary's --version output.
-- Returns nil when the binary doesn't support --version or has no hash.
local function binary_git_hash(bin_dir)
  local out = vim.fn.system({ bin_dir .. "/rg2fzf", "--version" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return out:match("%(git:([a-f0-9]+)%)")
end

-- Return the short git hash of the plugin's current HEAD, or nil.
local function plugin_git_hash(dir)
  local out = vim.fn.system({ "git", "-C", dir, "rev-parse", "--short", "HEAD" })
  if vim.v.shell_error == 0 then
    return vim.trim(out)
  end
  return nil
end

--- Ensure binaries are present, building or downloading as needed.
---@param opts? { force?: boolean, silent?: boolean }
---   force  — re-install even if all binaries are already there (default: false)
---   silent — suppress "already present" notification (default: false)
function M.ensure_binaries(opts)
  opts = opts or {}
  local dir = plugin_dir()
  local bin_dir = dir .. "/bin"
  local setup_script = dir .. "/scripts/setup.sh"

  if all_present(bin_dir) and not opts.force then
    -- Cross-check embedded git hash against the plugin's current HEAD.
    local bin_hash = binary_git_hash(bin_dir)
    local plug_hash = plugin_git_hash(dir)
    if bin_hash and plug_hash and bin_hash ~= plug_hash then
      vim.notify(
        "siefe: binaries are outdated (binary: "
          .. bin_hash
          .. ", plugin: "
          .. plug_hash
          .. "). Run :SiefeInstall! to update.",
        vim.log.levels.WARN
      )
      return
    end
    if not opts.silent then
      vim.notify("siefe: all binaries present in " .. bin_dir, vim.log.levels.DEBUG)
    end
    return
  end

  if vim.fn.executable(setup_script) ~= 1 then
    vim.notify(
      "siefe: setup script not found at " .. setup_script .. "\n" .. "Run `make build` from the plugin directory to build from source.",
      vim.log.levels.WARN
    )
    return
  end

  vim.notify("siefe: installing binaries (this may take a moment)…", vim.log.levels.INFO)

  local env = vim.deepcopy(vim.fn.environ())
  if opts.force then
    env["SIEFE_FORCE"] = "1"
  end

  local lines = {}
  local job = vim.fn.jobstart({ setup_script }, {
    env = env,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(lines, line)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(lines, line)
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local msg = table.concat(lines, "\n")
        if code == 0 then
          vim.notify("siefe: " .. (msg ~= "" and msg or "binaries installed successfully"), vim.log.levels.INFO)
        else
          vim.notify(
            "siefe: binary installation failed (exit " .. code .. ")\n" .. msg,
            vim.log.levels.ERROR
          )
        end
      end)
    end,
  })

  if job <= 0 then
    vim.notify("siefe: failed to start setup script", vim.log.levels.ERROR)
  end
end

return M
