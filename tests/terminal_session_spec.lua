-- Drive real interactive shells through the terminal owner with a UI
-- attached: sh on Linux and pwsh on Windows. No plugins are required.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local windows = vim.fn.has("win32") == 1
local shell = windows and "pwsh" or "sh"
assert(vim.fn.executable(shell) == 1, shell .. " is required for terminal acceptance")
-- Each command computes its marker, so echoed input cannot satisfy a wait.
local commands = windows
    and {
      first = "Write-Output ('orbit-first-' + (6 * 7))",
      second = "Write-Output ('orbit-second-' + (5 * 5))",
    }
  or {
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
local env = { XDG_STATE_HOME = workspace .. "/state" }
if windows then
  -- Use a private PSHOME so a real startup profile never changes an installed or user profile.
  local installed = vim.fs.dirname(vim.fn.exepath(shell))
  local private = workspace .. "/PowerShell"
  ---@param source string
  ---@param target string
  local function copy_shell(source, target)
    assert(vim.fn.mkdir(target, "p") == 1)
    for name in vim.fs.dir(source) do
      local from, to = vim.fs.joinpath(source, name), vim.fs.joinpath(target, name)
      local profile = source == installed
        and (name:lower() == "profile.ps1" or name:lower() == "microsoft.powershell_profile.ps1")
      if not profile then
        if assert(vim.uv.fs_stat(from)).type == "directory" then
          copy_shell(from, to)
        elseif not vim.uv.fs_link(from, to) then
          assert(vim.uv.fs_copyfile(from, to))
        end
      end
    end
  end
  copy_shell(installed, private)
  vim.fn.writefile({
    "$env:ORBIT_TERMINAL_PROFILE = 'orbit-profile-' + (6 * 7)",
    "function prompt { 'orbit-ready> ' }",
  }, private .. "/profile.ps1")
  env.PATH = private .. ";" .. vim.env.PATH
  env.ORBIT_TERMINAL_PROFILE = ""
end
local init = workspace .. "/init.lua"
local initialize_shell = windows and "" -- Exercise Neovim's untouched cmd.exe default on Windows.
  or "vim.o.shell = " .. vim.inspect('"' .. vim.fn.exepath(shell) .. '" -i')
vim.fn.writefile({
  "vim.opt.rtp:prepend(" .. vim.inspect(root) .. ")",
  initialize_shell,
  "require('orbit').setup()",
}, init)
local job = vim.fn.jobstart(
  { vim.v.progpath, "--embed", "--headless", "-i", "NONE", "-u", init },
  { rpc = true, env = env }
)
assert(job > 0, "cannot start child Neovim")

local function lua(code, ...)
  return vim.rpcrequest(job, "nvim_exec_lua", code, { ... })
end
local function wait(predicate, message)
  assert(vim.wait(30000, predicate, 50), message)
end
local function contains(buffer, marker)
  return lua(
    [[
    local buffer, marker = ...
    return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
      :find(marker, 1, true) ~= nil
  ]],
    buffer,
    marker
  )
end

local ok, err = pcall(function()
  vim.rpcrequest(job, "nvim_ui_attach", 120, 40, { rgb = true })
  local session = {}

  check("real " .. shell .. " input produces output in the toggled terminal", function()
    session.origin = lua("return vim.api.nvim_get_current_win()")
    if windows then
      assert(not lua("return vim.api.nvim_get_option_info2('shell', {}).was_set"))
      assert(
        vim.deep_equal(
          lua("return require('orbit.modules.terminal.runtime').shell_argv()"),
          { "pwsh.exe", "-NoLogo" }
        ),
        "the default terminal must select PowerShell with profiles enabled and no logo"
      )
    end
    assert(lua("return require('orbit.modules.terminal.runtime').toggle('vsp', 'acceptance')"))
    session.buffer = lua("return vim.api.nvim_get_current_buf()")
    session.job = lua("return vim.b[...].terminal_job_id", session.buffer)
    assert(lua("return vim.bo[...].buftype", session.buffer) == "terminal")
    -- Wait for the shell to start before typing.
    wait(function()
      if windows then
        return contains(session.buffer, "orbit-ready>")
      end
      return lua(
        "return #table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false)) > 0",
        session.buffer
      )
    end, "shell printed no prompt")
    lua([[vim.api.nvim_chan_send(...)]], session.job, commands.first .. "\r")
    wait(function()
      return contains(session.buffer, "orbit-first-42")
    end, "shell output did not reach the terminal buffer")
  end)

  if windows then
    check("the default Windows terminal loads its startup profile without a banner", function()
      lua(
        [[vim.api.nvim_chan_send(...)]],
        session.job,
        "[Console]::WriteLine($env:ORBIT_TERMINAL_PROFILE)\r"
      )
      wait(function()
        return contains(session.buffer, "orbit-profile-42")
      end, "PowerShell did not load the startup profile")
      for _, banner in ipairs({ "PowerShell 7", "Copyright (C)", "Microsoft Windows" }) do
        assert(not contains(session.buffer, banner), "unexpected startup banner: " .. banner)
      end
    end)
  end

  check("hiding returns focus to the source window and keeps the shell", function()
    assert(lua("return require('orbit.modules.terminal.runtime').toggle('vsp', 'acceptance')"))
    assert(lua("return vim.api.nvim_get_current_win()") == session.origin)
    assert(lua("return vim.fn.jobwait({ ... }, 0)[1]", session.job) == -1)
  end)

  check("another tab reuses the same live session and owns its own window", function()
    lua("vim.cmd.tabnew()")
    assert(lua("return require('orbit.modules.terminal.runtime').toggle('vsp', 'acceptance')"))
    assert(
      lua("return vim.api.nvim_get_current_buf()") == session.buffer,
      "the second tab started another terminal"
    )
    assert(contains(session.buffer, "orbit-first-42"), "earlier output was lost")
    lua([[vim.api.nvim_chan_send(...)]], session.job, commands.second .. "\r")
    wait(function()
      return contains(session.buffer, "orbit-second-25")
    end, "input from the second tab produced no output")
    lua("vim.cmd.tabprevious()")
    assert(lua("return require('orbit.modules.terminal.runtime').toggle('vsp', 'acceptance')"))
    local first_tab_window = lua("return vim.api.nvim_get_current_win()")
    assert(lua("return require('orbit.modules.terminal.runtime').toggle('vsp', 'acceptance')"))
    assert(not lua("return vim.api.nvim_win_is_valid(...)", first_tab_window))
    lua("vim.cmd.tabnext()")
    assert(
      lua("return vim.api.nvim_get_current_buf()") == session.buffer,
      "hiding in one tab closed the other tab's terminal window"
    )
  end)

  check("an exited shell is replaced by a new session", function()
    -- A failing exit keeps the terminal buffer, so reuse must check the job.
    lua([[vim.api.nvim_chan_send(...)]], session.job, "exit 3\r")
    wait(function()
      return lua("return vim.fn.jobwait({ ... }, 0)[1]", session.job) ~= -1
    end, "shell did not exit")
    assert(
      lua("return vim.api.nvim_buf_is_valid(...)", session.buffer),
      "the exited terminal buffer must remain for this check"
    )
    lua("vim.cmd.tabclose()")
    assert(lua("return require('orbit.modules.terminal.runtime').toggle('vsp', 'acceptance')"))
    local replacement = lua("return vim.api.nvim_get_current_buf()")
    local replacement_job = lua("return vim.b[...].terminal_job_id", replacement)
    assert(replacement ~= session.buffer and replacement_job ~= session.job)
    assert(lua("return vim.fn.jobwait({ ... }, 0)[1]", replacement_job) == -1)
    lua([[vim.api.nvim_chan_send(...)]], replacement_job, commands.first .. "\r")
    wait(function()
      return contains(replacement, "orbit-first-42")
    end, "the replacement shell did not accept input")
    lua([[vim.api.nvim_chan_send(...)]], replacement_job, "exit\r")
  end)
end)
pcall(vim.fn.jobstop, job)
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print(string.format("%d terminal session tests passed with %s.", passed, shell))
