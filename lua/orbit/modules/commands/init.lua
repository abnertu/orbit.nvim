local M = {}

---@alias Orbit.CommandsSnapshot {name?: string, path?: string}
local owned_name
local owned_path

---@class Orbit.CommandsOptions # Settings command integration.
---@field enabled? boolean @default(true) # Register the settings command.
---@field name? string @default("OrbitSettings") @minLength(1) # Command name.
---@field path? string @default("") # Optional settings path override.

local function current_path()
  return require("orbit.settings").path(owned_path ~= "" and owned_path or nil)
end

local function initialize(path)
  local stat, err, code = vim.uv.fs_stat(path)
  if stat then
    assert(stat.type == "file", "settings path must be a regular file: " .. path)
    return
  end
  assert(code == "ENOENT", "cannot inspect settings path: " .. tostring(err))

  local parent = vim.fs.dirname(path)
  vim.fn.mkdir(parent, "p")
  assert(vim.fn.isdirectory(parent) == 1, "cannot create settings directory: " .. parent)
  local schema = assert(vim.api.nvim_get_runtime_file("settings.schema.json", false)[1],
    "settings schema is missing")
  local content = "{\n  \"$schema\": " ..
    vim.json.encode(vim.uri_from_fname(schema)) .. "\n}\n"

  -- Open exclusively. Never truncate an existing user settings file.
  local handle, open_error, open_code = vim.uv.fs_open(path, "wx", 420)
  if not handle then
    assert(open_code == "EEXIST", "cannot create settings: " .. tostring(open_error))
    return
  end
  local written, write_error = vim.uv.fs_write(handle, content, 0)
  local closed, close_error = vim.uv.fs_close(handle)
  if not written or written ~= #content or not closed then
    vim.uv.fs_unlink(path)
    error("failed to initialize settings: " ..
      tostring(write_error or close_error or "short write"))
  end
end

local function info(path)
  local lines = { "Settings: " .. path, "" }
  local accepted = require("orbit").get_config()
  local function append(values, prefix)
    for _, key in ipairs(vim.fn.sort(vim.tbl_keys(values))) do
      local name = prefix == "" and key or prefix .. "." .. key
      local value = values[key]
      if type(value) == "table" and not vim.islist(value) and next(value) then
        append(value, name)
      else
        lines[#lines + 1] = name .. " = " .. vim.json.encode(value)
      end
    end
  end
  if accepted then
    append(accepted, "")
  else
    lines[#lines + 1] = "No accepted configuration."
  end
  vim.cmd.new()
  local buffer = vim.api.nvim_get_current_buf()
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
end

local function dispatch(action)
  local ok, err = xpcall(function()
    local path = current_path()
    if action == "" or action == "open" then
      initialize(path)
      vim.cmd.edit({ args = { path } })
    elseif action == "reload" then
      local loaded, message = require("orbit").reload_from_file(path)
      assert(loaded, message)
    elseif action == "info" then
      info(path)
    else
      error("expected open, reload or info")
    end
  end, debug.traceback)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.WARN, { title = "orbit.nvim settings" })
  end
end

local function register(name)
  vim.api.nvim_create_user_command(name, function(opts)
    dispatch(opts.args)
  end, {
    nargs = "?",
    desc = "Open, reload or inspect orbit.nvim settings",
    complete = function(prefix)
      return vim.tbl_filter(function(s)
        return vim.startswith(s, prefix)
      end, { "open", "reload", "info" })
    end,
  })
end

---Capture this module's registration, not unrelated user commands.
---@return Orbit.CommandsSnapshot
function M.capture()
  return { name = owned_name, path = owned_path }
end

---@param snapshot Orbit.CommandsSnapshot
function M.restore(snapshot)
  if owned_name then
    pcall(vim.api.nvim_del_user_command, owned_name)
  end
  owned_name, owned_path = nil, nil
  if snapshot.name then
    register(snapshot.name)
    owned_name, owned_path = snapshot.name, snapshot.path
  end
end

---@param opts? Orbit.CommandsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("commands", opts)
  if not opts.enabled then
    if owned_name then
      vim.api.nvim_del_user_command(owned_name)
    end
    owned_name, owned_path = nil, nil
    return
  end
  assert(opts.name:match("^[A-Z][A-Za-z0-9]*$"),
    "command name must begin with an uppercase letter")
  if owned_name ~= opts.name then
    assert(vim.api.nvim_get_commands({})[opts.name] == nil,
      "refusing to overwrite existing user command: " .. opts.name)
    if owned_name then
      vim.api.nvim_del_user_command(owned_name)
    end
    register(opts.name)
    owned_name = opts.name
  end
  owned_path = opts.path
end

return M
