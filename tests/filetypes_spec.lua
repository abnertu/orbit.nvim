-- Verify owner-scoped Compose / JSX filetype registration and rollback.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local keymaps = require("orbit.modules.keymaps")
local count = 0

local function match(name)
  return vim.filetype.match({ filename = vim.fn.fnamemodify(name, ":p") })
end

local original = {
  compose = match("compose.yaml"),
  docker = match("docker-compose.yml"),
  jsx = match("example.jsx"),
}

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  count = count + 1
  print("PASS " .. name)
end

check("legacy Compose and JSX rules are configurable", function()
  orbit.setup()
  assert(match("compose.yaml") == "yaml.docker-compose")
  assert(match("compose.yml") == "yaml.docker-compose")
  assert(match("docker-compose.yaml") == "yaml.docker-compose")
  assert(match("docker-compose.yml") == "yaml.docker-compose")
  assert(match("example.jsx") == "jsx")
end)

check("custom filetypes are applied and validated", function()
  orbit.setup({ modules = { filetypes = { compose = "yaml.custom", jsx = "javascriptreact" } } })
  assert(match("compose.yaml") == "yaml.custom")
  assert(match("example.jsx") == "javascriptreact")
  assert(orbit.get_config().modules.filetypes.compose == "yaml.custom")
  local accepted = orbit.get_config()
  local ok = pcall(orbit.setup, { modules = { filetypes = { jsx = "" } } })
  assert(not ok)
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("a later module failure restores previous registry entries", function()
  local accepted = orbit.get_config()
  local previous = keymaps.setup
  keymaps.setup = function(opts)
    previous(opts)
    error("injected keymap activation failure")
  end
  local ok, err = pcall(orbit.setup, {
    modules = {
      filetypes = { compose = "yaml.failed", jsx = "jsx.failed" },
      keymaps = { leader = ",", save = "<leader>f" },
    },
  })
  keymaps.setup = previous
  assert(not ok and tostring(err):find("injected keymap activation failure", 1, true))
  assert(match("compose.yaml") == "yaml.custom")
  assert(match("example.jsx") == "javascriptreact")
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("disabling restores initial detections", function()
  orbit.setup({ modules = { filetypes = { enabled = false } } })
  assert(match("compose.yaml") == original.compose)
  assert(match("docker-compose.yml") == original.docker)
  assert(match("example.jsx") == original.jsx)
end)

print(string.format("%d filetype module tests passed.", count))
