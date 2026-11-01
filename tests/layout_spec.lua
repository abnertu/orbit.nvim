-- Verify the Edgy layout owner and its Trouble window filters.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.layout")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("default spec declares toggle and select keys without loading Edgy", function()
  assert(#feature.spec() == 0)
  orbit.setup()
  local spec = feature.spec()[1]
  assert(spec[1] == "folke/edgy.nvim" and spec.event == "VeryLazy")
  assert(spec.keys[1][1] == "<leader>ue" and spec.keys[2][1] == "<leader>uE")
  local calls = {}
  package.loaded.edgy = {
    toggle = function() calls[#calls + 1] = "toggle" end,
    select = function() calls[#calls + 1] = "select" end,
  }
  spec.keys[1][2]()
  spec.keys[2][2]()
  package.loaded.edgy = nil
  assert(vim.deep_equal(calls, { "toggle", "select" }))
  local opts = spec.opts()
  assert(opts.animate.enabled == false)
  assert(opts.right[1].size.width == 0.3 and opts.bottom[1].size.height == 0.3)
end)

check("each side captures only its editor-relative Trouble split", function()
  local opts = feature.spec()[1].opts()
  local win = vim.api.nvim_get_current_win()
  local function accepted_by()
    local sides = {}
    for _, pos in ipairs({ "top", "bottom", "left", "right" }) do
      if opts[pos][1].filter(0, win) then sides[#sides + 1] = pos end
    end
    return sides
  end
  assert(#accepted_by() == 0, "plain windows must stay unmanaged")
  vim.w[win].trouble = { position = "right", type = "split", relative = "editor" }
  assert(vim.deep_equal(accepted_by(), { "right" }))
  vim.w[win].trouble = { position = "right", type = "split", relative = "win" }
  assert(#accepted_by() == 0, "window-relative Trouble must stay in place")
  vim.w[win].trouble = { position = "bottom", type = "float", relative = "editor" }
  assert(#accepted_by() == 0, "floating Trouble must stay unmanaged")
  vim.w[win].trouble = { position = "left", type = "split", relative = "editor" }
  vim.w[win].trouble_preview = true
  assert(#accepted_by() == 0, "Trouble previews must stay unmanaged")
  vim.w[win].trouble, vim.w[win].trouble_preview = nil, nil
end)

check("custom size and keys are validated and restart-only", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = { layout = { size_percent = 95 } } })
  assert(not ok and tostring(err):find("size_percent", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  feature.setup({ size_percent = 40, toggle_key = "<leader>lt" })
  local spec = feature.spec()[1]
  assert(spec.keys[1][1] == "<leader>lt")
  assert(spec.opts().left[1].size.width == 0.4)
  feature.setup({ enabled = false })
  assert(#feature.spec() == 0)
end)

print(string.format("%d layout tests passed.", passed))
