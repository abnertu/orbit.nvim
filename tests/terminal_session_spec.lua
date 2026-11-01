-- Drive real interactive shells through the terminal owner with a UI
-- attached: sh on Linux and pwsh on Windows. No plugins are required.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local windows = vim.fn.has("win32") == 1
local shell = windows and "pwsh" or "sh"
assert(vim.fn.executable(shell) == 1, shell .. " is required for terminal acceptance")
-- Each command computes its marker, so echoed input cannot satisfy a wait.
local commands = windows and {
  first = "Write-Output ('orbit-first-' + (6 * 7))",
  second = "Write-Output ('orbit-second-' + (5 * 5))",
} or {
  first = "echo orbit-first-$((6 * 7))",
  second = "echo orbit-second-$((5 * 5))",
}
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local workspace = vim.fn.tempname() .. " terminal session"
vim.fn.mkdir(workspace, "p")
local init = workspace .. "/init.lua"
vim.fn.writefile({
  "vim.opt.rtp:prepend(" .. vim.inspect(root) .. ")",
  "vim.o.shell = " .. vim.inspect(vim.fn.exepath(shell)),
  "require('orbit').setup()",
}, init)
local job = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-i", "NONE",
  "-u", init }, { rpc = true, env = { XDG_STATE_HOME = workspace .. "/state" } })
assert(job > 0, "cannot start child Neovim")

local function lua(code, ...)
  return vim.rpcrequest(job, "nvim_exec_lua", code, { ... })
end
local function wait(predicate, message)
  assert(vim.wait(30000, predicate, 50), message)
end
local function contains(buffer, marker)
  return lua([[
    local buffer, marker = ...
    return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
      :find(marker, 1, true) ~= nil
  ]], buffer, marker)
end

local ok, err = pcall(function()
  vim.rpcrequest(job, "nvim_ui_attach", 120, 40, { rgb = true })
  local session = {}

  check("real " .. shell .. " input produces output in the toggled terminal", function()
    session.origin = lua("return vim.api.nvim_get_current_win()")
    assert(lua("return require('orbit.modules.keymaps.terminal').toggle('vsp', 'acceptance')"))
    session.buffer = lua("return vim.api.nvim_get_current_buf()")
    session.job = lua("return vim.b[...].terminal_job_id", session.buffer)
    assert(lua("return vim.bo[...].buftype", session.buffer) == "terminal")
    -- Wait for the shell to start before typing.
    wait(function()
      return lua("return #table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false)) > 0",
        session.buffer)
    end, "shell printed no prompt")
    lua([[vim.api.nvim_chan_send(...)]], session.job, commands.first .. "\r")
    wait(function() return contains(session.buffer, "orbit-first-42") end,
      "shell output did not reach the terminal buffer")
  end)

  check("hiding returns focus to the source window and keeps the shell", function()
    assert(lua("return require('orbit.modules.keymaps.terminal').toggle('vsp', 'acceptance')"))
    assert(lua("return vim.api.nvim_get_current_win()") == session.origin)
    assert(lua("return vim.fn.jobwait({ ... }, 0)[1]", session.job) == -1)
  end)

  check("another tab reuses the same live session and owns its own window", function()
    lua("vim.cmd.tabnew()")
    assert(lua("return require('orbit.modules.keymaps.terminal').toggle('vsp', 'acceptance')"))
    assert(lua("return vim.api.nvim_get_current_buf()") == session.buffer,
      "the second tab started another terminal")
    assert(contains(session.buffer, "orbit-first-42"), "earlier output was lost")
    lua([[vim.api.nvim_chan_send(...)]], session.job, commands.second .. "\r")
    wait(function() return contains(session.buffer, "orbit-second-25") end,
      "input from the second tab produced no output")
    lua("vim.cmd.tabprevious()")
    assert(lua("return require('orbit.modules.keymaps.terminal').toggle('vsp', 'acceptance')"))
    local first_tab_window = lua("return vim.api.nvim_get_current_win()")
    assert(lua("return require('orbit.modules.keymaps.terminal').toggle('vsp', 'acceptance')"))
    assert(not lua("return vim.api.nvim_win_is_valid(...)", first_tab_window))
    lua("vim.cmd.tabnext()")
    assert(lua("return vim.api.nvim_get_current_buf()") == session.buffer,
      "hiding in one tab closed the other tab's terminal window")
  end)

  check("an exited shell is replaced by a new session", function()
    -- A failing exit keeps the terminal buffer, so reuse must check the job.
    lua([[vim.api.nvim_chan_send(...)]], session.job, "exit 3\r")
    wait(function() return lua("return vim.fn.jobwait({ ... }, 0)[1]", session.job) ~= -1 end,
      "shell did not exit")
    assert(lua("return vim.api.nvim_buf_is_valid(...)", session.buffer),
      "the exited terminal buffer must remain for this check")
    lua("vim.cmd.tabclose()")
    assert(lua("return require('orbit.modules.keymaps.terminal').toggle('vsp', 'acceptance')"))
    local replacement = lua("return vim.api.nvim_get_current_buf()")
    local replacement_job = lua("return vim.b[...].terminal_job_id", replacement)
    assert(replacement ~= session.buffer and replacement_job ~= session.job)
    assert(lua("return vim.fn.jobwait({ ... }, 0)[1]", replacement_job) == -1)
    lua([[vim.api.nvim_chan_send(...)]], replacement_job, commands.first .. "\r")
    wait(function() return contains(replacement, "orbit-first-42") end,
      "the replacement shell did not accept input")
    lua([[vim.api.nvim_chan_send(...)]], replacement_job, "exit\r")
  end)
end)
pcall(vim.fn.jobstop, job)
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print(string.format("%d terminal session tests passed with %s.", passed, shell))
