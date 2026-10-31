-- Test editor Lazy feature boundaries without downloading plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local editor = require("orbit.modules.editor_plugins")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("module import is inert before setup", function()
  assert(#editor.spec() == 0)
  assert(package.loaded.ibl == nil)
end)

check("default matchup and indentation declarations are lazy-owned", function()
  orbit.setup()
  local specs = editor.spec()
  assert(#specs == 2)
  assert(specs[1][1] == "andymass/vim-matchup")
  assert(specs[1].lazy == false)
  assert(specs[2][1] == "lukas-reineke/indent-blankline.nvim")
  assert(specs[2].event == "User FilePost" and specs[2].main == "ibl")
  assert(specs[2].opts.indent.char == "│")
  assert(specs[2].opts.scope.highlight == "IblScopeChar")
  assert(package.loaded.ibl == nil)
end)

check("matchup globals are applied only at the Lazy init boundary", function()
  local item = editor.spec()[1]
  assert(vim.g.matchup_treesitter_stopline == nil)
  item.init()
  assert(vim.g.matchup_treesitter_stopline == 500)
  assert(vim.g.matchup_matchparen_offscreen.method == "popup")
  assert(vim.g.matchup_matchparen_offscreen.fullwidth == 1)
end)

check("indent-blankline config registers whitespace hook then configures plugin", function()
  local registered, configured = 0, 0
  package.preload["ibl.hooks"] = function()
    return {
      type = { WHITESPACE = "WHITESPACE" },
      builtin = { hide_first_space_indent_level = function() end },
      register = function(kind, fn)
        assert(kind == "WHITESPACE" and type(fn) == "function")
        registered = registered + 1
      end,
    }
  end
  package.preload.ibl = function()
    return {
      setup = function(opts)
        assert(registered == 1)
        assert(opts.indent.char == "│")
        assert(opts.scope.char == "│")
        configured = configured + 1
      end,
    }
  end
  editor.spec()[2].config(nil, editor.spec()[2].opts)
  assert(configured == 1)
  package.loaded.ibl = nil
  package.loaded["ibl.hooks"] = nil
  package.preload.ibl = nil
  package.preload["ibl.hooks"] = nil
end)

check("configuration is validated and deferred after initial setup", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    editor_plugins = { matchup_stopline = -1 },
  } })
  assert(not ok and tostring(err):find("matchup_stopline", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))

  orbit.setup({ modules = { editor_plugins = { matchup = false } } })
  assert(orbit.get_config().modules.editor_plugins.matchup == true)
  assert(orbit.get_pending_restart()["orbit.modules.editor_plugins.matchup"] == false)
end)

check("disabling the module directly returns no plugin declarations", function()
  local before = editor.capture()
  editor.setup({ enabled = false })
  assert(#editor.spec() == 0)
  editor.restore(before)
  assert(#editor.spec() == 2)
end)

print(string.format("%d editor plugin tests passed.", passed))
