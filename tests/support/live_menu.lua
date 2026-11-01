-- Child fixture observes production menu input and real upstream window state.
---@class Orbit.LiveMenuOptions
---@field site string
---@field installed string
---@field dependencies table<string, string>
---@field enabled boolean
---@field corekeys boolean

---@class Orbit.LiveMenuPosition
---@field row integer
---@field col integer
---@field curscol integer
---@field endcol integer

---@class Orbit.LiveMenuWindow
---@field buf integer
---@field win integer
---@field rows string[]
---@field positions Orbit.LiveMenuPosition[]
---@field origin integer[]

---@class Orbit.LiveMenuMouse
---@field winid integer
---@field line integer
---@field column integer
---@field coladd integer
---@field screenrow integer
---@field screencol integer
---@field winrow integer
---@field wincol integer

---@class Orbit.LiveMenuSnapshot
---@field menus Orbit.LiveMenuWindow[]
---@field loaded table<string, integer>
---@field errors string[]
---@field errmsg string
---@field menu_loaded boolean
---@field runtime_loaded boolean
---@field tree_loaded boolean
---@field current integer
---@field win integer
---@field mode string
---@field cursor integer[]
---@field windows integer[]
---@field preserved boolean
---@field calls table<string, integer>
---@field lines string[]
---@field mouse Orbit.LiveMenuMouse
---@field journal string[]

---@class Orbit.LiveMenuOriginal
---@field mode string
---@field lhs string
---@field buffer? integer
---@field callback fun(): string
---@field id string
---@field mapping Orbit.MenuMapping

