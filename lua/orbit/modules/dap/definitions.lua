-- Adapter definitions are independent of the external nvim-dap package.
local M = {}

---@param opts Orbit.DapOptions
---@return table
function M.build(opts)
  local python = require("orbit.modules.dap.python")
  return {
    enabled = { python = opts.python, coreclr = opts.coreclr },
    adapters = {
      python = function(callback, config)
        if config.request == "launch" then
          local executable = python.venv_executable("debugpy")
          if not executable then
            vim.notify("Activate a virtual environment", vim.log.levels.WARN)
            return
          end
          if vim.fn.filereadable(executable) ~= 1 then
            vim.notify("Install debugpy in the virtual environment", vim.log.levels.WARN)
            return
          end
          callback({
            type = "executable",
            command = python.venv_python(),
            args = { "-m", "debugpy.adapter" },
            options = { source_filetype = "python" },
          })
        else
          local connect = config.connect or config
          callback({
            type = "server",
            host = connect.host or opts.python_host,
            port = connect.port or opts.python_port,
            options = { source_filetype = "python" },
          })
        end
      end,
    },
    configurations = {
      python = {
        { type = "python", request = "launch", name = "launch debugpy server",
          program = "$" .. "{file}" },
        { type = "python", request = "attach",
          name = "attach to active debugpy server",
          connect = { host = opts.python_host, port = opts.python_port } },
      },
    },
  }
end

return M
