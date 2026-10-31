-- Real upstream GitSigns attach test, not a mock of the plugin API.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local pinned = "1e9d0fbfe7ff848bc402d2c2e2854fb4eff2dce7"
local plugin_source = "https://github.com/lewis6991/gitsigns.nvim.git"
local directory = vim.fn.tempname() .. " live gitsigns plugin"
local project = vim.fn.tempname() .. " live gitsigns fixture"
local cwd = vim.fn.getcwd()

local function run(argv)
  local result = vim.system(argv, {
    text = true, timeout = 120000,
  }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(directory, "p") == 1)
  assert(vim.fn.mkdir(project, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1",
    plugin_source, pinned })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  local revision = run({ "git", "-C", directory, "rev-parse", "HEAD" })
    :gsub("%s+$", "")
  assert(revision == pinned, "upstream gitsigns revision mismatch")

  vim.opt.rtp:prepend(directory)
  local orbit = require("orbit")
  orbit.setup({ modules = { git = { enabled = true } } })
  assert(package.loaded.gitsigns == nil,
    "runtime imported gitsigns during configuration setup")

  local git_owner = require("orbit.modules.git")
  local spec = git_owner.spec()[1]
  assert(spec[1] == "lewis6991/gitsigns.nvim")
  assert(spec.event == "User FilePost")
  assert(spec.opts.signs.add.text == "▎")
  assert(spec.opts.signs_staged.add.text == " ")

  -- Exercise GitSigns against a real tracked file and its .git metadata.
  run({ "git", "init", project })
  local filename = project .. "/tracked.lua"
  assert(vim.fn.writefile({ "local value = 1" }, filename) == 0)
  run({ "git", "-C", project, "add", "tracked.lua" })
  run({ "git", "-C", project, "-c", "user.name=Orbit Test",
    "-c", "user.email=test@example.invalid", "commit", "-m", "fixture" })
  vim.api.nvim_set_current_dir(project)
  vim.cmd.edit({ args = { filename } })
  local buffer = vim.api.nvim_get_current_buf()
  require("gitsigns").setup(spec.opts)
  assert(type(vim.api.nvim_get_commands({}).Gitsigns) == "table",
    "real gitsigns command registration missing")

  local attached = vim.wait(10000, function()
    return vim.b[buffer].gitsigns_status_dict ~= nil
  end, 50)
  assert(attached, "real gitsigns did not attach to a tracked file")
  print("PASS pinned real gitsigns setup and tracked-file attachment")

  vim.api.nvim_buf_set_lines(buffer, 0, 1, false,
    { "local value = 2" })
  vim.api.nvim_exec_autocmds("TextChanged", {
    buffer = buffer, modeline = false,
  })
  assert(vim.wait(10000, function()
    local status = vim.b[buffer].gitsigns_status_dict
    return type(status) == "table"
      and ((status.changed or 0) + (status.added or 0)
        + (status.removed or 0)) > 0
  end, 50), "real gitsigns did not detect the modified hunk")
  print("PASS real tracked-file change detection")
  assert(vim.api.nvim_buf_is_valid(buffer))
  print("Pinned upstream revision: " .. pinned)
end, debug.traceback)

vim.api.nvim_set_current_dir(cwd)
vim.fn.delete(directory, "rf")
vim.fn.delete(project, "rf")
assert(ok, tostring(err))
print("Live gitsigns integration tests passed.")
