-- Execute the real module lifecycle with injected failures.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local editor = require("orbit.modules.editor")
local keymaps = require("orbit.modules.keymaps")
local count = 0

local function check(label, callback)
  local ok, err = xpcall(callback, debug.traceback)
  assert(ok, "FAIL " .. label .. ": " .. tostring(err))
  count = count + 1
  print("PASS " .. label)
end

check("failed later module restores option defaults and local overrides", function()
  orbit.setup({
    modules = {
      editor = { shiftwidth = 4, number = true },
      keymaps = { leader = " ", save = "<leader>w" },
    },
  })
  local buffer = vim.api.nvim_get_current_buf()
  vim.bo[buffer].shiftwidth = 7
  local accepted = orbit.get_config()
  local old_setup = keymaps.setup

  keymaps.setup = function(opts)
    old_setup(opts)
    error("injected keymaps failure")
  end
  local ok, err = pcall(orbit.setup, {
    modules = {
      editor = { shiftwidth = 8, number = false },
      keymaps = { leader = ",", save = "<leader>z" },
    },
  })
  keymaps.setup = old_setup

  assert(not ok and tostring(err):find("injected keymaps failure", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  assert(vim.api.nvim_get_option_value("shiftwidth", { scope = "global" }) == 4)
  assert(vim.bo[buffer].shiftwidth == 7)
  assert(vim.wo.number == true)
  assert(vim.wo.signcolumn == "yes")
  assert(vim.o.laststatus == 3)
  assert(vim.g.mapleader == " ")
  assert(vim.fn.maparg(" w", "n") ~= "")
  assert(vim.fn.maparg(",z", "n") == "")
end)

check("failed editor activation restores its own partial changes", function()
  local accepted = orbit.get_config()
  local old_setup = editor.setup
  editor.setup = function(opts)
    old_setup(opts)
    error("injected editor failure")
  end
  local ok, err =
    pcall(orbit.setup, { modules = {
      editor = { shiftwidth = 9, number = false },
    } })
  editor.setup = old_setup

  assert(not ok and tostring(err):find("injected editor failure", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  assert(vim.api.nvim_get_option_value("shiftwidth", { scope = "global" }) == 4)
  assert(vim.wo.number == true)
end)

check("new buffers default to the first file format and loaded buffers keep theirs", function()
  vim.cmd("enew")
  local loaded = vim.api.nvim_get_current_buf()
  vim.bo[loaded].fileformat = "unix"
  orbit.setup({ modules = { editor = { fileformats = "dos,unix", shiftwidth = 4 } } })
  assert(vim.api.nvim_get_option_value("fileformat", { scope = "global" }) == "dos")
  assert(vim.bo[loaded].fileformat == "unix", "a loaded buffer keeps its line endings")
  local scratch = vim.api.nvim_create_buf(true, false)
  assert(vim.bo[scratch].fileformat == "dos", "nvim_create_buf follows fileformats")
  vim.api.nvim_buf_delete(scratch, { force = true })

  local old_setup = editor.setup
  editor.setup = function(opts)
    old_setup(opts)
    error("injected fileformat failure")
  end
  vim.api.nvim_set_option_value("fileformat", "mac", { scope = "global" })
  local ok =
    pcall(orbit.setup, { modules = { editor = { fileformats = "unix,dos", shiftwidth = 4 } } })
  editor.setup = old_setup
  assert(not ok)
  assert(vim.api.nvim_get_option_value("fileformat", { scope = "global" }) == "mac", "rollback")
  orbit.setup({ modules = { editor = { fileformats = "unix,dos", shiftwidth = 4 } } })
  assert(vim.api.nvim_get_option_value("fileformat", { scope = "global" }) == "unix")
  vim.cmd("bwipeout!")
end)

check("failed remapping restores a pre-existing mapping", function()
  vim.keymap.set("n", ",z", "<cmd>echo 'original'<cr>", { silent = true })
  local before = vim.fn.maparg(",z", "n")
  local old_setup = keymaps.setup
  keymaps.setup = function(opts)
    old_setup(opts)
    error("injected failure")
  end
  local ok =
    pcall(orbit.setup, { modules = {
      keymaps = { leader = ",", save = "<leader>z" },
    } })
  keymaps.setup = old_setup
  assert(not ok)
  assert(vim.fn.maparg(",z", "n") == before, "previous mapping was not restored")
  assert(vim.fn.maparg(" w", "n") ~= "", "active mapping disappeared")
  vim.keymap.del("n", ",z")
end)

check("successful setup after a failure can replace mappings", function()
  orbit.setup({
    modules = {
      editor = { shiftwidth = 3 },
      keymaps = { leader = ",", save = "<leader>s" },
    },
  })
  assert(vim.g.mapleader == ",")
  assert(vim.fn.maparg(",s", "n") ~= "")
  assert(vim.fn.maparg(" w", "n") == "")
  assert(orbit.get_config().modules.editor.shiftwidth == 3)
end)

print(string.format("%d lifecycle tests passed.", count))
