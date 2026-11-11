local M = {}
---@type Orbit.MasonOptions?
local accepted

---@class Orbit.MasonHangar # Hangar tool manager, its state and the tool registry.
---@field enabled? boolean @default(true) @restart(true) # Include Hangar during Lazy startup.
---@field command? string @default("Hangar") @minLength(1) @restart(true) # Command for the Hangar UI.
---@field key? string @default("<leader>us") @minLength(1) @restart(true) # Mapping for the Hangar UI.
---@field state_file? string @default("") @restart(true) # Optional state JSON path override.
---@field border? 'rounded'|'single'|'double'|'solid'|'shadow'|'none' @default("rounded") @restart(true) # Hangar window border.

---@class Orbit.MasonOptions # Lazy Mason package manager and the Hangar tool manager.
---@field enabled? boolean @default(true) @restart(true) # Enable Mason commands.
---@field path_mode? 'skip'|'prepend'|'append' @default("prepend") @restart(true) # Where Mason's bin directory goes on PATH at startup.
---@field max_concurrent_installers? integer @default(10) @minimum(1) @maximum(64) @restart(true) # Concurrent package installation limit.
---@field registry? string @default("github:mason-org/mason-registry") @minLength(1) @restart(true) # Primary Mason registry.
---@field pending_icon? string @default(" ") @restart(true) # Pending package icon.
---@field installed_icon? string @default(" ") @restart(true) # Installed package icon.
---@field uninstalled_icon? string @default(" ") @restart(true) # Uninstalled package icon.
---@field hangar? Orbit.MasonHangar @default({}) @restart(true) # Hangar tool manager, independent of Mason enablement.

---@return Orbit.MasonOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.MasonOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.MasonOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("mason", opts)
end

---Add Mason's bin directory to PATH once, so servers resolve before Mason loads.
---@param mode 'skip'|'prepend'|'append'
function M.add_bin_to_path(mode)
  if mode == "skip" then
    return
  end
  local bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
  local separator = vim.fn.has("win32") == 1 and ";" or ":"
  local path = vim.env.PATH or ""
  for entry in vim.gsplit(path, separator, { plain = true }) do
    if vim.fs.normalize(entry) == vim.fs.normalize(bin) then
      return
    end
  end
  vim.env.PATH = mode == "prepend" and (bin .. separator .. path) or (path .. separator .. bin)
end

---@param opts Orbit.MasonHangar
---@return LazySpec
local function hangar_spec(opts)
  return {
    { "MunifTanjim/nui.nvim", lazy = true },
    {
      "Orbit-Lua/hangar.nvim",
      version = "^0.5",
      -- Hangar gates tool owners that load later, so it loads at startup.
      lazy = false,
      priority = 900,
      dependencies = { "MunifTanjim/nui.nvim" },
      config = function()
        require("orbit.modules.mason.hangar").setup(opts)
      end,
    },
  }
end

---@param c Orbit.MasonOptions
---@return LazySpec
local function mason_spec(c)
  return {
    "williamboman/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    -- Mason loads only on its commands; Orbit owns PATH at startup instead.
    init = function()
      M.add_bin_to_path(c.path_mode)
    end,
    ---@type MasonSettings
    opts = {
      PATH = "skip",
      ui = {
        icons = {
          package_pending = c.pending_icon,
          package_installed = c.installed_icon,
          package_uninstalled = c.uninstalled_icon,
        },
      },
      max_concurrent_installers = c.max_concurrent_installers,
      registries = { c.registry },
    },
  }
end

---@return LazySpec
function M.spec()
  if not accepted then
    return {}
  end
  local c = vim.deepcopy(accepted)
  ---@type LazySpec
  local result = {}
  if c.enabled then
    result[#result + 1] = mason_spec(c)
  end
  if c.hangar.enabled then
    vim.list_extend(result, hangar_spec(c.hangar))
  end
  return result
end

return M
