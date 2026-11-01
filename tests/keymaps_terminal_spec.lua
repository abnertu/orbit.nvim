-- Terminal mappings must reuse owned buffers, preserve windows and avoid shell strings.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local passed = 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local function map(mode, lhs)
  return vim.fn.maparg(lhs, mode, false, true)
end

local user_keys = {
  { "n", " h" }, { "n", " v" },
  { "n", "<M-h>" }, { "n", "<M-v>" }, { "n", "<M-i>" },
  { "t", "<M-h>" }, { "t", "<M-v>" }, { "t", "<M-i>" },
}
local old = {}
for _, target in ipairs(user_keys) do
  local mode, lhs = unpack(target)
  vim.keymap.set(mode, lhs, "<Nop>", { desc = "original terminal key" })
  old[mode .. ":" .. lhs] = map(mode, lhs).rhs
end

check("terminal callbacks are owned lazily in the original modes", function()
  orbit.setup()
  assert(package.loaded["orbit.modules.keymaps.terminal"] == nil)
  for _, target in ipairs(user_keys) do
    assert(type(map(target[1], target[2]).callback) == "function")
  end
end)

local term = require("orbit.modules.keymaps.terminal")
local actual_spawn, actual_start_insert = term.spawn, term.start_insert
local actual_is_live_terminal = term.is_live_terminal
-- Mapping tests stub spawn(), so no real PTY exists in their buffers.
-- The dedicated real-terminal suite exercises the production liveness check.
term.is_live_terminal = function() return true end
local spawns, inserts = 0, 0
term.spawn = function()
  spawns = spawns + 1
  return spawns
end
term.start_insert = function() inserts = inserts + 1 end

check("horizontal terminal creates a split with window-local options", function()
  local origin = vim.api.nvim_get_current_win()
  local before = #vim.api.nvim_tabpage_list_wins(0)
  map("n", " h").callback()
  local win = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_get_current_buf()
  assert(win ~= origin)
  assert(#vim.api.nvim_tabpage_list_wins(0) == before + 1)
  assert(vim.bo[buffer].filetype == "Term_sp")
  assert(vim.bo[buffer].buflisted == false)
  assert(not vim.wo[win].number and not vim.wo[win].relativenumber)
  assert(spawns == 1 and inserts == 1)
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buffer, { force = true })
end)

check("terminal display failure restores the original window and buffer state", function()
  local origin = vim.api.nvim_get_current_win()
  local before_windows = #vim.api.nvim_tabpage_list_wins(0)
  local before_spawns = spawns
  local set_buf = vim.api.nvim_win_set_buf
  local allocated
  vim.api.nvim_win_set_buf = function(_, buffer)
    allocated = buffer
    -- A WinEnter or buffer callback may move focus before setup fails.
    vim.api.nvim_set_current_win(origin)
    error("injected terminal display failure")
  end
  local ok, err = pcall(function() map("n", " v").callback() end)
  vim.api.nvim_win_set_buf = set_buf
  assert(not ok and tostring(err):find("injected terminal display failure", 1, true))
  assert(allocated and not vim.api.nvim_buf_is_valid(allocated),
    "failed display must not leak its scratch buffer")
  assert(vim.api.nvim_get_current_win() == origin,
    "failed display must restore the original window")
  assert(#vim.api.nvim_tabpage_list_wins(0) == before_windows,
    "failed display must close its partial split")
  assert(spawns == before_spawns, "failed display must not start a job")
end)

check("vertical toggle hides and reopens the same buffer, spawning once", function()
  local origin = vim.api.nvim_get_current_win()
  local before = spawns
  assert(map("n", "<M-v>").callback() == nil)
  local win = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_get_current_buf()
  assert(win ~= origin and vim.bo.filetype == "Term_vsp")
  assert(spawns == before + 1)
  map("n", "<M-v>").callback()
  assert(not vim.api.nvim_win_is_valid(win))
  assert(vim.api.nvim_buf_is_valid(buffer))
  map("n", "<M-v>").callback()
  assert(vim.api.nvim_get_current_buf() == buffer)
  assert(spawns == before + 1)
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buffer, { force = true })
end)