---@param opts Orbit.LiveMenuOptions
return function(opts)
  vim.opt.packpath = { opts.site, vim.env.VIMRUNTIME }
  vim.cmd.packadd("orbit.nvim")
  local orbit = require("orbit")
  local source = vim.fs.normalize(debug.getinfo(orbit.setup, "S").source:sub(2))
  local installed = vim.fs.normalize(opts.installed)
  if vim.fn.has("win32") == 1 then source, installed = source:lower(), installed:lower() end
  assert(source:sub(1, #installed + 1) == installed .. "/", "loaded a different Orbit package")
  local manifest = vim.json.decode(table.concat(vim.fn.readfile(
    vim.fs.joinpath(opts.installed, "lua/orbit/modules/manifest.json")), "\n"))
  local modules = {}
  for _, name in ipairs(manifest.order) do modules[name] = { enabled = false } end
  modules.menu = { enabled = opts.enabled }
  modules.corekeys = { enabled = opts.corekeys, save = "<F6>" }
  modules.keymaps = { enabled = true }
  modules.navigation = { enabled = true, oil = false, harpoon = false }
  modules.plugins = { enabled = true, path = opts.dependencies["lazy.nvim"], import = "live_paths" }
  local options = { modules = modules }
  ---@type table<string, integer>
  local loaded = {}
  ---@type string[]
  local errors = {}
  ---@type table<string, integer>
  local calls = {}
  ---@type Orbit.LiveMenuOriginal[]
  local originals = {}
  local original_notify = vim.notify
  ---@param message string
  ---@param level? integer
  ---@param config? {title?: string}
  vim.notify = function(message, level, config)
    if level and level >= vim.log.levels.WARN then errors[#errors + 1] = tostring(message) end
    return original_notify(message, level, config)
  end
  local group = vim.api.nvim_create_augroup("OrbitLiveMenu", {})
  ---@type string[]
  local journal = {}
  ---@param event string
  local function mark(event)
    journal[#journal + 1] = event .. ': ' .. vim.api.nvim_get_current_win()
      .. ' ' .. vim.api.nvim_buf_get_name(0)
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group, callback = function(event)
      mark(event.event)
      if event.event == "WinEnter" and vim.bo.filetype == "NvimTree" then
        journal[#journal + 1] = debug.traceback("tree focus")
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "LazyLoad", callback = function(event)
    loaded[event.data] = (loaded[event.data] or 0) + 1
  end })
  orbit.setup(options)
  vim.o.mouse = "a"
  vim.o.mousemodel = "popup_setpos"
  vim.o.laststatus = 0
  vim.o.showtabline = 0
  vim.o.cmdheight = 1

  ---@param buffer? integer
  local function remember(buffer)
    for _, mode in ipairs({ "n", "x" }) do
      for _, lhs in ipairs({ "<LeftMouse>", "<Esc>" }) do
        local id = mode .. lhs .. tostring(buffer or "global")
        local callback = function()
          calls[id] = (calls[id] or 0) + 1
          return lhs == "<Esc>" and "<Esc>" or ""
        end
        vim.keymap.set(mode, lhs, callback, { buffer = buffer, expr = true, desc = id })
        local maps = buffer and vim.api.nvim_buf_get_keymap(buffer, mode) or vim.api.nvim_get_keymap(mode)
        local original
        for _, value in ipairs(maps) do
          if vim.keycode(value.lhs) == vim.keycode(lhs) then original = value end
        end
        originals[#originals + 1] = {
          mode = mode, lhs = lhs, buffer = buffer, callback = callback, id = id, mapping = assert(original),
        }
      end
    end
  end

  package.loaded["orbit.tests.live_menu"] = {
    mark = mark,
    ---@param first string
    ---@param second string
    ---@return boolean
    same_path = function(first, second)
      first, second = vim.fs.normalize(first), vim.fs.normalize(second)
      if vim.fn.has("win32") == 1 then first, second = first:lower(), second:lower() end
      return first == second
    end,
    ---@return LazySpec
    import = function()
      ---@type LazySpec
      local specs = require("plugins")
      for _, spec in ipairs(specs) do
        spec.dir = assert(opts.dependencies[spec[1]:match("[^/]+$")], spec[1])
        if spec.dependencies then
          for i, dependency in ipairs(spec.dependencies) do
            local name = type(dependency) == "string" and dependency or dependency[1]
            spec.dependencies[i] = { name, dir = assert(opts.dependencies[name:match("[^/]+$")]) }
          end
        end
      end
      return specs
    end,
    prepare = function()
      remember(nil)
      remember(vim.api.nvim_get_current_buf())
      local buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_open_win(buffer, false, {
        relative = "editor", row = 38, col = 115, width = 15, height = 2, style = "minimal",
      })
    end,
    repeat_setup = function() orbit.setup(options); orbit.setup(options) end,
    exercise_maps = function()
      for _, old in ipairs(originals) do
        local maps = old.buffer and vim.api.nvim_buf_get_keymap(old.buffer, old.mode)
          or vim.api.nvim_get_keymap(old.mode)
        local called = false
        for _, map in ipairs(maps) do
          if vim.keycode(map.lhs) == vim.keycode(old.lhs) then
            local before = calls[old.id] or 0
            map.callback()
            assert(calls[old.id] == before + 1, "restored mapping is not callable")
            called = true
          end
        end
        assert(called, "restored mapping is missing")
      end
    end,
    replace_visual_escape = function()
      for _, old in ipairs(originals) do
        if old.buffer and old.mode == "x" and old.lhs == "<Esc>" then
          old.id = "user replacement"
          old.callback = function()
            calls[old.id] = (calls[old.id] or 0) + 1
            return "<Esc>"
          end
          vim.keymap.set("x", "<Esc>", old.callback, { buffer = old.buffer, expr = true, desc = old.id })
          for _, value in ipairs(vim.api.nvim_buf_get_keymap(old.buffer, "x")) do
            if vim.keycode(value.lhs) == vim.keycode(old.lhs) then old.mapping = value end
          end
        end
      end
    end,
    ---@return Orbit.LiveMenuSnapshot
    snapshot = function()
      local state = package.loaded["menu.state"]
      ---@type Orbit.LiveMenuWindow[]
      local menus = {}
      for _, buf in ipairs(state and state.bufids or {}) do
        if vim.api.nvim_buf_is_valid(buf) then
          local win = vim.fn.bufwinid(buf)
          local rows = {}
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
            if mark[4].virt_text then
              local text = {}
              for _, part in ipairs(mark[4].virt_text) do text[#text + 1] = part[1] end
              rows[mark[2] + 1] = (rows[mark[2] + 1] or "") .. table.concat(text)
            end
          end
          local positions = {}
          for row = 1, vim.api.nvim_buf_line_count(buf) do
            positions[row] = vim.fn.screenpos(win, row, 1)
          end
          menus[#menus + 1] = { buf = buf, win = win, rows = rows, positions = positions,
            origin = vim.api.nvim_win_get_position(win) }
        end
      end
      local preserved = true
      for _, old in ipairs(originals) do
        local maps = old.buffer and vim.api.nvim_buf_get_keymap(old.buffer, old.mode)
          or vim.api.nvim_get_keymap(old.mode)
        local found = false
        for _, map in ipairs(maps) do
          if vim.keycode(map.lhs) == vim.keycode(old.lhs) then
            found = vim.deep_equal(map, old.mapping)
          end
        end
        preserved = preserved and found
      end
      local windows = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do windows[#windows + 1] = win end
      return {
        menus = menus, loaded = loaded, errors = errors, errmsg = vim.v.errmsg,
        menu_loaded = package.loaded.menu ~= nil, tree_loaded = package.loaded["nvim-tree.api"] ~= nil,
        runtime_loaded = package.loaded["orbit.modules.menu.runtime"] ~= nil,
        current = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win(), mode = vim.fn.mode(),
        cursor = vim.api.nvim_win_get_cursor(0), windows = windows, preserved = preserved, calls = calls,
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false), mouse = vim.fn.getmousepos(), journal = journal,
      }
    end,
  }
end
