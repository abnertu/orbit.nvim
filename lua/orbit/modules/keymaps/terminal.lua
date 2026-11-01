-- Native terminal windows and sessions with no external UI or shell-script glue.
local M = {}
local sessions = {}

local kinds = { sp = true, vsp = true, float = true }

---Build a shell argv vector instead of interpolating platform commands.
---@return string[]
function M.shell_argv()
  local shell = vim.o.shell
  local name = vim.fn.fnamemodify(shell, ":t"):lower():gsub("%.exe$", "")
  if vim.fn.has("win32") == 1
    and (name == "powershell" or name == "pwsh") then
    return { shell, "-NoLogo" }
  end
  return { shell }
end

---@return integer
function M.spawn()
  local job = vim.fn.jobstart(M.shell_argv(), { term = true, detach = false })
  assert(type(job) == "number" and job > 0,
    "failed to start a terminal job: " .. tostring(job))
  return job
end

function M.start_insert()
  vim.cmd.startinsert()
end

local function tab_window_for(buffer)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == buffer then
      return win
    end
  end
end

local function float_options()
  local width = math.max(1, math.floor(vim.o.columns * 0.8))
  local height = math.max(1, math.floor((vim.o.lines - 2) * 0.8))
  return {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width, height = height,
    border = "rounded",
    style = "minimal",
  }
end

local function display(buffer, pos, on_open)
  local win
  if pos == "float" then
    win = vim.api.nvim_open_win(buffer, true, float_options())
  else
    vim.cmd(pos == "sp" and "split" or "vsplit")
    win = vim.api.nvim_get_current_win()
  end
  -- Record ownership before later window setup can throw or switch focus.
  on_open(win)
  if pos ~= "float" then
    vim.api.nvim_win_set_buf(win, buffer)
  end

  if pos == "sp" then
    vim.api.nvim_win_set_height(win,
      math.max(1, math.floor(vim.o.lines * 0.3)))
  elseif pos == "vsp" then
    vim.api.nvim_win_set_width(win,
      math.max(1, math.floor(vim.o.columns * 0.2)))
  end
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.bo[buffer].buflisted = false
  return win
end

---@return boolean
function M.can_toggle()
  local config = vim.api.nvim_win_get_config(0)
  if config.relative == "" then return true end
  -- A filetype is user-controlled; only a saved session owns a floating buffer.
  local current = vim.api.nvim_get_current_buf()
  for _, buffer in pairs(sessions) do
    if buffer == current and vim.api.nvim_buf_is_valid(buffer) then
      return true
    end
  end
  return false
end

---Create a terminal in a new split or floating window.
---@param pos 'sp'|'vsp'|'float'
---@param id? string
---@return integer
function M.open(pos, id)
  assert(kinds[pos], "invalid terminal position: " .. tostring(pos))
  local reuse = id and sessions[id]
  local buffer = reuse
    and vim.api.nvim_buf_is_valid(reuse)
    and reuse or nil
  if buffer and vim.bo[buffer].buftype == "terminal" then
    -- A terminal buffer remains valid after its PTY exits. Reopening it
    -- cannot restart the shell, so allocate a fresh buffer and job instead.
    local job = vim.b[buffer].terminal_job_id
    if type(job) ~= "number" or vim.fn.jobwait({ job }, 0)[1] ~= -1 then
      buffer = nil
    end
  end
  if not buffer then buffer = vim.api.nvim_create_buf(false, true) end
  local created = not (reuse and buffer == reuse)
  local origin = vim.api.nvim_get_current_win()
  local displayed
  local ok, err = xpcall(function()
    display(buffer, pos, function(win) displayed = win end)
    if created then M.spawn() end
    vim.bo[buffer].filetype = "Term_" .. pos
    M.start_insert()
  end, debug.traceback)

  if not ok then
    if displayed and displayed ~= origin
      and vim.api.nvim_win_is_valid(displayed)
    then
      pcall(vim.api.nvim_win_close, displayed, true)
    end
    if created and vim.api.nvim_buf_is_valid(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
    error(err, 0)
  end

  if id then sessions[id] = buffer end
  return buffer
end

---Toggle an owned terminal in this tab, or open its saved buffer.
---@param pos 'sp'|'vsp'|'float'
---@param id string
---@return boolean
function M.toggle(pos, id)
  assert(type(id) == "string" and id ~= "", "terminal id is required")
  if not M.can_toggle() then return false end
  local buffer = sessions[id]
  local win = buffer and vim.api.nvim_buf_is_valid(buffer)
    and tab_window_for(buffer) or nil
  if win then
    if vim.api.nvim_win_get_config(win).relative == "" then
      local other_normal = false
      for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if candidate ~= win
          and vim.api.nvim_win_get_config(candidate).relative == ""
        then
          other_normal = true
          break
        end
      end
      if not other_normal then
        -- Neovim cannot close the tab's last normal window. Hide the
        -- terminal in place so its session stays available for reopening.
        local replacement = vim.api.nvim_create_buf(true, false)
        local ok, err = pcall(vim.api.nvim_win_set_buf, win, replacement)
        if not ok then
          pcall(vim.api.nvim_buf_delete, replacement, { force = true })
          error(err, 0)
        end
        return true
      end
    end
    vim.api.nvim_win_close(win, true)
    return true
  end
  M.open(pos, id)
  return true
end

return M
