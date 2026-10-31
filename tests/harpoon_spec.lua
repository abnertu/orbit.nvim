-- Harpoon callbacks and UI item context with no external downloads.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local navigation = require("orbit.modules.navigation")
local runtime = require("orbit.modules.navigation.harpoon")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("Harpoon import is inert and keeps the legacy navigation keys", function()
  assert(#navigation.spec() == 0)
  orbit.setup()
  local list = navigation.spec()
  assert(#list == 3)
  local item = list[3]
  assert(item[1] == "Orbit-Lua/harpoon" and item.branch == "harpoon2")
  assert(item.dependencies[1] == "nvim-lua/plenary.nvim")
  assert(vim.deep_equal(vim.tbl_map(function(key) return key[1] end, item.keys),
    { "<C-e>", "<M-S-p>", "<M-S-n>", "<leader>ba" }))
  assert(package.loaded.harpoon == nil)
end)

local count = { menu = 0, prev = 0, next = 0, add = 0, setup = 0, extend = 0 }
local config, extension
local collection = {
  prev = function() count.prev = count.prev + 1 end,
  next = function() count.next = count.next + 1 end,
  add = function() count.add = count.add + 1 end,
}
local harpoon = {
  ui = {
    toggle_quick_menu = function(_, selected)
      assert(selected == collection)
      count.menu = count.menu + 1
    end,
  },
  list = function() return collection end,
  setup = function(_, opts)
    config = opts
    count.setup = count.setup + 1
  end,
  extend = function(_, opts)
    extension = opts
    count.extend = count.extend + 1
  end,
}
package.preload.harpoon = function() return harpoon end

check("Harpoon invokes plugin only when a Lazy callback runs", function()
  local item = navigation.spec()[3]
  for _, key in ipairs(item.keys) do key[2]() end
  assert(count.menu == 1 and count.prev == 1 and
    count.next == 1 and count.add == 1)
  assert(count.setup == 0 and count.extend == 0)
  item.config()
  item.config()
  assert(count.setup == 1 and count.extend == 1)
  assert(type(config.default.create_list_item) == "function")
  assert(type(config.default.display) == "function")
  assert(type(extension.UI_CREATE) == "function")
end)

check("list items retain path, cursor and shortened display context", function()
  local item = config.default.create_list_item({
    get_root_dir = function() return vim.fn.getcwd() end,
  }, "src/modules/very/long/relative/sample.lua")
  assert(item.value == "src/modules/very/long/relative/sample.lua")
  assert(item.context.row == 1 and item.context.col == 0)
  assert(item.context.short_path:find("sample.lua", 1, true))
  assert(config.default.display(item):find("sample.lua", 1, true))
  assert(runtime.pretty_path("a/b/c/d.lua", 2) == "a/…/d.lua")
  assert(runtime.pretty_path("a/b/c/d.lua", 1) == "d.lua",
    "a single segment must keep the filename")
  assert(runtime.pretty_path("", 8) == "")
end)

check("filesystem roots shorten absolute paths without losing the first segment", function()
  local drive = vim.fn.getcwd():match("^%a:")
  local filesystem_root = drive and (drive .. "/") or "/"
  local path = vim.fs.joinpath(filesystem_root, "alpha", "beta.lua")
  assert(runtime.pretty_path(path, 8, filesystem_root) == "alpha/beta.lua",
    "filesystem root must not leave an absolute path in the display")
  local sibling_root = vim.fs.joinpath(filesystem_root, "alph")
  assert(runtime.pretty_path(path, 8, sibling_root) ==
    runtime.pretty_path(path, 8), "unrelated root must not strip a prefix")
end)

check("UI_CREATE highlights only the exact current-file display row", function()
  -- Harpoon UI_CREATE.contents comes from HarpoonList:display(), including
  -- the same icon and padding as the popup buffer.
  local shorter = runtime.format_display("src/other.lua")
  local current = runtime.format_display("src/other.lua.backup.lua")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { shorter, current })
  local win = vim.api.nvim_get_current_win()
  local previous = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_buf(win, buf)
  extension.UI_CREATE({
    current_file = "src/other.lua.backup.lua",
    contents = { shorter, current },
    bufnr = buf, win_id = win,
  })
  local marks = vim.api.nvim_buf_get_extmarks(
    buf, vim.api.nvim_get_namespaces()["orbit.harpoon"], 0, -1, {
      details = true,
    })
  assert(#marks == 1 and marks[1][2] == 1,
    "a shorter filename prefix must not also be highlighted")
  assert(marks[1][4].hl_group == "active_context")
  assert(vim.api.nvim_win_get_cursor(win)[1] == 2)
  vim.api.nvim_win_set_buf(win, previous)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

check("bad path-length options do not alter accepted settings", function()
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    navigation = { harpoon_short_path_length = 0 },
  } })
  assert(not ok and tostring(err):find("harpoon_short_path_length", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
  orbit.setup({ modules = { navigation = { harpoon = false } } })
  assert(orbit.get_config().modules.navigation.harpoon)
  assert(orbit.get_pending_restart()["orbit.modules.navigation.harpoon"] == false)
end)

package.loaded.harpoon, package.preload.harpoon = nil, nil
print(string.format("%d Harpoon navigation tests passed.", passed))
