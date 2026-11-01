-- Register standard native LSP configs at the Lazy config boundary.
-- Once activated, server state requires a fresh Neovim process to change.
local M = {}

---@alias Orbit.LspActivation {already_started?: boolean, activated: string[], failures: table<string, string>}
local started = false

function M.client_capabilities()
  local overrides = {
    textDocument = { diagnostic = { dynamicRegistration = true } },
    window = { workDoneProgress = true },
  }
  local ok, blink = pcall(require, "blink.cmp")
  if ok and type(blink.get_lsp_capabilities) == "function" then
    return blink.get_lsp_capabilities(overrides, true)
  end
  return vim.tbl_deep_extend("force",
    vim.lsp.protocol.make_client_capabilities(), overrides)
end

local function set_diagnostics(opts)
  local severity = vim.diagnostic.severity
  vim.diagnostic.config({
    underline = opts.underline,
    update_in_insert = opts.update_in_insert,
    severity_sort = opts.severity_sort,
    virtual_text = opts.virtual_text and {
      spacing = 4,
      source = "if_many",
      prefix = "●",
      severity = { min = severity.WARN },
    } or false,
    signs = { text = {
      [severity.ERROR] = " ",
      [severity.WARN] = " ",
      [severity.HINT] = " ",
      [severity.INFO] = " ",
    } },
    float = { border = opts.float_border },
  })
end

---@param opts Orbit.LspOptions
---@return Orbit.LspActivation
function M.setup(opts)
  if started then
    return { already_started = true, activated = {}, failures = {} }
  end
  local capabilities = M.client_capabilities()
  local configs = require("orbit.modules.lsp.servers")
  local tool_state = require("orbit.hangar_bridge")
  local activated, failures = {}, {}
  set_diagnostics(opts.diagnostics)
  local names = vim.tbl_keys(opts.servers)
  table.sort(names)
  for _, name in ipairs(names) do
    if opts.servers[name] and tool_state.is_enabled("lsp", name) then
      local config = vim.tbl_deep_extend("force", {
        capabilities = vim.deepcopy(capabilities),
        on_init = function(client)
          if not opts.semantic_tokens then
            client.server_capabilities.semanticTokensProvider = nil
          end
        end,
      }, configs.get(name))
      local registered, failure = pcall(vim.lsp.config, name, config)
      if registered then
        local enabled, reason = pcall(vim.lsp.enable, name)
        if enabled then
          activated[#activated + 1] = name
        else
          failures[name] = tostring(reason)
        end
      else
        failures[name] = tostring(failure)
      end
      if failures[name] then
        vim.notify("orbit.nvim LSP " .. name .. ": " .. failures[name],
          vim.log.levels.WARN)
      end
    end
  end
  started = true
  return { activated = activated, failures = failures }
end

return M
