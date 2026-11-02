-- Verify public diagnostic callback boundaries without fetching plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local diagnostics = require("orbit.modules.diagnostics_plugins")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("import is inert", function()
  assert(#diagnostics.spec() == 0)
  assert(package.loaded.trouble == nil)
end)

check("commands, keys, preview and TODO glyph are configured", function()
  orbit.setup()
  local items = diagnostics.spec()
  assert(#items == 2)
  assert(items[1][1] == "folke/trouble.nvim" and items[1].cmd == "Trouble")
  assert(#items[1].keys == 6)
  assert(items[1].keys[4][1] == "<leader>cL")
  local p = items[1].opts.modes.diagnostic_preview_float.preview
  assert(p.border == "rounded" and p.size.width == 0.3 and p.zindex == 200)
  assert(items[2][1] == "folke/todo-comments.nvim")
  assert(items[2].event == "User FilePost")
  assert(items[2].dependencies[1] == "nvim-lua/plenary.nvim")
  assert(items[2].opts.keywords.WORKAROUND.icon == " ")
  assert(package.loaded["todo-comments"] == nil)
end)

check("Trouble LSP references close and reopen with stable options", function()
  local order = {}
  package.preload.trouble = function()
    return {
      close = function(o)
        assert(o.mode == "lsp")
        order[#order + 1] = "close"
      end,
      open = function(o)
        assert(o.mode == "lsp" and o.auto_refresh == false)
        assert(o.win.position == "right" and o.focus == false)
        order[#order + 1] = "open"
      end,
    }
  end
  diagnostics.spec()[1].keys[4][2]()
  assert(vim.deep_equal(order, { "close", "open" }))
  package.loaded.trouble = nil
  package.preload.trouble = nil
end)

check("TODO shortcuts and setup invoke their owned plugin APIs", function()
  local picked, configured = {}, 0
  package.preload.snacks = function()
    return { picker = { todo_comments = function(opts)
      picked[#picked + 1] = opts or {}
    end } }
  end
  package.preload["todo-comments"] = function()
    return { setup = function(opts)
      assert(opts.keywords.WORKAROUND.color == "warning")
      configured = configured + 1
    end }
  end
  local todo = diagnostics.spec()[2]
  todo.keys[1][2]()
  todo.keys[2][2]()
  todo.config(nil, todo.opts)
  assert(#picked == 2 and configured == 1)
  assert(vim.deep_equal(picked[2].keywords, { "TODO", "FIX", "FIXME", "WORKAROUND" }))
  package.loaded.snacks, package.preload.snacks = nil, nil
  package.loaded["todo-comments"], package.preload["todo-comments"] = nil, nil
end)

check("invalid size is rejected without replacing configuration", function()
  local previous = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    diagnostics_plugins = { preview_width_percent = 200 },
  } })
  assert(not ok and tostring(err):find("preview_width_percent", 1, true))
  assert(vim.deep_equal(previous, orbit.get_config()))
end)

check("plugin options changed later require restart", function()
  orbit.setup({ modules = { diagnostics_plugins = { trouble = false } } })
  assert(orbit.get_config().modules.diagnostics_plugins.trouble)
  assert(orbit.get_pending_restart()["orbit.modules.diagnostics_plugins.trouble"] == false)
end)

print(string.format("%d diagnostics plugin tests passed.", passed))
