-- Explicit Pyright stub regeneration with rollback of failed builds.
local M = {}
local owns_command = false

---@class Orbit.PythonToolsOptions # Python project maintenance commands.
---@field enabled? boolean @default(true) # Enable Python project maintenance commands.
---@field recreate_stub? boolean @default(true) # Register the guarded Pyright stub regeneration command.

local function list_stubs(root)
  local parent = vim.fs.joinpath(root, "typings")
  local scan = vim.uv.fs_scandir(parent)
  if not scan then return {} end
  local found = {}
  while true do
    local name, kind = vim.uv.fs_scandir_next(scan)
    if not name then break end
    if kind == "directory" and not name:match("^%.orbit%-stub%-") then
      local stat = vim.uv.fs_lstat(vim.fs.joinpath(parent, name))
      if stat and stat.type == "directory" then
        found[#found + 1] = name
      end
    end
  end
  table.sort(found)
  return found
end

local function register()
  assert(vim.api.nvim_get_commands({}).PyrightReCreateStub == nil,
    "refusing to overwrite existing user command: PyrightReCreateStub")
  vim.api.nvim_create_user_command("PyrightReCreateStub", function()
    local root = vim.fn.getcwd()
    local candidates = list_stubs(root)
    if #candidates == 0 then
      vim.notify("No existing Pyright stub directories", vim.log.levels.INFO,
        { title = "orbit.nvim Python" })
      return
    end
    vim.ui.select(candidates, { prompt = "Choose existing stub" }, function(name)
      if name == nil then return end
      require("orbit.modules.python_tools.runtime").recreate(root, name,
        function(ok, err)
          vim.notify(err or "Stub regenerated successfully",
            ok and not err and vim.log.levels.INFO or vim.log.levels.WARN,
            { title = "orbit.nvim Python" })
        end)
    end)
  end, { desc = "Regenerate a Pyright stub with failure recovery" })
  owns_command = true
end

function M.capture()
  return { owns_command = owns_command }
end

---@param snapshot table
function M.restore(snapshot)
  if owns_command then
    pcall(vim.api.nvim_del_user_command, "PyrightReCreateStub")
    owns_command = false
  end
  if snapshot.owns_command then register() end
end

---@param opts? Orbit.PythonToolsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("python_tools", opts)
  local desired = opts.enabled and opts.recreate_stub
  if not desired and owns_command then
    vim.api.nvim_del_user_command("PyrightReCreateStub")
    owns_command = false
  elseif desired and not owns_command then
    register()
  end
end

return M
