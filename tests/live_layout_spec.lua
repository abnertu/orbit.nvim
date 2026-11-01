-- Exercise pinned Edgy with real Trouble views through the layout owner.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local pins = {
  { "https://github.com/folke/edgy.nvim.git", "8bfd2808994a988c975694122f68624b8a219f5f" },
  { "https://github.com/folke/trouble.nvim.git", "748ca2789044607f19786b1d837044544c55e80a" },
}
local base = vim.fn.tempname() .. " live layout with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

local function managed(win)
  local item = require("edgy.editor").get_win(win)
  return item and item.view.edgebar.pos or nil
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  for index, pin in ipairs(pins) do
    local directory = base .. "/" .. index
    assert(vim.fn.mkdir(directory, "p") == 1)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1", pin[1], pin[2] })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pin[2],
      "upstream revision mismatch: " .. pin[1])
    vim.opt.rtp:prepend(directory)
  end
  vim.o.laststatus = 3
  vim.o.splitkeep = "screen"

  local orbit = require("orbit")
  orbit.setup()
  assert(package.loaded.edgy == nil, "root setup imported Edgy before Lazy activation")
  local layout = require("orbit.modules.layout").spec()[1]
  require("trouble").setup(require("orbit.modules.diagnostics_plugins").spec()[1].opts)
  require("edgy").setup(layout.opts())

  local main = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local unrelated = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(main)
  local buffer = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace("orbit.live.layout")
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "local value = 1" })
  vim.diagnostic.set(ns, buffer, {
    { lnum = 0, col = 0, message = "live layout diagnostic",
      severity = vim.diagnostic.severity.WARN },
  })

  local trouble = require("trouble")
  for _, pos in ipairs({ "right", "bottom" }) do
    local view = trouble.open({
      mode = "diagnostics", new = true, focus = false, auto_preview = false,
      win = { position = pos, type = "split", relative = "editor" },
    })
    assert(vim.wait(10000, function()
      return view.win and view.win.win and vim.api.nvim_win_is_valid(view.win.win)
        and managed(view.win.win) == pos
    end, 50), "Edgy did not place the " .. pos .. " Trouble view")
    assert(managed(unrelated) == nil and managed(main) == nil,
      "Edgy captured an unrelated window")
    trouble.close("diagnostics")
    assert(vim.wait(10000, function() return not trouble.is_open("diagnostics") end, 50))
    print("PASS real Edgy places the " .. pos .. " Trouble view")
  end

  local view = trouble.open({
    mode = "diagnostics", new = true, focus = false, auto_preview = false,
    win = { position = "right", type = "split", relative = "editor" },
  })
  assert(vim.wait(10000, function() return view.win.win and managed(view.win.win) end, 50))
  layout.keys[1][2]()
  assert(vim.wait(10000, function()
    return not (view.win.win and vim.api.nvim_win_is_valid(view.win.win))
  end, 50), "toggle key did not close the side layout")
  assert(vim.api.nvim_win_is_valid(main) and vim.api.nvim_win_is_valid(unrelated))
  print("PASS layout toggle key closes only the side layout")
  vim.diagnostic.reset(ns, buffer)
end, debug.traceback)

vim.fn.delete(base, "rf")
assert(ok, tostring(err))
print("Pinned upstream Edgy layout integration tests passed.")
