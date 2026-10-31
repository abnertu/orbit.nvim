local M = {}
local accepted

---@class Orbit.DapOptions # Debug adapters and DAP UI integrations.
---@field enabled boolean @default(true) @restart(true) # Enable debug plugins.
---@field python boolean @default(true) @restart(true) # Enable Python debugpy adapter.
---@field coreclr boolean @default(true) @restart(true) # Enable dotnet-cli debug adapter.
---@field ui boolean @default(true) @restart(true) # Enable DAP UI.
---@field python_host string @default("127.0.0.1") @minLength(1) @restart(true) # Python attach host.
---@field python_port string @default("8001") @minLength(1) @restart(true) # Python attach port.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.DapOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("dap", opts)
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled then return {} end
  local opts = vim.deepcopy(accepted)
  local specs = {
    {
      "Orbit-Lua/nvim-dap",
      keys = {
        { "<leader>dt", "<cmd>DapToggleBreakpoint<CR>", desc = "dap toggle breakpoint" },
        { "<leader>ds", "<cmd>DapNew<CR>", desc = "dap new session" },
        { "<leader>dR", "<cmd>DapToggleRepl<CR>", desc = "dap toggle repl" },
        { "<leader>dc", "<cmd>DapContinue<CR>", desc = "dap continue" },
        { "<leader>dl", "<cmd>DapShowLog<CR>", desc = "dap show log" },
        { "<leader>dn", "<cmd>DapStepOver<CR>", desc = "dap step over" },
        { "<leader>di", "<cmd>DapStepInto<CR>", desc = "dap step into" },
        { "<leader>do", "<cmd>DapStepOut<CR>", desc = "dap step out" },
      },
      config = function()
        require("orbit.modules.dap.runtime").setup(
          require("dap"), require("orbit.modules.dap.definitions").build(opts))
      end,
    },
  }
  if opts.ui then
    specs[#specs + 1] = {
      "rcarriga/nvim-dap-ui",
      dependencies = { "Orbit-Lua/nvim-dap", "nvim-neotest/nvim-nio" },
      keys = {
        { "<leader>du", function() require("dapui").toggle() end, desc = "dap toggle ui" },
        { "<leader>dr", function() require("dap").restart() end, desc = "dap restart" },
        { "<leader>dw", function()
          require("dapui").float_element("watches", { enter = true })
        end, desc = "dap open watch window" },
      },
      config = function(_, ui_opts)
        require("orbit.modules.dap.runtime").setup_ui(ui_opts)
      end,
    }
  end
  return specs
end

return M
