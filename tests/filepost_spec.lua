-- Verify FilePost startup ordering and one-shot behavior without plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local passed = 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local filepost, filetype = 0, 0
vim.api.nvim_create_autocmd("User", {
  pattern = "FilePost",
  callback = function()
    filepost = filepost + 1
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  callback = function()
    filetype = filetype + 1
  end,
})

check("headless configuration does not fire FilePost during setup", function()
  orbit.setup()
  assert(filepost == 0)
  local entries = vim.api.nvim_get_autocmds({
    group = "OrbitCoreEvents",
    event = "UIEnter",
  })
  assert(#entries == 1)
end)

check("UIEnter with an unnamed buffer does not emit FilePost", function()
  vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
  assert(filepost == 0)
end)

check("named special buffers do not consume the one-shot FilePost", function()
  for _, buftype in ipairs({ "nofile", "prompt", "acwrite" }) do
    local buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".lua")
    vim.bo[buffer].buftype = buftype
    vim.api.nvim_exec_autocmds("BufReadPost", {
      buffer = buffer, modeline = false,
    })
    vim.api.nvim_exec_autocmds("BufNewFile", {
      buffer = buffer, modeline = false,
    })
    assert(filepost == 0, buftype .. " consumed FilePost")
    vim.api.nvim_buf_delete(buffer, { force = true })
  end
  assert(#vim.api.nvim_get_autocmds({
    group = "OrbitCoreEvents", event = "BufReadPost",
  }) == 1, "special buffers removed the one-shot observer")
end)

check("a real file after UIEnter fires FilePost once", function()
  local buffer = vim.api.nvim_create_buf(true, false)
  local name = vim.fn.tempname() .. ".lua"
  vim.api.nvim_buf_set_name(buffer, name)
  vim.api.nvim_exec_autocmds("BufReadPost", {
    buffer = buffer, modeline = false,
  })
  assert(filepost == 1, "FilePost did not fire")
  assert(vim.wait(1000, function()
    return filetype >= 1
  end, 10), "FileType was not replayed")
  local seen = filetype
  vim.api.nvim_exec_autocmds("BufReadPost", {
    buffer = buffer, modeline = false,
  })
  vim.api.nvim_exec_autocmds("BufNewFile", {
    buffer = buffer, modeline = false,
  })
  assert(filepost == 1)
  assert(filetype == seen)
end)

check("subsequent setup does not register a new FilePost hook", function()
  orbit.setup()
  assert(#vim.api.nvim_get_autocmds({
    group = "OrbitCoreEvents", event = "UIEnter",
  }) == 0)
  assert(filepost == 1)
end)

check("filepost setting is restart-only after initialization", function()
  orbit.setup({ modules = { events = { filepost = false } } })
  assert(orbit.get_config().modules.events.filepost == true)
  assert(orbit.get_pending_restart()["orbit.modules.events.filepost"] == false)
end)

print(string.format("%d FilePost event tests passed.", passed))
