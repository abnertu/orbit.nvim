-- Verify the dotnet-cli owner declaration, settings and DAP delegation.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.dotnet")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("default spec declares every .NET entry point without loading it", function()
  assert(#feature.spec() == 0)
  orbit.setup()
  local spec = feature.spec()[1]
  assert(spec[1] == "Orbit-Lua/dotnet-cli.nvim")
  assert(spec.dependencies[1] == "Orbit-Lua/comet.nvim")
  assert(vim.deep_equal(spec.cmd, {
    "DotnetManager", "DotnetBuild", "DotnetPublish",
    "DotnetGlobalJson", "DotnetDebug", "DotnetAttach",
  }))
  assert(spec.ft == "cs")
  assert(spec.keys[1][1] == "<leader>ud" and spec.keys[1][2] == "<cmd>DotnetManager<CR>")
  assert(package.loaded["dotnet-cli"] == nil)
end)

check("bundled spec import collects the dotnet owner", function()
  local found = false
  for _, item in ipairs(require("orbit.plugins")) do
    if item[1] == "Orbit-Lua/dotnet-cli.nvim" then found = true end
  end
  assert(found, "orbit.plugins must include dotnet-cli")
end)

check("CoreCLR registration delegates to dotnet-cli", function()
  local calls = 0
  package.loaded["dotnet-cli"] = { setup_dap = function() calls = calls + 1; return true end }
  local ok = require("orbit.modules.dap.runtime").apply_adapter({}, "coreclr", true, {})
  package.loaded["dotnet-cli"] = nil
  assert(ok and calls == 1)
end)

check("invalid manager keys are rejected and options are restart-only", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = { dotnet = { manager_key = "" } } })
  assert(not ok and tostring(err):find("manager_key", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  orbit.setup({ modules = { dotnet = { enabled = false } } })
  assert(#feature.spec() == 1, "enabled is restart-only")
  assert(orbit.get_pending_restart()["orbit.modules.dotnet.enabled"] == false)
end)

check("manager open applies floating-window colors after Comet creates its panels", function()
  local panels = {}
  local configured = 0
  local dotnet = {
    setup = function() configured = configured + 1 end,
    open = function()
      for index = 1, 3 do
        local buffer = vim.api.nvim_create_buf(false, true)
        panels[index] = vim.api.nvim_open_win(buffer, false, {
          relative = "editor", row = index, col = index, width = 10, height = 2, border = "rounded",
        })
        vim.wo[panels[index]].winhighlight = "Normal:ExBlack2Bg,FloatBorder:ExBlack2Border"
      end
    end,
  }
  package.loaded["dotnet-cli"] = dotnet
  package.loaded["comet.state"] = {
    is_open = function() return true end,
    get = function() return { input_win = panels[1], list_win = panels[2], output_win = panels[3] } end,
  }
  local item = feature.spec()[1]
  item.config(item, item.opts)
  local open = dotnet.open
  item.config(item, item.opts)
  assert(configured == 1 and dotnet.open == open, "repeated activation reconfigured or wrapped Dotnet twice")
  dotnet.open()
  for _, window in ipairs(panels) do
    assert(vim.wo[window].winhighlight:find("Normal:NormalFloat", 1, true))
    assert(vim.wo[window].winhighlight:find("FloatBorder:FloatBorder", 1, true))
    vim.api.nvim_win_close(window, true)
  end
  package.loaded["dotnet-cli"], package.loaded["comet.state"] = nil, nil
end)

check("a disabled owner contributes no spec", function()
  feature.setup({ enabled = false })
  assert(#feature.spec() == 0)
end)

print(string.format("%d dotnet tests passed.", passed))
