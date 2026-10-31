-- Verify manifest-owned which-key behavior without importing upstream plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local guide = require("orbit.modules.keyguide")
local passed = 0

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("manifest setup does not import which-key", function()
  assert(#guide.spec() == 0)
  orbit.setup()
  assert(package.loaded["which-key"] == nil)
  local spec = guide.spec()[1]
  assert(spec and spec[1] == "folke/which-key.nvim")
  assert(spec.event == "VeryLazy" and spec.cmd == "WhichKey")
  assert(spec.opts.preset == "helix")
  assert(spec.opts.win.border == "rounded")
  assert(#spec.opts.spec == 10)
  assert(spec.opts.spec[1][1] == "<leader>b")
  assert(spec.opts.spec[#spec.opts.spec].group == "whichkey")
  assert(spec.keys[1][1] == "<leader>wK")
  assert(spec.keys[2][1] == "<leader>wk")
  assert(type(spec.keys[2][2]) == "function")
end)

check("configuration callback is the only external import boundary", function()
  local calls = 0
  package.preload["which-key"] = function()
    return { setup = function(opts)
      calls = calls + 1
      assert(opts.preset == "helix")
      assert(opts.win.border == "rounded")
      assert(#opts.spec == 10)
    end }
  end
  local spec = guide.spec()[1]
  spec.config(nil, spec.opts)
  assert(calls == 1)
  package.loaded["which-key"] = nil
  package.preload["which-key"] = nil
end)

check("query key sends a single safe Ex argument and ignores cancellation", function()
  local input, command = vim.fn.input, vim.api.nvim_cmd
  local received, called
  vim.fn.input = function(prompt)
    assert(prompt == "WhichKey: ")
    return "n <leader>b | quit!"
  end
  vim.api.nvim_cmd = function(args, opts)
    received = args
    assert(vim.deep_equal(opts, {}))
  end
  local ok, err = xpcall(function()
    guide.spec()[1].keys[2][2]()
    assert(received and received.cmd == "WhichKey")
    assert(vim.deep_equal(received.args, { "n <leader>b | quit!" }))
    vim.fn.input = function() return "" end
    received = nil
    guide.query()
    assert(received == nil)
  end, debug.traceback)
  vim.fn.input, vim.api.nvim_cmd = input, command
  assert(ok, err)
end)

check("disabled owner and snapshot restore preserve specification", function()
  local snapshot = guide.capture()
  guide.setup({ enabled = false })
  assert(#guide.spec() == 0)
  guide.restore(snapshot)
  assert(#guide.spec() == 1)
  assert(guide.spec()[1].opts.preset == "helix")
end)

check("invalid owner metadata is rejected", function()
  local ok, err = pcall(guide.setup, { preset = "invalid" })
  assert(not ok and tostring(err):find("preset", 1, true), tostring(err))
  assert(#guide.spec() == 1)
end)

print(string.format("%d which-key guide tests passed.", passed))
