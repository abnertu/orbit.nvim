local M = {}

---@alias Orbit.DemandEvent {event: string, buf?: integer}
---@alias Orbit.PluginsSnapshot {group?: integer, searcher?: function, options?: Orbit.PluginsOptions, state: string, failure?: string, original_loadplugins?: boolean, current_loadplugins: boolean}

---@class Orbit.PluginsOptions # On-demand Lazy plugin initialization.
---@field enabled? boolean @default(false) @restart(true) # Enable plugin initialization for this session.
---@field path? string @default("") @restart(true) # Optional existing lazy.nvim installation directory.
---@field import? string @default("plugins") @minLength(1) @restart(true) # Lazy plugin spec import module.
---@field bootstrap? boolean @default(false) @restart(true) # Clone Lazy on first demand when missing.
---@field source? string @default("https://github.com/folke/lazy.nvim.git") @minLength(1) @restart(true) # Git source for Lazy bootstrap.
---@field lockfile? string @default("") @restart(true) # Optional locked revision file.

local group
local searcher
local options
local state = "disabled"
local failure
local initial_loadplugins

local demand_events = {
  "UIEnter", "BufReadPre", "BufNewFile", "StdinReadPre",
  "CmdUndefined", "ColorSchemePre",
}
local replay_events = { BufReadPre = true, BufNewFile = true, StdinReadPre = true }

local function clear_group()
  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
    group = nil
  end
end

local function clear_searcher()
  if searcher then
    for index, entry in ipairs(package.loaders) do
      if entry == searcher then
        table.remove(package.loaders, index)
        break
      end
    end
    searcher = nil
  end
end

---@return string
function M.status()
  return state
end

---Activate installed Lazy once, and replay only observers registered by Lazy.
---@param event? Orbit.DemandEvent
function M.activate(event)
  if state == "loading" or state == "loaded" then
    return
  end
  if state == "failed" then
    error(failure, 0)
  end
  assert(state == "pending", "plugin startup is not enabled")

  local previous = {}
  local replay = event and replay_events[event.event] and event.buf
  if replay then
    for _, item in ipairs(vim.api.nvim_get_autocmds({ event = event.event })) do
      if item.group then
        previous[item.group] = true
      end
    end
  end

  state = "loading"
  clear_searcher()
  clear_group()
  local ok, err = xpcall(function()
    if options.path ~= "" then
      local path = require("orbit.lazy_bootstrap").ensure(options)
      vim.opt.rtp:prepend(path)
    end
    vim.go.loadplugins = true
    require("lazy").setup({ { import = options.import } }, {
      defaults = { lazy = true },
      rocks = { enabled = false, herorocks = false },
    })
  end, debug.traceback)
  if not ok then
    state = "failed"
    failure = "orbit.nvim plugin initialization failed: " .. tostring(err)
    vim.go.loadplugins = initial_loadplugins
    error(failure, 0)
  end

  state = "loaded"
  if replay then
    for _, item in ipairs(vim.api.nvim_get_autocmds({ event = event.event })) do
      if item.group and not previous[item.group] then
        previous[item.group] = true
        vim.api.nvim_exec_autocmds(event.event, {
          group = item.group, buffer = event.buf, modeline = false,
        })
      end
    end
  end
end

local function install()
  local ok, existing = pcall(vim.api.nvim_get_autocmds,
    { group = "OrbitPluginDemand" })
  assert(not ok or #existing == 0,
    "plugin demand group is owned by another component")
  group = vim.api.nvim_create_augroup("OrbitPluginDemand", { clear = true })
  vim.api.nvim_create_autocmd(demand_events, {
    group = group,
    nested = true,
    callback = M.activate,
    desc = "Initialize Lazy on first plugin demand",
  })
  searcher = function(name)
    M.activate()
    if package.loaded[name] ~= nil then
      local loaded = package.loaded[name]
      return function()
        return loaded
      end
    end
    for _, loader in ipairs(package.loaders) do
      local result, data = loader(name)
      if type(result) == "function" then
        return result, data
      end
    end
    return "\n\tno plugin module found after orbit.nvim activation"
  end
  table.insert(package.loaders, searcher)
  vim.go.loadplugins = false
end

---Capture pending state. Actual plugin activation cannot be rolled back.
---@return Orbit.PluginsSnapshot
function M.capture()
  return {
    group = group,
    searcher = searcher,
    options = options and vim.deepcopy(options) or nil,
    state = state,
    failure = failure,
    original_loadplugins = initial_loadplugins,
    current_loadplugins = vim.go.loadplugins,
  }
end

---@param snapshot Orbit.PluginsSnapshot
function M.restore(snapshot)
  assert(state ~= "loaded" or snapshot.state == "loaded",
    "loaded plugins cannot be rolled back; restart Neovim")
  if group ~= snapshot.group then
    clear_group()
  end
  if searcher ~= snapshot.searcher then
    clear_searcher()
  end
  group = snapshot.group
  searcher = snapshot.searcher
  options = snapshot.options and vim.deepcopy(snapshot.options) or nil
  state = snapshot.state
  failure = snapshot.failure
  initial_loadplugins = snapshot.original_loadplugins
  vim.go.loadplugins = snapshot.current_loadplugins
end

---@param opts? Orbit.PluginsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("plugins", opts)
  if options then
    assert(vim.deep_equal(options, opts),
      "plugin startup options require restarting Neovim")
    return
  end
  if opts.enabled and opts.bootstrap then
    assert(opts.path ~= "", "bootstrap requires a nonempty installation path")
  end
  options = vim.deepcopy(opts)
  if not opts.enabled then
    state = "disabled"
    return
  end
  initial_loadplugins = vim.go.loadplugins
  state = "pending"
  install()
end

return M
