-- FilePost must replay EditorConfig once, after FileType and on a valid buffer.
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

local previous_editorconfig = package.loaded["editorconfig"]
local previous_flag = vim.g.editorconfig
local events = {}
local applies = {}
local fileposts = 0

package.loaded["editorconfig"] = {
  config = function(buffer)
    assert(vim.api.nvim_buf_is_valid(buffer))
    assert(vim.api.nvim_buf_is_loaded(buffer))
    events[#events + 1] = { type = "editorconfig", buffer = buffer }
    applies[#applies + 1] = buffer
  end,
}
vim.g.editorconfig = true

vim.api.nvim_create_autocmd("FileType", {
  callback = function(event)
    events[#events + 1] = { type = "filetype", buffer = event.buf }
  end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "FilePost",
  callback = function()
    events[#events + 1] = { type = "filepost" }
    fileposts = fileposts + 1
  end,
})

check("setup never eagerly imports or applies EditorConfig", function()
  orbit.setup()
  assert(#applies == 0)
  assert(fileposts == 0)
end)

check("UIEnter with an unnamed buffer does not replay EditorConfig", function()
  vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
  assert(#applies == 0)
  assert(fileposts == 0)
end)

local buffer
check("named file triggers FilePost then FileType then EditorConfig", function()
  buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".lua")
  vim.api.nvim_exec_autocmds("BufReadPost", {
    buffer = buffer, modeline = false,
  })
  assert(fileposts == 1)
  assert(vim.wait(1000, function() return #applies == 1 end, 10),
    "EditorConfig was not applied")
  assert(applies[1] == buffer)
  local index = #events
  assert(events[index - 1].type == "filetype")
  assert(events[index].type == "editorconfig")
  assert(events[index - 1].buffer == buffer)
  assert(events[index].buffer == buffer)
end)

check("the same and new file events never replay the one-shot config", function()
  local second = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(second, vim.fn.tempname() .. ".txt")
  vim.api.nvim_exec_autocmds("BufReadPost", {
    buffer = buffer, modeline = false,
  })
  vim.api.nvim_exec_autocmds("BufNewFile", {
    buffer = second, modeline = false,
  })
  assert(vim.wait(100, function() return true end, 10))
  assert(fileposts == 1)
  assert(#applies == 1)
  vim.api.nvim_buf_delete(second, { force = true })
end)

check("reconfiguration does not register duplicate FilePost hooks", function()
  orbit.setup()
  assert(fileposts == 1)
  assert(#applies == 1)
  assert(#vim.api.nvim_get_autocmds({
    group = "OrbitCoreEvents", event = "BufReadPost",
  }) == 0)
end)

vim.api.nvim_buf_delete(buffer, { force = true })
package.loaded["editorconfig"] = previous_editorconfig
vim.g.editorconfig = previous_flag
print(string.format("%d editorconfig replay tests passed.", passed))
