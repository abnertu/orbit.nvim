-- Configure Hangar before event-loaded consumers read its tool state.
local M = {}
local active = false

local function settings_for(name)
  local module = require("orbit.modules." .. name)
  local specs = module.spec()
  if #specs == 0 then return {} end
  return vim.deepcopy(specs[1].opts.formatters_by_ft or
    specs[1].opts.linters_by_ft or {})
end

---@param opts Orbit.HangarOptions
function M.options(opts)
  local registry = require("orbit.modules.hangar.registry")
  return {
    registry = registry,
    defaults = function()
      return {
        formatter = vim.deepcopy(registry.formatter_defaults),
        linter = vim.deepcopy(registry.linter_defaults),
      }
    end,
    state_path = function()
      if opts.state_file ~= "" then return opts.state_file end
      return vim.g.hangar_state_path or
        vim.fs.joinpath(vim.fn.stdpath("data"), "hangar.json")
    end,
    border = opts.border,
    adapters = {
      dap = {
        runtime = function()
          return require("orbit.modules.dap.runtime")
        end,
        options = function()
          local current = require("orbit").get_config()
          return require("orbit.modules.dap.definitions")
            .build(current.modules.dap)
        end,
      },
      activation = {
        formatter = function() return settings_for("formatter") end,
        linter = function() return settings_for("linter") end,
      },
    },
  }
end

---@param opts Orbit.HangarOptions
function M.setup(opts)
  if active then return end
  assert(opts.command:match("^[A-Z][A-Za-z0-9]*$"),
    "Hangar command must start with an uppercase letter")
  assert(vim.api.nvim_get_commands({})[opts.command] == nil,
    "refusing to replace an existing user command: " .. opts.command)
  local hangar = require("hangar")
  hangar.setup(M.options(opts))
  vim.api.nvim_create_user_command(opts.command, function()
    hangar.open()
  end, { desc = "Open Hangar tool manager" })
  vim.keymap.set("n", opts.key, "<cmd>" .. opts.command .. "<cr>",
    { desc = "Hangar", silent = true })
  active = true
end

return M
