local M = {}

---@alias Orbit.EventsSnapshot {group?: integer, active?: Orbit.EventsOptions, ui_entered: boolean, filepost_emitted: boolean, filepost_id?: integer, startup_buffer?: integer}
local group
local active
local ui_entered = false
local filepost_emitted = false
local filepost_id
---@type integer?
local startup_buffer

---@class Orbit.EventsOptions # Standalone core Neovim events.
---@field enabled? boolean @default(true) # Enable core event behavior.
---@field diagnostics_redraw? boolean @default(true) # Redraw the statusline when diagnostics change.
---@field startup_buffer? boolean @default(true) @restart(true) # Keep a temporary unnamed buffer behind startup interfaces.
---@field directory_argument? boolean @default(true) @restart(true) # Change directory for a directory startup argument.
---@field filepost? boolean @default(true) @restart(true) # Emit a one-shot FilePost event when a normal file is ready.

local function is_active(name)
  return active and active.enabled and active[name]
end

local function release_startup_buffer()
  if not is_active("startup_buffer") then return end
  local buffer = startup_buffer
  if not buffer then return end
  startup_buffer = nil
  if not vim.api.nvim_buf_is_valid(buffer)
    or not vim.api.nvim_buf_is_loaded(buffer)
    or vim.bo[buffer].modified or vim.bo[buffer].buftype ~= ""
    or vim.api.nvim_buf_get_name(buffer) ~= ""
    or #vim.fn.win_findbuf(buffer) > 0
    or not vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { "" })
  then return end
  vim.api.nvim_buf_delete(buffer, { force = false })
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

-- On-demand startup re-applies EditorConfig after FileType.
-- Do not import it on startup when the existing flag is unset.
local function replay_editorconfig(buffer)
  if not vim.g.editorconfig
    or not vim.api.nvim_buf_is_valid(buffer)
    or not vim.api.nvim_buf_is_loaded(buffer)
  then
    return
  end
  local ok, editorconfig = pcall(require, "editorconfig")
  if not ok or type(editorconfig.config) ~= "function" then
    return
  end
  local applied, err = pcall(editorconfig.config, buffer)
  if not applied then
    vim.notify("[editorconfig] " .. tostring(err), vim.log.levels.WARN)
  end
end

local function register()
  -- Never silently replace unrelated autocommands with the same group name.
  local found, previous = pcall(vim.api.nvim_get_autocmds, { group = "OrbitCoreEvents" })
  assert(not found or #previous == 0,
    "refusing to overwrite existing OrbitCoreEvents group")

  group = vim.api.nvim_create_augroup("OrbitCoreEvents", { clear = true })

  filepost_id = vim.api.nvim_create_autocmd({
    "UIEnter", "BufReadPost", "BufNewFile",
  }, {
    group = group,
    desc = "Emit FilePost exactly once after the UI and a file are ready",
    callback = function(event)
      if event.event == "UIEnter" then
        ui_entered = true
      end
      if filepost_emitted or not is_active("filepost") or not ui_entered then
        return
      end

      local buffer = event.buf
      if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
        return
      end
      local name = vim.api.nvim_buf_get_name(buffer)
      local buftype = vim.api.nvim_get_option_value("buftype", { buf = buffer })
      if name == "" or buftype ~= "" then
        return
      end

      filepost_emitted = true
      if filepost_id then
        vim.api.nvim_del_autocmd(filepost_id)
        filepost_id = nil
      end

      vim.api.nvim_exec_autocmds("User", {
        pattern = "FilePost",
        modeline = false,
      })
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer)
          and vim.api.nvim_buf_is_loaded(buffer)
        then
          vim.api.nvim_exec_autocmds("FileType", {
            buffer = buffer,
            modeline = false,
          })
          replay_editorconfig(buffer)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    desc = "Redraw the statusline when diagnostics change",
    callback = function()
      if is_active("diagnostics_redraw") then
        vim.cmd.redrawstatus()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    desc = "Release an unused Orbit startup buffer after opening a file",
    callback = function(event)
      if startup_buffer and is_active("startup_buffer")
        and vim.bo[event.buf].buftype == "" and vim.api.nvim_buf_get_name(event.buf) ~= ""
      then
        vim.schedule(release_startup_buffer)
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
        local current = vim.api.nvim_get_current_buf()
        local file_ready = vim.bo[current].buftype == "" and vim.api.nvim_buf_get_name(current) ~= ""
        if is_active("startup_buffer") and not file_ready and not has_listed_unnamed_buffer() then
          startup_buffer = vim.api.nvim_create_buf(true, false)
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
---@return Orbit.EventsSnapshot
function M.capture()
  return {
    group = group,
    active = active and vim.deepcopy(active) or nil,
    ui_entered = ui_entered,
    filepost_emitted = filepost_emitted,
    filepost_id = filepost_id,
    startup_buffer = startup_buffer,
  }
end

---@param snapshot Orbit.EventsSnapshot
function M.restore(snapshot)
  if group and not snapshot.group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
    group = nil
    filepost_id = nil
  end
  ui_entered = snapshot.ui_entered
  filepost_emitted = snapshot.filepost_emitted
  filepost_id = snapshot.filepost_id
  startup_buffer = snapshot.startup_buffer
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
