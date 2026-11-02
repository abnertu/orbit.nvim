-- A silent colon mapping suppresses the first native cmdline UI event.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local job = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-i", "NONE", "-u", "NONE" }, { rpc = true })
assert(job > 0)
local ok, err = xpcall(function()
  vim.rpcrequest(job, "nvim_ui_attach", 100, 30, { rgb = true })
  vim.rpcrequest(job, "nvim_exec_lua", [[
    vim.opt.rtp:prepend(...)
    require("orbit.modules.corekeys").setup()
    local shown = 0
    vim.ui_attach(vim.api.nvim_create_namespace("OrbitTestCmdline"), { ext_cmdline = true }, function(event)
      if event == "cmdline_show" then shown = shown + 1 end
    end)
    package.loaded["orbit.tests.cmdline"] = { shown = function() return shown end }
  ]], { root })
  vim.rpcnotify(job, "nvim_input", ";")
  assert(vim.wait(1000, function()
    return vim.rpcrequest(job, "nvim_exec_lua", [[
      return vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == ""
        and require("orbit.tests.cmdline").shown() > 0
    ]], {})
  end, 10), "semicolon did not show cmdline UI before the next character")
  vim.rpcnotify(job, "nvim_input", "<Esc>")
end, debug.traceback)
vim.fn.jobstop(job)
assert(ok, err)
print("PASS semicolon shows the native cmdline UI before command text")