check("floating toggle preserves window layout and blocks foreign floats", function()
  local origin = vim.api.nvim_get_current_win()
  map("n", "<M-i>").callback()
  local window = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_get_current_buf()
  local config = vim.api.nvim_win_get_config(window)
  assert(config.relative == "editor")
  assert(config.width > 0 and config.height > 0)
  assert(term.can_toggle())
  map("t", "<M-i>").callback()
  assert(not vim.api.nvim_win_is_valid(window))
  assert(vim.api.nvim_get_current_win() == origin)

  local scratch = vim.api.nvim_create_buf(false, true)
  local float = vim.api.nvim_open_win(scratch, true, {
    relative = "editor", row = 1, col = 1,
    width = 20, height = 3,
  })
  assert(not term.can_toggle())
  -- A foreign float can impersonate the terminal filetype without owning a session.
  vim.bo[scratch].filetype = "Term_float"
  assert(not term.can_toggle(), "foreign terminal-like floats must stay blocked")
  local count = #vim.api.nvim_list_wins()
  assert(term.toggle("float", "floatTerm") == false)
  assert(#vim.api.nvim_list_wins() == count)
  vim.api.nvim_win_close(float, true)
  vim.api.nvim_buf_delete(scratch, { force = true })
  vim.api.nvim_buf_delete(buffer, { force = true })
end)

check("terminal toggle preserves the last normal window beside a foreign float", function()
  vim.cmd.tabnew()
  local tab = vim.api.nvim_get_current_tabpage()
  local original = vim.api.nvim_get_current_win()
  local before_spawns = spawns
  assert(term.toggle("vsp", "lastNormalTerm"))
  local terminal = vim.api.nvim_get_current_buf()
  assert(spawns == before_spawns + 1)
  vim.api.nvim_win_close(original, true)

  -- Floating windows do not count as a second normal window.
  local popup_buffer = vim.api.nvim_create_buf(false, true)
  local popup = vim.api.nvim_open_win(popup_buffer, false, {
    relative = "editor", row = 1, col = 1, width = 10, height = 2,
  })
  assert(#vim.api.nvim_tabpage_list_wins(tab) == 2)
  assert(term.toggle("vsp", "lastNormalTerm"))
  assert(vim.api.nvim_get_current_tabpage() == tab)
  assert(vim.api.nvim_win_is_valid(popup))
  assert(#vim.api.nvim_tabpage_list_wins(tab) == 2)
  assert(vim.api.nvim_buf_is_valid(terminal))
  assert(vim.api.nvim_get_current_buf() ~= terminal)
  assert(vim.bo[vim.api.nvim_get_current_buf()].buflisted)

  vim.api.nvim_win_close(popup, true)
  vim.api.nvim_buf_delete(popup_buffer, { force = true })
  assert(term.toggle("vsp", "lastNormalTerm"))
  assert(vim.api.nvim_get_current_buf() == terminal)
  assert(spawns == before_spawns + 1)
  vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
  vim.api.nvim_buf_delete(terminal, { force = true })
  vim.cmd.tabclose()
end)

check("repurposed saved buffer is never reused as a terminal", function()
  local previous_check = term.is_live_terminal
  term.is_live_terminal = actual_is_live_terminal
  local origin = vim.api.nvim_get_current_win()
  local before = spawns
  local first = term.open("vsp", "repurposed-session")
  vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
  -- The fake spawn does not create a PTY. The production check must
  -- reject this saved buffer and allocate a fresh one on reopening.
  local second = term.open("vsp", "repurposed-session")
  assert(second ~= first, "reopening must not reuse a nonterminal buffer")
  assert(spawns == before + 2, "repurposed session did not spawn again")
  vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
  assert(vim.api.nvim_get_current_win() == origin)
  vim.api.nvim_buf_delete(second, { force = true })
  vim.api.nvim_buf_delete(first, { force = true })
  term.is_live_terminal = previous_check
end)

check("shell arguments are an argv vector and match the host platform", function()
  local original = vim.o.shell
  vim.o.shell = vim.fn.has("win32") == 1 and "pwsh.exe" or "/bin/sh"
  local args = term.shell_argv()
  if vim.fn.has("win32") == 1 then
    assert(vim.deep_equal(args, { "pwsh.exe", "-NoLogo" }))
  else
    assert(vim.deep_equal(args, { "/bin/sh" }))
  end
  vim.o.shell = original
end)

check("an actual Neovim subprocess starts in a terminal buffer", function()
  term.spawn = actual_spawn
  local original_argv = term.shell_argv
  term.shell_argv = function()
    return { vim.v.progpath, "--version" }
  end
  local ok, err = xpcall(function()
    map("n", " v").callback()
    local win = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()
    assert(vim.bo[buffer].buftype == "terminal")
    assert(type(vim.b[buffer].terminal_job_id) == "number")
    assert(vim.b[buffer].terminal_job_id > 0)
    assert(vim.bo[buffer].filetype == "Term_vsp")
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buffer, { force = true })
  end, debug.traceback)
  term.shell_argv = original_argv
  term.spawn = function() spawns = spawns + 1; return spawns end
  assert(ok, err)
end)

check("exited saved PTY is replaced on reopen, not reused", function()
  local previous_spawn, previous_argv = term.spawn, term.shell_argv
  local origin = vim.api.nvim_get_current_win()
  local buffers = {}
  term.spawn = actual_spawn
  term.shell_argv = function()
    return { vim.v.progpath, "--version" }
  end

  local ok, err = xpcall(function()
    assert(term.toggle("vsp", "exited-pty"))
    local first = vim.api.nvim_get_current_buf()
    buffers[#buffers + 1] = first
    local first_job = vim.b[first].terminal_job_id
    assert(vim.bo[first].buftype == "terminal" and first_job > 0)
    assert(vim.wait(10000, function()
      return vim.fn.jobwait({ first_job }, 0)[1] ~= -1
    end, 20), "short-lived terminal command did not exit")

    assert(term.toggle("vsp", "exited-pty"))
    assert(vim.api.nvim_get_current_win() == origin)
    assert(term.toggle("vsp", "exited-pty"))
    local second = vim.api.nvim_get_current_buf()
    buffers[#buffers + 1] = second
    assert(second ~= first, "exited terminal buffer was incorrectly reused")
    assert(vim.bo[second].buftype == "terminal")
    assert(type(vim.b[second].terminal_job_id) == "number"
      and vim.b[second].terminal_job_id ~= first_job,
      "reopening an exited session must start a new PTY")
  end, debug.traceback)

  term.spawn, term.shell_argv = previous_spawn, previous_argv
  if vim.api.nvim_get_current_win() ~= origin then
    pcall(vim.api.nvim_win_close, vim.api.nvim_get_current_win(), true)
  end
  for _, buffer in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
  end
  assert(ok, err)
end)

check("leader and mode mappings survive injected failure and disable", function()
  local accepted = orbit.get_config()
  local original = commands.setup
  commands.setup = function() error("terminal rollback injected") end
  local ok, err = pcall(orbit.setup, { modules = {
    keymaps = { leader = "," },
    commands = { enabled = false },
  } })
  commands.setup = original
  assert(not ok and tostring(err):find("terminal rollback injected", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  for _, target in ipairs(user_keys) do
    assert(type(map(target[1], target[2]).callback) == "function")
  end

  orbit.setup({ modules = { keymaps = { enabled = false } } })
  for _, target in ipairs(user_keys) do
    local mode, lhs = unpack(target)
    assert(map(mode, lhs).rhs == old[mode .. ":" .. lhs])
  end
end)

term.spawn, term.start_insert = actual_spawn, actual_start_insert
print(string.format("%d terminal keymap tests passed.", passed))
