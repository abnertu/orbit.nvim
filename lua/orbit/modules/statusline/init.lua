local M = {}

---@alias Orbit.StatuslineSnapshot {owned: boolean, original?: string, current: string, gap: integer}
---@alias Orbit.StatuslineSymbolProvider {get: fun(): string?}
local owned = false
local gap = 1
---@type string?
local original
local group_name = "OrbitStatusline"
local expression = "%!v:lua.require'orbit.modules.statusline.render'.render()"

---@class Orbit.StatuslineOptions # Orbit global status line.
---@field enabled? boolean @default(true) # Draw the Orbit status line.
---@field gap? integer @default(1) @minimum(0) @maximum(8) # Blank cells between status line sections.

local function sync_group(active)
  pcall(vim.api.nvim_del_augroup_by_name, group_name)
  if not active then
    return
  end
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  -- The events module owns the DiagnosticChanged redraw.
  vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
    group = group,
    callback = function()
      vim.cmd.redrawstatus()
    end,
    desc = "Redraw the Orbit status line",
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      require("orbit.modules.statusline.render").define_highlights()
    end,
    desc = "Restore Orbit status line highlight links",
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GitSignsUpdate",
    callback = function()
      vim.cmd.redrawstatus()
    end,
    desc = "Redraw the Orbit status line after Git sign updates",
  })
  -- :nohlsearch fires no event and has several callers, such as <Esc> and
  -- <C-L>. Compare v:hlsearch when Neovim waits for input instead.
  local render = require("orbit.modules.statusline.render")
  local highlighting = render.highlighting()
  vim.api.nvim_create_autocmd("SafeState", {
    group = group,
    callback = function()
      if render.highlighting() ~= highlighting then
        highlighting = not highlighting
        vim.cmd.redrawstatus()
      end
    end,
    desc = "Redraw the Orbit status line when the search highlight changes",
  })
end

---@return Orbit.StatuslineSnapshot
function M.capture()
  return { owned = owned, original = original, current = vim.go.statusline, gap = gap }
end

---@param snapshot Orbit.StatuslineSnapshot
function M.restore(snapshot)
  owned, original, gap = snapshot.owned, snapshot.original, snapshot.gap
  vim.go.statusline = snapshot.current
  sync_group(owned)
end

---@param opts? Orbit.StatuslineOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("statusline", opts)
  local changed = gap ~= opts.gap
  gap = opts.gap
  if opts.enabled then
    if not owned then
      original, owned = vim.go.statusline, true
    end
    vim.go.statusline = expression
  elseif owned then
    -- Keep a value the user set after Orbit took ownership.
    if vim.go.statusline == expression then
      vim.go.statusline = original
    end
    owned, original = false, nil
  end
  sync_group(owned)
  if changed and owned then
    vim.cmd.redrawstatus()
  end
end

---Return the configured blank cells between sections. The renderer reads it on each redraw.
---@return integer
function M.gap()
  return gap
end

return M
