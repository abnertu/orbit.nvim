-- Exercise real PTY jobs with long-running native shell commands on both OSes.
-- A controlled command avoids headless EOF behavior of interactive shells.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local terminal = require("orbit.modules.keymaps.terminal")
local completed = 0

local function check(label, run)
  local ok, err = xpcall(run, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  completed = completed + 1
  print("PASS " .. label)
end

local function alive(job)
  return vim.fn.jobwait({ job }, 0)[1] == -1
end

local function session()
  local buffer = vim.api.nvim_get_current_buf()
  local job = vim.b[buffer].terminal_job_id
  assert(vim.bo[buffer].buftype == "terminal", "expected real terminal buffer")
  assert(type(job) == "number" and job > 0, "missing live terminal job")
  assert(alive(job), "terminal shell exited before toggle")
  return buffer, job
end

-- Keep test cleanup deterministic even when an assertion fails.
local function isolated(run)
  io.stderr:write("live terminal: creating isolated PTY fixture\\n")
  io.stderr:flush()
  -- A timed shell command has a deterministic lifetime in headless CI.
  -- Interactive cmd.exe may exit on EOF when no terminal UI is attached.
  -- Keep the production jobstart/PTY path; substitute only its argv input.
  local shell_argv = terminal.shell_argv
  local windows = vim.fn.has("win32") == 1
  local shell = windows and "cmd.exe" or "/bin/sh"
  assert(vim.fn.executable(shell) == 1, "required host shell is unavailable")
  terminal.shell_argv = function()
    if windows then
      return { shell, "/d", "/c", "ping -n 60 127.0.0.1 >nul" }
    end
    return { shell, "-c", "sleep 60" }
  end
  vim.cmd.tabnew()
  local tab = vim.api.nvim_get_current_tabpage()
  local jobs, buffers = {}, {}
  local function track()
    local buffer, job = session()
    buffers[#buffers + 1] = buffer
    jobs[#jobs + 1] = job
    return buffer, job
  end
  local ok, err = xpcall(function()
    run(track)
  end, debug.traceback)

  for _, job in ipairs(jobs) do
    if alive(job) then
      pcall(vim.fn.jobstop, job)
      vim.fn.jobwait({ job }, 3000)
    end
  end
  if vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    pcall(vim.cmd.tabclose)
  end
  for _, buffer in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
  end
  terminal.shell_argv = shell_argv
  assert(ok, err)
end

orbit.setup()

check("real shell survives hiding and reopening the mapped vertical terminal", function()
  isolated(function(track)
    local binding = vim.fn.maparg("<M-v>", "n", false, true)
    assert(type(binding.callback) == "function", "vertical toggle key is missing")
    local original = vim.api.nvim_get_current_win()
    binding.callback()
    io.stderr:write("live terminal: mapped job started\\n")
    io.stderr:flush()
    local buffer, job = track()
    local terminal_window = vim.api.nvim_get_current_win()
    assert(vim.bo[buffer].filetype == "Term_vsp")
    assert(terminal_window ~= original and vim.api.nvim_win_is_valid(original))

    -- Prove the real PTY job remains active across headless event cycles.
    assert(not vim.wait(250, function()
      return not alive(job)
    end, 20), "timed shell command exited unexpectedly")

    io.stderr:write("live terminal: sleeping command survived\\n")
    io.stderr:flush()
    binding.callback()
    assert(not vim.api.nvim_win_is_valid(terminal_window), "toggle did not hide split")
    assert(vim.api.nvim_get_current_win() == original, "original window lost focus")
    assert(vim.api.nvim_buf_is_valid(buffer) and alive(job),
      "hiding the split terminated the shell")

    binding.callback()
    assert(vim.api.nvim_get_current_buf() == buffer, "toggle lost saved terminal buffer")
    assert(vim.b[buffer].terminal_job_id == job and alive(job),
      "reopening started another process or lost the original shell")
  end)
end)

check("the last normal window hides a live session beside an unrelated float", function()
  isolated(function(track)
    local origin = vim.api.nvim_get_current_win()
    assert(terminal.toggle("vsp", "live-last-normal"))
    local buffer, job = track()
    local terminal_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(origin, true)

    local foreign_buffer = vim.api.nvim_create_buf(false, true)
    local popup = vim.api.nvim_open_win(foreign_buffer, false, {
      relative = "editor", row = 1, col = 1, width = 10, height = 2,
    })
    local ok, err = xpcall(function()
      assert(terminal.toggle("vsp", "live-last-normal"))
      assert(vim.api.nvim_win_is_valid(terminal_window),
        "the tab's last normal window must remain")
      assert(vim.api.nvim_win_is_valid(popup), "foreign popup was closed")
      assert(vim.api.nvim_get_current_buf() ~= buffer,
        "hiding must install a replacement normal buffer")
      assert(alive(job), "hiding the last normal window stopped the shell")

      assert(terminal.toggle("vsp", "live-last-normal"))
      assert(vim.api.nvim_get_current_buf() == buffer)
      assert(vim.b[buffer].terminal_job_id == job and alive(job))
      assert(vim.api.nvim_win_is_valid(popup), "popup must remain owned by caller")
    end, debug.traceback)
    if vim.api.nvim_win_is_valid(popup) then
      vim.api.nvim_win_close(popup, true)
    end
    if vim.api.nvim_buf_is_valid(foreign_buffer) then
      vim.api.nvim_buf_delete(foreign_buffer, { force = true })
    end
    assert(ok, err)
  end)
end)

print(string.format("%d real terminal lifecycle tests passed.", completed))
