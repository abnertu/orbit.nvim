-- Child-side observations; production Lazy specs and input handlers stay intact.
---@class Orbit.LiveCompletionOptions
---@field site string
---@field installed string
---@field dependencies table<string, string>
---@field plugins boolean

---@class Orbit.LiveCompletionWindow
---@field id integer
---@field ft string
---@field lines string[]

---@class Orbit.LiveCompletionSnapshot
---@field mode string
---@field lines string[]
---@field cursor integer[]
---@field visible boolean
---@field selected string
---@field windows Orbit.LiveCompletionWindow[]
---@field blink boolean
---@field luasnip boolean
---@field snippet boolean
---@field node integer
---@field native boolean
---@field hlsearch integer
---@field loaded table<string, integer>
---@field accepts string[]
---@field leaves boolean[]
---@field cleanup integer
---@field errors string[]
---@field errmsg string

---@param opts Orbit.LiveCompletionOptions
return function(opts)
  vim.opt.packpath = { opts.site, vim.env.VIMRUNTIME }
  vim.cmd.packadd("orbit.nvim")
  local orbit = require("orbit")
  local source = vim.fs.normalize(debug.getinfo(orbit.setup, "S").source:sub(2))
  local installed = vim.fs.normalize(opts.installed)
  if vim.fn.has("win32") == 1 then source, installed = source:lower(), installed:lower() end
  assert(source:sub(1, #installed + 1) == installed .. "/", "wrong native Orbit installation")

  ---@type string[], string[], boolean[], table<string, integer>
  local errors, accepts, leaves, loaded = {}, {}, {}, {}
  local group = vim.api.nvim_create_augroup("OrbitLiveCompletion", {})
  local notify = vim.notify
  vim.notify = function(message, level, options)
    if level and level >= vim.log.levels.ERROR then errors[#errors + 1] = tostring(message) end
    return notify(message, level, options)
  end
  -- Observe real emitted errors too; :silent! errors need not be emitted.
  vim.ui_attach(vim.api.nvim_create_namespace("OrbitLiveCompletionMessages"), { ext_messages = true },
    function(event, kind, content)
      if event == "msg_show" and kind == "emsg" then
        local parts = {}
        for _, chunk in ipairs(content) do parts[#parts + 1] = chunk[2] end
        errors[#errors + 1] = table.concat(parts)
      end
    end)
  -- Register before plugins so Escape's stop cannot be masked by InsertLeave.
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function(event)
      local ls = package.loaded.luasnip
      leaves[#leaves + 1] = type(ls) == "table" and ls.session.current_nodes[event.buf] ~= nil
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "LazyLoad",
    callback = function(event) loaded[event.data] = (loaded[event.data] or 0) + 1 end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "BlinkCmpAccept",
    callback = function(event) accepts[#accepts + 1] = event.data.item.label end,
  })

  local manifest = vim.json.decode(table.concat(vim.fn.readfile(
    vim.fs.joinpath(opts.installed, "lua/orbit/modules/manifest.json")), "\n"))
  local modules = {}
  for _, name in ipairs(manifest.order) do modules[name] = { enabled = false } end
  modules.corekeys = { enabled = true }
  modules.completion = { enabled = opts.plugins }
  modules.plugins = { enabled = opts.plugins, path = opts.dependencies["lazy.nvim"], import = "live_completion_paths" }
  local options = { modules = modules }

  ---@param spec string|LazyPluginSpec
  ---@return LazyPluginSpec
  local function localize(spec)
    if type(spec) == "string" then spec = { spec } end
    spec.dir = assert(opts.dependencies[spec[1]:match("[^/]+$")], spec[1])
    if type(spec.dependencies) == "string" then spec.dependencies = { spec.dependencies } end
    for index, dependency in ipairs(spec.dependencies or {}) do
      spec.dependencies[index] = localize(dependency)
    end
    return spec
  end

  package.loaded["orbit.tests.live_completion_escape"] = {
    ---@return LazySpec
    import = function()
      local specs = require("orbit.plugins")
      for index, spec in ipairs(specs) do
        specs[index] = localize(spec)
        -- Exercise the supported Lua path; native distribution is a separate gate.
        if spec[1] == "saghen/blink.cmp" then spec.opts.fuzzy.implementation = "lua" end
      end
      return specs
    end,
    repeat_setup = function() orbit.setup(options); orbit.setup(options) end,
    ---@return Orbit.LiveCompletionSnapshot
    snapshot = function()
      local cmp, ls = package.loaded["blink.cmp"], package.loaded.luasnip
      local node = type(ls) == "table" and ls.session.current_nodes[vim.api.nvim_get_current_buf()]
      local selected = type(cmp) == "table" and cmp.get_selected_item()
      ---@type Orbit.LiveCompletionWindow[]
      local windows = {}
      for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)
        windows[#windows + 1] = { id = window, ft = vim.bo[buffer].filetype,
          lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false) }
      end
      local ok, handlers = pcall(vim.api.nvim_get_autocmds, { group = "OrbitSnippets", event = "InsertLeave" })
      return {
        mode = vim.api.nvim_get_mode().mode,
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false), cursor = vim.api.nvim_win_get_cursor(0),
        visible = type(cmp) == "table" and cmp.is_visible() or false,
        selected = selected and selected.label or "", windows = windows,
        blink = type(cmp) == "table", luasnip = type(ls) == "table",
        snippet = not not node, node = node and node.pos or -1,
        native = vim.snippet.active(), hlsearch = vim.v.hlsearch,
        loaded = loaded, accepts = accepts, leaves = leaves,
        cleanup = ok and #handlers or 0, errors = errors, errmsg = vim.v.errmsg,
      }
    end,
  }
  vim.bo.filetype = "text"
  orbit.setup(options)
  assert(not package.loaded.luasnip and not package.loaded["blink.cmp"], "eager completion import")
end
