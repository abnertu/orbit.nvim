local M = {}

---@alias Orbit.ColorsSnapshot {options?: Orbit.ColorsOptions, lsp: boolean, lsp_original?: boolean}
---@type Orbit.ColorsOptions?
local accepted

---@class Orbit.ColorsOptions # Color previews for hex codes and LSP document colors.
---@field enabled? boolean @default(true) # Show color previews.
---@field hex? boolean @default(true) # Preview #RGB, #RRGGBB and #RRGGBBAA codes in normal buffers.
---@field lsp? boolean @default(true) # Show LSP document colors.
---@field swatch? string @default("󱓻 ") @minLength(1) @restart(true) # Text drawn before each color.

---@return Orbit.ColorsSnapshot
function M.capture()
  return {
    options = accepted and vim.deepcopy(accepted) or nil,
    lsp = vim.lsp.document_color.is_enabled(),
    lsp_original = require("orbit.modules.colors.runtime").lsp_original(),
  }
end

---@param snapshot Orbit.ColorsSnapshot
function M.restore(snapshot)
  accepted = snapshot.options and vim.deepcopy(snapshot.options) or nil
  local runtime = require("orbit.modules.colors.runtime")
  runtime.set_hex(accepted ~= nil and accepted.enabled and accepted.hex, accepted)
  runtime.set_lsp_original(snapshot.lsp_original)
  vim.lsp.document_color.enable(snapshot.lsp)
end

---@param opts? Orbit.ColorsOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("colors", opts)
  local runtime = require("orbit.modules.colors.runtime")
  runtime.set_hex(accepted.enabled and accepted.hex, accepted)
  runtime.set_lsp(accepted.enabled, accepted.lsp, accepted)
end

return M
