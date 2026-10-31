-- Real file conversions must preserve explicit-only writes and legacy keys.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local passed = 0

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

local function read_bytes(path)
  local file = assert(io.open(path, "rb"))
  local bytes = assert(file:read("*a"))
  assert(file:close())
  return bytes
end

local function write_bytes(path, data)
  local file = assert(io.open(path, "wb"))
  assert(file:write(data))
  assert(file:close())
end

local function mapping(lhs)
  return vim.fn.maparg(lhs, "n", false, true)
end

local sandbox = vim.fn.tempname() .. " encoding path with spaces"
assert(vim.fn.mkdir(sandbox, "p") == 1)
local dos_path = sandbox .. "/dos.txt"
local big5_path = sandbox .. "/big5.txt"
local previous_buffer = vim.api.nvim_get_current_buf()

vim.keymap.set("n", " fu", "<cmd>echo 'user-unix'<cr>", { silent = true })
vim.keymap.set("n", " fi", "<cmd>echo 'user-utf8'<cr>", { silent = true })
local original_unix, original_utf8 = mapping(" fu").rhs, mapping(" fi").rhs

check("no file action runs during setup", function()
  write_bytes(dos_path, "one\r\ntwo\r\n")
  local before = read_bytes(dos_path)
  orbit.setup()
  assert(type(mapping(" fu").callback) == "function")
  assert(type(mapping(" fi").callback) == "function")
  assert(package.loaded["orbit.modules.keymaps.conversion"] == nil)
  assert(read_bytes(dos_path) == before)
end)

check("DOS shortcut converts on-disk CRLF into Unix LF", function()
  vim.cmd.edit({ args = { dos_path } })
  assert(vim.bo.fileformat == "dos")
  mapping(" fu").callback()
  assert(vim.bo.fileformat == "unix")
  assert(read_bytes(dos_path) == "one\ntwo\n")
end)

check("Big5 shortcut writes valid UTF-8 without altering text", function()
  local text = "測試中文"
  local bytes = vim.fn.iconv(text, "utf-8", "big5")
  assert(type(bytes) == "string" and #bytes > 0)
  write_bytes(big5_path, bytes .. "\n")
  vim.cmd.edit({ args = { big5_path } })
  mapping(" fi").callback()
  assert(vim.bo.fileencoding == "utf-8")
  assert(read_bytes(big5_path) == text .. "\n")
  assert(vim.api.nvim_get_current_line() == text)
end)

check("conversion refuses unnamed buffers without writing", function()
  vim.cmd.enew()
  local before = read_bytes(dos_path)
  assert(vim.api.nvim_buf_get_name(0) == "")
  local ok, err = pcall(function() mapping(" fu").callback() end)
  assert(not ok and tostring(err):find("named buffer", 1, true))
  assert(read_bytes(dos_path) == before)
end)

check("leader reconfiguration keeps the physical conversion keys", function()
  orbit.setup({ modules = { keymaps = { leader = ",", save = "<leader>w" } } })
  assert(mapping(" fu").rhs == original_unix)
  assert(mapping(" fi").rhs == original_utf8)
  assert(type(mapping(",fu").callback) == "function")
  assert(type(mapping(",fi").callback) == "function")
end)

check("disable restores original user conversion shortcuts", function()
  orbit.setup({ modules = { keymaps = { enabled = false } } })
  assert(mapping(" fu").rhs == original_unix)
  assert(mapping(" fi").rhs == original_utf8)
  assert(vim.fn.maparg(",fu", "n") == "")
  assert(vim.fn.maparg(",fi", "n") == "")
end)

vim.api.nvim_set_current_buf(previous_buffer)
vim.fn.delete(sandbox, "rf")
print(string.format("%d file conversion tests passed.", passed))
