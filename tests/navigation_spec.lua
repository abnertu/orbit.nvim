local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.navigation")
local passed = 0
local function check(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("import is inert and options keep their defaults", function()
  assert(#feature.spec() == 0)
  orbit.setup()
  local specs = feature.spec()
  assert(#specs == 3)
  assert(specs[3][1] == "Orbit-Lua/harpoon")
  assert(specs[3].branch == "harpoon2")
  assert(specs[1][1] == "stevearc/oil.nvim")
  assert(specs[1].opts.default_file_explorer == false)
  assert(specs[1].opts.delete_to_trash)
  assert(specs[1].opts.keymaps["<C-h>"] == false)
  assert(specs[1].opts.keymaps["s"][1] == "<cmd>write<CR>")
  assert(specs[2][1] == "nvim-tree/nvim-tree.lua")
  assert(specs[2].opts.view.width == 40)
  assert(specs[2].opts.filesystem_watchers.enable == (vim.fn.has("win32") ~= 1))
  assert(specs[2].opts.reload_on_bufenter == (vim.fn.has("win32") == 1))
end)

check("Oil callback resolves plugin only on demand", function()
  local called = 0
  package.preload.oil = function()
    return { toggle_float = function(_, options)
      assert(vim.deep_equal(options, { preview = {} }))
      called = called + 1
    end }
  end
  feature.spec()[1].keys[1][2]()
  assert(called == 1)
  package.loaded.oil, package.preload.oil = nil, nil
end)

check("tree FileCreated callback relays one CreateFile event", function()
  local subscribers, setup_count, fired = {}, 0, 0
  package.preload["nvim-tree"] = function()
    return { setup = function(opts)
      assert(opts.view.width == 40)
      setup_count = setup_count + 1
    end }
  end
  package.preload["nvim-tree.api"] = function()
    return {
      fs = { create = function() end },
      events = {
        Event = { FileCreated = "created" },
        subscribe = function(name, cb)
          assert(name == "created")
          subscribers[#subscribers + 1] = cb
        end,
      },
    }
  end
  local group = vim.api.nvim_create_augroup("OrbitTestCreateFile", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "CreateFile",
    callback = function() fired = fired + 1 end })
  local spec = feature.spec()[2]
  spec.config(nil, spec.opts)
  spec.config(nil, spec.opts)
  assert(setup_count == 2 and #subscribers == 1)
  subscribers[1]()
  assert(fired == 1)
  vim.api.nvim_del_augroup_by_id(group)
  package.loaded["nvim-tree"], package.preload["nvim-tree"] = nil, nil
  package.loaded["nvim-tree.api"], package.preload["nvim-tree.api"] = nil, nil
end)

check("restart-only options and invalid widths preserve accepted state", function()
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = { navigation = { tree_width = 5 } } })
  assert(not ok and tostring(err):find("tree_width", 1, true))
  assert(vim.deep_equal(before, orbit.get_config()))
  orbit.setup({ modules = { navigation = { tree = false } } })
  assert(orbit.get_config().modules.navigation.tree)
  assert(orbit.get_pending_restart()["orbit.modules.navigation.tree"] == false)
end)

print(string.format("%d navigation tests passed.", passed))
