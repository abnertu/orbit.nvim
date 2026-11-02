-- Child observations around native startup and real upstream plugins.
---@class Orbit.LiveStartupOptions
---@field site string
---@field installed string
---@field dependencies table<string, string>
---@field plugins boolean
---@field dashboard boolean

---@class Orbit.LiveStartupBuffer
---@field id integer
---@field name string
---@field ft string
---@field bt string
---@field listed boolean
---@field lines string[]

---@class Orbit.LiveStartupWindow
---@field id integer
---@field buffer integer
---@field floating boolean

---@class Orbit.LiveStartupEvent
---@field event string
---@field buffer integer
---@field name string
---@field ui boolean

---@class Orbit.LiveStartupSnapshot
---@field current integer
---@field window integer
---@field cwd string
---@field buffers Orbit.LiveStartupBuffer[]
---@field windows Orbit.LiveStartupWindow[]
---@field journal Orbit.LiveStartupEvent[]
---@field loaded table<string, integer>
---@field imported boolean
---@field lazy boolean
---@field snacks boolean
---@field tree boolean
---@field oil boolean
---@field status string
---@field errors string[]
---@field errmsg string
---@field manifest string[]
---@field specs string[]
---@field helper string[]
---@field helper_loaded boolean

---@param opts Orbit.LiveStartupOptions
return function(opts)
  vim.opt.packpath = { opts.site, vim.env.VIMRUNTIME }
  vim.cmd.packadd("orbit.nvim")
  local orbit = require("orbit")
  local source = vim.fs.normalize(debug.getinfo(orbit.setup, "S").source:sub(2))
  local installed = vim.fs.normalize(opts.installed)
  if vim.fn.has("win32") == 1 then source, installed = source:lower(), installed:lower() end
  assert(source:sub(1, #installed + 1) == installed .. "/",
    "native package loaded a different Orbit checkout: " .. source)

  ---@type Orbit.LiveStartupEvent[]
  local journal = {}
  ---@type string[]
  local errors = {}
  ---@type table<string, integer>
  local loaded = {}
  local imported = false
  local group = vim.api.nvim_create_augroup("OrbitLiveStartup", {})
  ---@param event vim.api.keyset.create_autocmd.callback_args
  local function record(event)
    journal[#journal + 1] = {
      event = event.event == "User" and event.match or event.event,
      buffer = event.buf, name = vim.api.nvim_buf_get_name(event.buf),
      ui = #vim.api.nvim_list_uis() > 0,
    }
  end
  vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter", "BufReadPre", "BufNewFile" }, {
    group = group, callback = record,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = { "FilePost", "LazyDone", "VeryLazy" }, callback = record,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "LazyLoad",
    callback = function(event)
      loaded[event.data] = (loaded[event.data] or 0) + 1
    end,
  })
  local notify = vim.notify
  vim.notify = function(message, level, options)
    if level and level >= vim.log.levels.WARN then errors[#errors + 1] = tostring(message) end
    return notify(message, level, options)
  end

  local manifest = vim.json.decode(table.concat(vim.fn.readfile(
    vim.fs.joinpath(opts.installed, "lua/orbit/modules/manifest.json")), "\n"))
  local modules = {}
  for _, name in ipairs(manifest.order) do modules[name] = { enabled = false } end
  modules.events = { enabled = true }
  modules.snacks = { enabled = true, dashboard = opts.dashboard }
  modules.navigation = { enabled = true, harpoon = false }
  modules.plugins = { enabled = opts.plugins, path = opts.dependencies["lazy.nvim"], import = "live_paths" }
  local options = { modules = modules }

  -- The config-local import calls this after real Lazy resets runtimepath.
  -- Only paths change; all production declarations and config callbacks run.
  package.loaded["orbit.tests.live_startup_ui"] = {
    ---@return LazySpec
    import = function()
      imported = true
      ---@type LazySpec
      local specs = require("orbit.plugins")
      for _, spec in ipairs(specs) do
        spec.dir = assert(opts.dependencies[spec[1]:match("[^/]+$")], spec[1])
      end
      vim.api.nvim_create_autocmd("BufReadPre", {
        group = vim.api.nvim_create_augroup("OrbitLiveNewRead", {}),
        callback = function(event)
          record(vim.tbl_extend("force", event, { event = "NewRead" }))
        end,
      })
      return specs
    end,
    ---@return Orbit.LiveStartupSnapshot
    snapshot = function()
      ---@type Orbit.LiveStartupBuffer[]
      local buffers = {}
      for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        buffers[#buffers + 1] = {
          id = buffer, name = vim.api.nvim_buf_get_name(buffer),
          ft = vim.bo[buffer].filetype, bt = vim.bo[buffer].buftype,
          listed = vim.bo[buffer].buflisted,
          lines = vim.api.nvim_buf_is_loaded(buffer)
            and vim.api.nvim_buf_get_lines(buffer, 0, -1, false) or {},
        }
      end
      ---@type Orbit.LiveStartupWindow[]
      local windows = {}
      for _, window in ipairs(vim.api.nvim_list_wins()) do
        windows[#windows + 1] = {
          id = window, buffer = vim.api.nvim_win_get_buf(window),
          floating = vim.api.nvim_win_get_config(window).relative ~= "",
        }
      end
      return {
        current = vim.api.nvim_get_current_buf(), window = vim.api.nvim_get_current_win(),
        cwd = vim.fn.getcwd(), buffers = buffers, windows = windows, journal = journal,
        loaded = loaded, imported = imported, status = require("orbit.modules.plugins").status(),
        lazy = package.loaded.lazy ~= nil, snacks = package.loaded.snacks ~= nil,
        tree = package.loaded["nvim-tree"] ~= nil, oil = package.loaded.oil ~= nil,
        errors = errors, errmsg = vim.v.errmsg,
        manifest = vim.api.nvim_get_runtime_file("lua/orbit/modules/manifest.json", true),
        specs = vim.api.nvim_get_runtime_file("lua/orbit/plugins/init.lua", true),
        helper = vim.api.nvim_get_runtime_file("lua/orbit/modules/snacks/runtime.lua", true),
        helper_loaded = package.loaded["orbit.modules.snacks.runtime"] ~= nil,
      }
    end,
    repeat_setup = function() orbit.setup(options); orbit.setup(options) end,
  }
  orbit.setup(options)
  assert(not package.loaded["orbit.modules.snacks.runtime"], "Snacks helper loaded before demand")
end
