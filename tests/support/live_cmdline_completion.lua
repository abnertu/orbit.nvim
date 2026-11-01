-- Child observations keep production providers, demand events, and mappings intact.
---@class Orbit.LiveCmdlineOptions
---@field site string
---@field installed string
---@field dependencies table<string, string>
---@field completion boolean
---@field messages boolean

---@class Orbit.LiveCmdlineWindow
---@field id integer
---@field ft string
---@field floating boolean
---@field lines string[]

---@class Orbit.LiveCmdlineSnapshot
---@field mode string
---@field command string
---@field command_type string
---@field blink boolean
---@field noice boolean
---@field noice_running boolean
---@field visible boolean
---@field selected string
---@field selected_index integer
---@field items string[]
---@field windows Orbit.LiveCmdlineWindow[]
---@field loaded table<string, integer>
---@field events string[]
---@field accepts string[]
---@field executed string[]
---@field errors string[]
---@field errmsg string
---@field editor integer
---@field editor_buffer integer
---@field current_window integer
---@field lines string[]
---@field cursor integer[]
---@field next_mapping {callback: boolean, expr: integer, rhs: string, desc: string}

---@param opts Orbit.LiveCmdlineOptions
return function(opts)
  vim.opt.packpath = { opts.site, vim.env.VIMRUNTIME }
  vim.cmd.packadd("orbit.nvim")
  local orbit = require("orbit")
  local source = vim.fs.normalize(debug.getinfo(orbit.setup, "S").source:sub(2))
  local installed = vim.fs.normalize(opts.installed)
  if vim.fn.has("win32") == 1 then source, installed = source:lower(), installed:lower() end
  assert(source:sub(1, #installed + 1) == installed .. "/", "wrong native Orbit installation")

  ---@type string[], string[], string[], string[], table<string, integer>
  local errors, accepts, executed, events, loaded = {}, {}, {}, {}, {}
  local editor, buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local group = vim.api.nvim_create_augroup("OrbitLiveCmdline", {})
  local notify = vim.notify
  vim.notify = function(message, level, options)
    if level and level >= vim.log.levels.ERROR then errors[#errors + 1] = tostring(message) end
    return notify(message, level, options)
  end
  vim.ui_attach(vim.api.nvim_create_namespace("OrbitLiveCmdlineMessages"), { ext_messages = true },
    function(event, kind, content)
      if event == "msg_show" and kind == "emsg" then
        local parts = {}
        for _, chunk in ipairs(content) do parts[#parts + 1] = chunk[2] end
        errors[#errors + 1] = table.concat(parts)
      end
    end)
  vim.api.nvim_create_autocmd({ "UIEnter", "InsertEnter", "CmdlineEnter" }, {
    group = group,
    ---@param event vim.api.keyset.create_autocmd.callback_args
    callback = function(event) events[#events + 1] = event.event end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "VeryLazy",
    callback = function() events[#events + 1] = "VeryLazy" end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "LazyLoad",
    ---@param event {data: string}
    callback = function(event)
      loaded[event.data] = (loaded[event.data] or 0) + 1
      events[#events + 1] = "LazyLoad:" .. event.data
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "BlinkCmpAccept",
    ---@param event {data: {item: {label: string}}}
    callback = function(event) accepts[#accepts + 1] = event.data.item.label end,
  })
  for _, name in ipairs({ "OrbitCmdlineAlpha", "OrbitCmdlineBeta", "OrbitCmdlineGamma" }) do
    vim.api.nvim_create_user_command(name, function() executed[#executed + 1] = name end, {})
  end
  vim.bo.filetype = "text"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
    "orbitSearchUniqueBackward", "editor anchor", "orbitSearchUniqueForward",
  })
  vim.api.nvim_win_set_cursor(editor, { 2, 0 })

  local manifest = vim.json.decode(table.concat(vim.fn.readfile(
    vim.fs.joinpath(opts.installed, "lua/orbit/modules/manifest.json")), "\n"))
  local modules = {}
  for _, name in ipairs(manifest.order) do modules[name] = { enabled = false } end
  modules.completion = { enabled = opts.completion }
  modules.messages = { enabled = opts.messages }
  modules.plugins = { enabled = true, path = opts.dependencies["lazy.nvim"], import = "live_cmdline_paths" }
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

  package.loaded["orbit.tests.live_cmdline_completion"] = {
    ---@return LazySpec
    import = function()
      local specs = require("plugins")
      for index, spec in ipairs(specs) do
        specs[index] = localize(spec)
        -- Native binary distribution is a separate acceptance gate.
        if spec[1] == "saghen/blink.cmp" then spec.opts.fuzzy.implementation = "lua" end
      end
      return specs
    end,
    repeat_setup = function() orbit.setup(options); orbit.setup(options) end,
    ---@return Orbit.LiveCmdlineSnapshot
    snapshot = function()
      local cmp = package.loaded["blink.cmp"]
      local noice = package.loaded.noice
      local config = package.loaded["noice.config"]
      local selected = type(cmp) == "table" and cmp.get_selected_item()
      local next_mapping = vim.fn.maparg("<C-j>", "c", false, true)
      local items = {}
      if type(cmp) == "table" then
        for _, item in ipairs(cmp.get_items()) do items[#items + 1] = item.label end
      end
      ---@type Orbit.LiveCmdlineWindow[]
      local windows = {}
      for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(window)
        windows[#windows + 1] = { id = window, ft = vim.bo[buf].filetype,
          floating = vim.api.nvim_win_get_config(window).relative ~= "",
          lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false) }
      end
      return {
        mode = vim.api.nvim_get_mode().mode,
        command = vim.fn.getcmdline(), command_type = vim.fn.getcmdtype(),
        blink = type(cmp) == "table", noice = type(noice) == "table",
        noice_running = type(config) == "table" and config.is_running() or false,
        visible = type(cmp) == "table" and cmp.is_visible() or false,
        selected = selected and selected.label or "",
        selected_index = type(cmp) == "table" and cmp.get_selected_item_idx() or 0,
        items = items, windows = windows, loaded = loaded, events = events,
        accepts = accepts, executed = executed, errors = errors, errmsg = vim.v.errmsg,
        editor = editor, editor_buffer = vim.api.nvim_win_get_buf(editor),
        current_window = vim.api.nvim_get_current_win(),
        lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
        cursor = vim.api.nvim_win_get_cursor(editor),
        next_mapping = { callback = type(next_mapping.callback) == "function",
          expr = next_mapping.expr or 0, rhs = next_mapping.rhs or "", desc = next_mapping.desc or "" },
      }
    end,
  }
  orbit.setup(options)
  assert(not package.loaded["blink.cmp"] and not package.loaded.noice, "eager commandline plugin import")
end
