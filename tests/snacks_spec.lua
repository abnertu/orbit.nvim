-- Verify Snacks feature behavior without downloading upstream plugin code.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.snacks")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end
local function key(keys, lhs)
  for _, entry in ipairs(keys) do
    if entry[1] == lhs then return entry end
  end
  error("missing Snacks key " .. lhs)
end

check("spec imports are inert before setup", function()
  assert(#feature.spec() == 0)
  assert(package.loaded.snacks == nil)
end)

check("legacy picker and UI defaults are configured", function()
  orbit.setup()
  local spec = feature.spec()
  assert(#spec == 1 and spec[1][1] == "folke/snacks.nvim")
  assert(spec[1].lazy == false and spec[1].priority == 1000)
  local opts = spec[1].opts
  assert(opts.picker.sources.files.hidden and opts.picker.sources.grep.hidden)
  assert(opts.statuscolumn.left[1] == "mark" and opts.statuscolumn.refresh == 50)
  assert(opts.notifier.timeout == 3000 and opts.bigfile.enabled)
  assert(#spec[1].keys >= 30)
  for _, lhs in ipairs({ "<leader>ff", "<leader>sg", "<leader>bd", "<leader>gg" }) do
    assert(type(key(spec[1].keys, lhs)[2]) == "function")
  end
  assert(package.loaded.snacks == nil)
end)

check("picker and buffer commands resolve only at the Lazy callback boundary", function()
  local calls = {}
  package.preload.snacks = function()
    return {
      picker = {
        files = function() calls[#calls + 1] = "files" end,
        grep = function() calls[#calls + 1] = "grep" end,
      },
      bufdelete = function() calls[#calls + 1] = "bufdelete" end,
    }
  end
  local keys = feature.spec()[1].keys
  key(keys, "<leader>ff")[2]()
  key(keys, "<leader>sg")[2]()
  key(keys, "<leader>bd")[2]()
  assert(vim.deep_equal(calls, { "files", "grep", "bufdelete" }))
  package.loaded.snacks, package.preload.snacks = nil, nil
end)

check("redraw suppression is narrow and installed once", function()
  local count, setups = 0, 0
  package.preload.snacks = function()
    return {
      util = { redraw_range = function(v)
        count = count + 1
        if v == 1 then error("Invalid window id: 14") end
        if v == 2 then error("bad redraw") end
      end },
      setup = function(opts)
        assert(opts.statuscolumn.refresh == 50)
        setups = setups + 1
      end,
    }
  end
  local item = feature.spec()[1]
  item.config(nil, item.opts)
  item.config(nil, item.opts)
  assert(setups == 2)
  local snacks = require("snacks")
  snacks.util.redraw_range(1)
  assert(count == 1)
  local ok, err = pcall(snacks.util.redraw_range, 2)
  assert(not ok and tostring(err):find("Snacks redraw failed", 1, true))
  assert(count == 2)
  package.loaded.snacks, package.preload.snacks = nil, nil
end)

check("invalid schema values are rejected before restart deferral", function()
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, {
    modules = { snacks = { notify_timeout = -1 } },
  })
  assert(not ok and tostring(err):find("notify_timeout", 1, true))
  assert(vim.deep_equal(before, orbit.get_config()))
  orbit.setup({ modules = { snacks = { picker = false } } })
  assert(orbit.get_pending_restart()["orbit.modules.snacks.picker"] == false)
  assert(orbit.get_config().modules.snacks.picker == true)
end)

print(string.format("%d Snacks tests passed.", passed))
