-- Theme shortcuts use runtime colorschemes and restore overwritten leader maps.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local count = 0

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  count = count + 1
  print("PASS " .. name)
end

local function mapping(lhs)
  return vim.fn.maparg(lhs, "n", false, true)
end

vim.keymap.set("n", " ut", "<cmd>echo 'old theme select'<cr>")
vim.keymap.set("n", " ur", "<cmd>echo 'old theme reload'<cr>")
vim.keymap.set("n", ",ut", "<cmd>echo 'comma select'<cr>")
vim.keymap.set("n", ",ur", "<cmd>echo 'comma reload'<cr>")
local old = {
  select = mapping(" ut").rhs, reload = mapping(" ur").rhs,
  comma_select = mapping(",ut").rhs, comma_reload = mapping(",ur").rhs,
}

check("startup never imports theme runtime or opens picker", function()
  orbit.setup()
  assert(package.loaded["orbit.modules.keymaps.theme"] == nil)
  assert(type(mapping(" ut").callback) == "function")
  assert(type(mapping(" ur").callback) == "function")
end)

check("theme selection lists installed schemes and applies a real default", function()
  local original = vim.ui.select
  local offered
  vim.ui.select = function(items, opts, callback)
    offered = { items = items, prompt = opts.prompt }
    callback("default")
  end
  local ok, err = pcall(function() mapping(" ut").callback() end)
  vim.ui.select = original
  assert(ok, tostring(err))
  assert(type(offered) == "table")
  assert(offered.prompt == "Select colorscheme")
  assert(vim.tbl_contains(offered.items, "default"))
  assert(vim.g.colors_name == "default")
end)

check("reloading the active colorscheme reports success", function()
  local original = vim.notify
  local notices = {}
  vim.notify = function(message, level)
    notices[#notices + 1] = { message, level }
  end
  local ok, err = pcall(function() mapping(" ur").callback() end)
  vim.notify = original
  assert(ok, tostring(err))
  assert(#notices == 1)
  assert(notices[1][1] == "Theme reloaded")
  assert(notices[1][2] == vim.log.levels.INFO)
  assert(vim.g.colors_name == "default")
end)

check("cancelled selection and invalid theme never replace accepted scheme", function()
  local original_select, original_notify = vim.ui.select, vim.notify
  local notices = {}
  vim.notify = function(msg, level)
    notices[#notices + 1] = { msg, level }
  end
  local choice
  vim.ui.select = function(_, _, callback) callback(choice) end
  local ok, err = xpcall(function()
    mapping(" ut").callback()
    assert(vim.g.colors_name == "default")
    choice = "orbit_nonexistent_colorscheme_2026"
    mapping(" ut").callback()
    assert(vim.g.colors_name == "default")
  end, debug.traceback)
  vim.ui.select, vim.notify = original_select, original_notify
  assert(ok, err)
  assert(#notices == 1 and notices[1][2] == vim.log.levels.WARN)
end)

check("leader changes preserve old mappings and reject reserved theme keys", function()
  orbit.setup({ modules = { keymaps = { leader = "," } } })
  assert(mapping(" ut").rhs == old.select)
  assert(mapping(" ur").rhs == old.reload)
  assert(type(mapping(",ut").callback) == "function")
  assert(type(mapping(",ur").callback) == "function")
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    keymaps = { leader = ",", save = "<leader>ur" },
  } })
  assert(not ok and tostring(err):find("duplicate leader mapping", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("downstream rollback and disable restore physical theme mappings", function()
  local accepted = orbit.get_config()
  local original = commands.setup
  commands.setup = function() error("injected theme mapping failure") end
  local ok, err = pcall(orbit.setup, { modules = {
    keymaps = { leader = ";" }, commands = { enabled = false },
  } })
  commands.setup = original
  assert(not ok and tostring(err):find("injected theme mapping failure", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  assert(type(mapping(",ur").callback) == "function")
  assert(mapping(" ut").rhs == old.select)
  assert(mapping(" ur").rhs == old.reload)

  orbit.setup({ modules = { keymaps = { enabled = false } } })
  assert(mapping(" ut").rhs == old.select)
  assert(mapping(" ur").rhs == old.reload)
  assert(mapping(",ut").rhs == old.comma_select)
  assert(mapping(",ur").rhs == old.comma_reload)
end)

print(string.format("%d native theme mapping tests passed.", count))
