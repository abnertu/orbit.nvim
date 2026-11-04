-- Configure Hangar at startup, before event-loaded tool owners register their
-- tools. Hangar gates LSP, DAP, conform, nvim-lint and Tree-sitter itself.
local M = {}
local active = false

---@param opts Orbit.MasonHangar
---@return Hangar.Options
function M.options(opts)
  return {
    registry = require("orbit.modules.mason.registry"),
    state_path = function()
      if opts.state_file ~= "" then
        return opts.state_file
      end
      return vim.g.hangar_state_path or vim.fs.joinpath(vim.fn.stdpath("data"), "hangar.json")
    end,
    border = opts.border,
  }
end

---@param opts Orbit.MasonHangar
function M.setup(opts)
  if active then
    return
  end
  assert(
    opts.command:match("^[A-Z][A-Za-z0-9]*$"),
    "Hangar command must start with an uppercase letter"
  )
  assert(
    vim.api.nvim_get_commands({})[opts.command] == nil,
    "refusing to replace an existing user command: " .. opts.command
  )

  local hangar = require("hangar")
  hangar.setup(M.options(opts))
  vim.api.nvim_create_user_command(opts.command, function()
    hangar.open()
  end, { desc = "Open Hangar tool manager" })
  vim.keymap.set(
    "n",
    opts.key,
    "<cmd>" .. opts.command .. "<cr>",
    { desc = "Hangar", silent = true }
  )
  active = true
end

return M
