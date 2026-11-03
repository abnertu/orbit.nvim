-- An attached UI starts installed Lazy during setup; a missing checkout waits for demand.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

if arg[1] ~= "child" then
  for _, case in ipairs({ "installed", "missing" }) do
    local result = vim
      .system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", arg[0], "child", case }, {
        text = true,
        timeout = 30000,
      })
      :wait()
    assert(result.code == 0, case .. ": " .. tostring(result.stderr) .. tostring(result.stdout))
    io.write(result.stdout)
  end
  return
end

local case = arg[2]
vim.opt.rtp:prepend(root)
local path = vim.fn.tempname()
if case == "installed" then
  vim.fn.mkdir(path, "p")
end
local started = 0
package.preload.lazy = function()
  return {
    setup = function()
      started = started + 1
    end,
  }
end
-- Headless tests have no UI; a terminal UI attaches before init runs.
vim.api.nvim_list_uis = function()
  return { { chan = 1, width = 80, height = 24 } }
end

require("orbit").setup({
  modules = { plugins = { enabled = true, bootstrap = true, path = path } },
})
local status = require("orbit.modules.plugins").status()
if case == "installed" then
  assert(started == 1 and status == "loaded", "attached UI did not start installed Lazy")
  print("PASS attached UI starts installed Lazy during setup")
else
  assert(started == 0 and status == "pending", "attached UI bootstrapped Lazy before demand")
  print("PASS attached UI leaves a missing Lazy checkout for first demand")
end
