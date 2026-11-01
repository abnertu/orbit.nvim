-- Verify tab line ownership, rendering and real mouse input.
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

local function rendered()
  return vim.api.nvim_eval_statusline(vim.go.tabline,
    { use_tabline = true, highlights = false }).str
end

local directory = vim.fn.tempname() .. " tabline"
local function file(relative)
  local path = directory .. "/" .. relative
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ relative }, path)
  return path
end

vim.go.tabline, vim.go.showtabline = "user tabline", 1

check("setup owns the tab line and shows this tab's buffers in order", function()
  orbit.setup()
  assert(vim.go.showtabline == 2 and require("orbit.buffers").attached("tabline"))
  vim.cmd.edit(vim.fn.fnameescape(file("alpha.txt")))
  vim.cmd.edit(vim.fn.fnameescape(file("beta.txt")))
  local text = rendered()
  local alpha, beta = text:find("alpha.txt", 1, true), text:find("beta.txt", 1, true)
  assert(alpha and beta and alpha < beta, text)
end)

check("duplicate names show their parent directory", function()
  vim.cmd.edit(vim.fn.fnameescape(file("one/same.txt")))
  vim.cmd.edit(vim.fn.fnameescape(file("two/same.txt")))
  local text = rendered()
  assert(text:find("one/same.txt", 1, true) and text:find("two/same.txt", 1, true), text)
end)

check("other tabs keep their own buffers and tab numbers appear", function()
  vim.cmd.tabnew()
  vim.cmd.edit(vim.fn.fnameescape(file("gamma.txt")))
  local text = rendered()
  assert(text:find("gamma.txt", 1, true) and not text:find("alpha.txt", 1, true), text)
  assert(text:find(" 1  2 ", 1, true), text)
  vim.cmd.tabclose()
end)

check("the current buffer stays visible when labels overflow", function()
  local columns = vim.o.columns
  vim.o.columns = 40
  vim.cmd.edit(vim.fn.fnameescape(file("one/same.txt")))
  local text = rendered()
  assert(text:find("one/same.txt", 1, true), text)
  assert(vim.api.nvim_strwidth(text) <= 40, text)
  vim.o.columns = columns
end)

check("closing from the tab line keeps the window and refuses edits", function()
  local layout = #vim.api.nvim_tabpage_list_wins(0)
  local target = vim.fn.bufnr(file("beta.txt"))
  vim.api.nvim_set_current_buf(target)
  require("orbit.modules.tabline.render").close(target)
  assert(not vim.api.nvim_buf_is_valid(target) or not vim.bo[target].buflisted)
  assert(#vim.api.nvim_tabpage_list_wins(0) == layout, "close must keep the window")
  assert(vim.api.nvim_buf_get_name(0) ~= "", "the window must show a neighbouring buffer")
  local current = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(current, 0, -1, false, { "edited" })
  local notify, warned = vim.notify, nil
  vim.notify = function(message) warned = message end
  require("orbit.modules.tabline.render").close(current)
  vim.notify = notify
  assert(warned and warned:find("unsaved", 1, true) and vim.api.nvim_buf_is_valid(current))
  vim.bo[current].modified = false
end)

check("disabling restores the prior tab line and detaches buffer order", function()
  orbit.setup({ modules = { tabline = { enabled = false } } })
  assert(vim.go.tabline == "user tabline" and vim.go.showtabline == 1)
  assert(not require("orbit.buffers").attached("tabline"))
  assert(pcall(vim.api.nvim_get_autocmds, { group = "OrbitBufferOrder" }),
    "corekeys still owns the buffer order")
  orbit.setup({ modules = { tabline = { enabled = false }, corekeys = { enabled = false } } })
  assert(not pcall(vim.api.nvim_get_autocmds, { group = "OrbitBufferOrder" }),
    "the last owner must remove the buffer-order group")
end)

check("real mouse clicks select and close buffers", function()
  local init = directory .. "/child init.lua"
  vim.fn.writefile({
    "vim.opt.rtp:prepend(" .. vim.inspect(root) .. ")",
    "vim.o.mouse = 'a'",
    "require('orbit').setup()",
    "vim.cmd.edit(vim.fn.fnameescape(" .. vim.inspect(file("left.txt")) .. "))",
    "vim.cmd.edit(vim.fn.fnameescape(" .. vim.inspect(file("right.txt")) .. "))",
  }, init)
  local job = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-i", "NONE",
    "-u", init }, { rpc = true })
  assert(job > 0, "cannot start child Neovim")
  local ok, err = pcall(function()
    vim.rpcrequest(job, "nvim_ui_attach", 100, 20, { rgb = true })
    local function column(label)
      return vim.rpcrequest(job, "nvim_exec_lua", [[
        local text = vim.api.nvim_eval_statusline(vim.go.tabline,
          { use_tabline = true, highlights = false }).str
        local start = text:find(..., 1, true)
        return start and vim.fn.strdisplaywidth(text:sub(1, start - 1)) or -1
      ]], { label })
    end
    local function current()
      return vim.rpcrequest(job, "nvim_exec_lua",
        "return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')", {})
    end
    local function click(col)
      vim.rpcrequest(job, "nvim_input_mouse", "left", "press", "", 0, 0, col)
      vim.rpcrequest(job, "nvim_input_mouse", "left", "release", "", 0, 0, col)
    end
    local function wait(predicate, message)
      assert(vim.wait(5000, predicate, 20), message)
    end
    local left = column("left.txt")
    assert(left >= 0 and current() == "right.txt")
    click(left + 1)
    wait(function() return current() == "left.txt" end, "click did not select the buffer")
    local close = column("right.txt") + vim.fn.strdisplaywidth("right.txt ")
    click(close)
    wait(function() return column("right.txt") == -1 end, "close click left the buffer")
    assert(current() == "left.txt")
  end)
  vim.fn.jobstop(job)
  assert(ok, err)
end)

vim.fn.delete(directory, "rf")
print(string.format("%d tabline tests passed.", passed))
