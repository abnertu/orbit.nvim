-- Exercise actual pinned Trouble diagnostics and custom view configuration.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local pinned = "748ca2789044607f19786b1d837044544c55e80a"
local upstream = "https://github.com/folke/trouble.nvim.git"
local directory = vim.fn.tempname() .. " live Trouble with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1", upstream, pinned })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pinned,
    "upstream Trouble revision mismatch")
  vim.opt.rtp:prepend(directory)

  local orbit = require("orbit")
  local diagnostics = require("orbit.modules.diagnostics_plugins")
  orbit.setup()
  assert(package.loaded.trouble == nil,
    "root setup imported Trouble before Lazy activation")
  local spec = diagnostics.spec()[1]
  assert(spec and spec[1] == "folke/trouble.nvim")
  assert(spec.cmd == "Trouble")
  local trouble = require("trouble")
  trouble.setup(spec.opts)
  assert(vim.api.nvim_get_commands({}).Trouble ~= nil,
    "real Trouble command registration missing")

  local custom = require("trouble.config").get("diagnostic_preview_float")
  assert(custom.mode == "diagnostics")
  assert(custom.preview.type == "float")
  assert(custom.preview.border == "rounded")
  assert(custom.preview.size.width == 0.3)
  print("PASS real Trouble configuration and custom diagnostic preview mode")

  local buffer = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace("orbit.live.trouble")
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "local value = 1" })
  vim.diagnostic.set(ns, buffer, {
    { lnum = 0, col = 0, message = "live Trouble diagnostic",
      severity = vim.diagnostic.severity.WARN },
  })
  local view = trouble.open({
    mode = "diagnostics", focus = false, auto_preview = false,
    win = { position = "bottom" },
  })
  assert(view and trouble.is_open("diagnostics"),
    "real Trouble diagnostics view did not open")
  assert(vim.wait(10000, function()
    for _, item in ipairs(trouble.get_items("diagnostics")) do
      if item.message == "live Trouble diagnostic" then return true end
    end
    return false
  end, 50), "real Trouble did not consume a Neovim diagnostic")
  trouble.close("diagnostics")
  assert(not trouble.is_open("diagnostics"),
    "Trouble diagnostics view stayed open after close")
  vim.diagnostic.reset(ns, buffer)
  print("PASS real Trouble diagnostic source, view and close lifecycle")
end, debug.traceback)

vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned upstream Trouble integration tests passed.")
