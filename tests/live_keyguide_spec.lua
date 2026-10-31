-- Exercise the pinned upstream which-key config and command, not a mock.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local revision = "fcbf4eea17cb299c02557d576f0d568878e354a4"
local source = "https://github.com/folke/which-key.nvim.git"
local directory = vim.fn.tempname() .. " live which key with spaces"

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
  run({ "git", "-C", directory, "fetch", "--depth", "1", source, revision })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == revision)
  vim.opt.rtp:prepend(directory)

  local orbit = require("orbit")
  local guide = require("orbit.modules.keyguide")
  orbit.setup()
  assert(package.loaded["which-key"] == nil, "which-key loaded before Lazy")
  local spec = guide.spec()[1]
  assert(spec and spec[1] == "folke/which-key.nvim")
  spec.config(spec, spec.opts)
  local wk = require("which-key")
  local cfg = require("which-key.config")
  assert(wk.did_setup, "upstream which-key setup was not invoked")
  assert(cfg.version == "3.17.0")
  assert(cfg.options.preset == "helix")
  assert(cfg.options.win.border == "rounded")
  assert(#cfg.options.spec == 10)
  assert(vim.api.nvim_get_commands({}).WhichKey ~= nil,
    "real which-key command was not registered")
  -- The upstream config owns command parsing and mapping registration.
  vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
  assert(vim.wait(5000, function() return cfg.loaded end, 20),
    "real which-key startup did not finish")
  local registered = {}
  for _, mapping in ipairs(cfg.mappings) do
    if mapping.group then registered[mapping.lhs] = mapping.group end
  end
  assert(next(registered) ~= nil, "which-key group mappings were not registered")
  print("PASS real which-key setup, group registration and Ex command")
end, debug.traceback)

vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned upstream which-key integration tests passed.")
