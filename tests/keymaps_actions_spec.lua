-- Protect leader actions through real Neovim mappings and root setup.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local events = require("orbit.modules.events")
local project = require("orbit.modules.keymaps.project")
local passed = 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local function mapping(lhs)
  return vim.fn.maparg(lhs, "n", false, true)
end

local function equal_path(left, right)
  left, right = vim.fs.normalize(left), vim.fs.normalize(right)
  if vim.fn.has("win32") == 1 then
    left, right = left:lower(), right:lower()
  end
  return left == right
end

vim.keymap.set("n", " bn", "<cmd>echo 'old buffer'<cr>", { silent = true })
vim.keymap.set("n", ",bn", "<cmd>echo 'comma buffer'<cr>", { silent = true })
vim.keymap.set("n", ";bn", "<cmd>echo 'semicolon buffer'<cr>", { silent = true })
local prior_space = mapping(" bn").rhs
local prior_comma = mapping(",bn").rhs
local prior_semicolon = mapping(";bn").rhs

check("default leader actions replace fixed physical slots", function()
  orbit.setup()
  for _, lhs in ipairs({ " bn", " fd", " tf" }) do
    assert(type(mapping(lhs).callback) == "function", "missing " .. lhs)
  end
  assert(mapping(" w").rhs:lower():find("write", 1, true))
end)

check("new-buffer shortcut uses real Neovim buffer creation", function()
  local original = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(original, vim.fn.tempname() .. ".lua")
  mapping(" bn").callback()
  local created = vim.api.nvim_get_current_buf()
  assert(created ~= original and vim.api.nvim_buf_get_name(created) == "")
  vim.api.nvim_set_current_buf(original)
  vim.api.nvim_buf_delete(created, { force = true })
end)

check("diagnostics shortcut defers the floating diagnostic callback", function()
  local original = vim.diagnostic.open_float
  local called = 0
  vim.diagnostic.open_float = function(...)
    assert(select("#", ...) == 0)
    called = called + 1
  end
  local ok, err = xpcall(function()
    mapping(" tf").callback()
  end, debug.traceback)
  vim.diagnostic.open_float = original
  assert(ok, err)
  assert(called == 1)
end)

check("project shortcut resolves markers and an LSP root without a shell", function()
  local before = vim.fn.getcwd()
  local original_buffer = vim.api.nvim_get_current_buf()
  local original_clients = vim.lsp.get_clients
  local sandbox = vim.fn.tempname() .. " project with spaces"
  local source = sandbox .. "/nested/deep"
  local lsp_root = sandbox .. "/language server root"
  assert(vim.fn.mkdir(source, "p") == 1)
  assert(vim.fn.mkdir(sandbox .. "/.git", "p") == 1)
  assert(vim.fn.mkdir(lsp_root, "p") == 1)
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buffer, source .. "/sample.lua")
  vim.api.nvim_set_current_buf(buffer)
  vim.lsp.get_clients = function(opts)
    assert(opts.bufnr == 0)
    return {}
  end
  local ok, err = xpcall(function()
    vim.api.nvim_set_current_dir(source)
    mapping(" fd").callback()
    assert(equal_path(vim.fn.getcwd(), sandbox), "failed marker root")
    vim.lsp.get_clients = function() return {
      { config = { root_dir = lsp_root } },
    } end
    assert(equal_path(project.root(), lsp_root), "LSP root not preferred")
    assert(equal_path(project.root(source .. "/sample.lua"), sandbox),
      "explicit path should skip current LSP")
    vim.api.nvim_set_current_dir(source)
    mapping(" fd").callback()
    assert(equal_path(vim.fn.getcwd(), lsp_root))
  end, debug.traceback)
  vim.lsp.get_clients = original_clients
  vim.api.nvim_set_current_dir(before)
  vim.api.nvim_set_current_buf(original_buffer)
  vim.api.nvim_buf_delete(buffer, { force = true })
  vim.fn.delete(sandbox, "rf")
  assert(ok, err)
end)

check("leader changes release physical keys and retain user mappings", function()
  orbit.setup({ modules = { keymaps = { leader = ",", save = "<leader>w" } } })
  assert(mapping(" bn").rhs == prior_space)
  assert(type(mapping(",bn").callback) == "function")
  assert(type(mapping(",fd").callback) == "function")
  assert(type(mapping(",tf").callback) == "function")
  assert(mapping(",w").rhs:lower():find("write", 1, true))
end)

check("save key collisions are rejected before replacing accepted values", function()
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    keymaps = { leader = ",", save = "<leader>bn" },
  } })
  assert(not ok and tostring(err):find("duplicate leader mapping", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
  assert(type(mapping(",bn").callback) == "function")
end)

check("downstream failure restores old and proposed physical mappings", function()
  local before = orbit.get_config()
  local original = events.setup
  events.setup = function() error("injected leader action failure") end
  local ok, err = pcall(orbit.setup, { modules = {
    keymaps = { leader = ";", save = "<leader>w" },
    events = { diagnostics_redraw = false },
  } })
  events.setup = original
  assert(not ok and tostring(err):find("injected leader action failure", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
  assert(vim.g.mapleader == ",")
  assert(type(mapping(",bn").callback) == "function")
  assert(mapping(";bn").rhs == prior_semicolon)
  assert(mapping(" bn").rhs == prior_space)
end)

check("disable restores third-party mappings for both former leaders", function()
  orbit.setup({ modules = { keymaps = { enabled = false } } })
  assert(mapping(" bn").rhs == prior_space)
  assert(mapping(",bn").rhs == prior_comma)
  assert(mapping(";bn").rhs == prior_semicolon)
  assert(vim.fn.maparg(",fd", "n") == "")
  assert(vim.fn.maparg(",tf", "n") == "")
end)

print(string.format("%d leader action tests passed.", passed))
