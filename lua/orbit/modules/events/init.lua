local M = {}
local group
local active

---@class Orbit.EventsOptions # Standalone core Neovim events.
---@field enabled boolean @default(true) # Enable core event behavior.
---@field diagnostics_redraw boolean @default(true) # Redraw the statusline when diagnostics change.
---@field startup_buffer boolean @default(true) # Keep a listed unnamed buffer behind startup interfaces.
---@field directory_argument boolean @default(true) # Change directory for a directory startup argument.

local function is_active(name)
  return active and active.enabled and active[name]
end

local function has_listed_unnamed_buffer()
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer)
      and vim.api.nvim_buf_is_loaded(buffer)
      and vim.bo[buffer].buflisted
      and vim.bo[buffer].buftype == ""
      and vim.api.nvim_buf_get_name(buffer) == ""
    then
      return true
    end
  end
  return false
end

local function register()
  -- Never silently replace unrelated autocommands with the same group name.
  local found, previous = pcall(vim.api.nvim_get_autocmds, { group = "OrbitCoreEvents" })
  assert(not found or #previous == 0,
    "refusing to overwrite existing OrbitCoreEvents group")

  group = vim.api.nvim_create_augroup("OrbitCoreEvents", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    desc = "Redraw the statusline when diagnostics change",
    callback = function()
      if is_active("diagnostics_redraw") then
        vim.cmd.redrawstatus()
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    desc = "Keep an unnamed listed buffer behind the startup UI",
    callback = function(event)
      if not is_active("startup_buffer")
        or vim.fn.argc() > 0
        or (event.file or "") ~= ""
      then
        return
      end

      vim.schedule(function()
        if is_active("startup_buffer") and not has_listed_unnamed_buffer() then
          vim.api.nvim_create_buf(true, false)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    desc = "Use a directory startup argument as the working directory",
    callback = function(event)
      if not is_active("directory_argument")
        or type(event.file) ~= "string"
        or vim.fn.isdirectory(event.file) ~= 1
      then
        return
      end

      vim.api.nvim_set_current_dir(event.file)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(event.buf) then
          vim.api.nvim_buf_delete(event.buf, { force = true })
        end
      end)
    end,
  })
end

---Capture owner state without disturbing other Neovim events.
---@return table
function M.capture()
  return {
    group = group,
    active = active and vim.deepcopy(active) or nil,
  }
end

---@param snapshot table
function M.restore(snapshot)
  if group and not snapshot.group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
    group = nil
  end
  active = snapshot.active and vim.deepcopy(snapshot.active) or nil
end

---A registered group is reused; disabling leaves inert callbacks for rollback.
---@param opts? Orbit.EventsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("events", opts)
  if opts.enabled and not group then
    register()
  end
  active = vim.deepcopy(opts)
end

return M
