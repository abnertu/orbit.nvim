local M = {}

---@type Orbit.TerminalShellOption[]
local option_names = {
  "shell",
  "shellcmdflag",
  "shellredir",
  "shellpipe",
  "shellquote",
  "shellxquote",
  "shelltemp",
}

-- PowerShell must initialize its own console encoding and preserve pipeline status.
-- These command fragments configure PowerShell; Lua cannot replace shell syntax here.
local command_flags = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command "
  .. "[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();"
  .. "$PSDefaultParameterValues['Out-File:Encoding']='utf8';$LASTEXITCODE=$null;$Error.Clear();"
local capture = "2>&1 | Out-File -Encoding UTF8 %s;"
  .. " $orbitShellSuccess=$?; if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0)"
  .. " { exit $LASTEXITCODE }; if ((-not $orbitShellSuccess -and $null -eq $LASTEXITCODE)"
  .. " -or @($Error | Where-Object { $_.FullyQualifiedErrorId -notlike 'NativeCommandError*' })"
  .. ".Count -gt 0) { exit 1 }; exit 0"
---@type table<Orbit.TerminalShellOption, Orbit.TerminalShellValue>
local command_options = {
  shellcmdflag = command_flags,
  shellredir = capture,
  shellpipe = capture,
  shellquote = "",
  shellxquote = "",
  shelltemp = false,
}
local interactive_flags = { "-NoLogo" }
---@type Orbit.TerminalShellProfile[]
local profiles = {
  {
    executable = "pwsh.exe",
    interactive = interactive_flags,
    options = vim.tbl_extend("force", command_options, {
      shellcmdflag = command_flags
        .. "if ($null -ne $PSStyle) { $PSStyle.OutputRendering='PlainText' };",
    }),
  },
  { executable = "powershell.exe", interactive = interactive_flags, options = command_options },
}

---@type table<Orbit.TerminalShellOption, Orbit.TerminalShellEntry>?
local entries
local active, writing = false, false
local observing = false
---@type table<Orbit.TerminalShellOption, Orbit.TerminalShellValue>?
local pending
local write_source =
  vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "apply.lua")

---@return table<Orbit.TerminalShellOption, Orbit.TerminalShellValue>
local function values()
  local result = {}
  for _, name in ipairs(option_names) do
    result[name] = vim.api.nvim_get_option_value(name, { scope = "global" })
  end
  return result
end

---Keep provenance after release: restoring values cannot clear Neovim's was_set bit.
local function refresh()
  if not entries then
    entries = {}
    for name, value in pairs(values()) do
      local info = vim.api.nvim_get_option_info2(name, {})
      entries[name] = {
        original = value,
        observed = value,
        source = info.last_set_sid,
        explicit = info.was_set,
      }
    end
  end
  for name, value in pairs(values()) do
    local entry = entries[name]
    local source = vim.api.nvim_get_option_info2(name, {}).last_set_sid
    if value ~= entry.observed or source ~= entry.source then
      entry.original, entry.observed, entry.explicit, entry.owned = value, value, true, nil
      entry.source = source
    end
  end
end

---@param desired table<Orbit.TerminalShellOption, Orbit.TerminalShellValue>
local function write(desired)
  writing, pending = true, desired
  local ok, err = pcall(function()
    vim.cmd.source({ args = { write_source }, mods = { noautocmd = true } })
  end)
  writing, pending = false, nil
  if not ok then
    error(err, 0)
  end
  for name, value in pairs(values()) do
    entries[name].observed = value
    entries[name].source = vim.api.nvim_get_option_info2(name, {}).last_set_sid
  end
end

---Called only by the sourced Lua bridge to give owned writes their own script ID.
---@private
function M.apply_pending()
  assert(writing and pending, "no pending terminal shell options")
  -- Restore shell first: setting it can change defaults for the other options.
  for _, name in ipairs(option_names) do
    if vim.api.nvim_get_option_value(name, { scope = "global" }) ~= pending[name] then
      vim.api.nvim_set_option_value(name, pending[name], { scope = "global" })
    end
  end
end

local function observe()
  if observing then
    return
  end
  local group = vim.api.nvim_create_augroup("OrbitTerminalShell", { clear = true })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = option_names,
    callback = function(event)
      if writing then
        return
      end
      local entry = entries[event.match]
      local value = vim.api.nvim_get_option_value(event.match, { scope = "global" })
      entry.original, entry.observed, entry.explicit, entry.owned = value, value, true, nil
      entry.source = vim.api.nvim_get_option_info2(event.match, {}).last_set_sid
      if active and event.match == "shell" then
        M.setup(true)
      end
    end,
  })
  -- Remain a passive observer after release so same-value user writes stay explicit.
  observing = true
end

---@param shell string
---@return string[]
local function split(shell)
  if vim.fn.executable(shell) == 1 then
    return { shell }
  end
  local args, pos = {}, 1
  while true do
    local _, last, argument = shell:find('^%s*"([^"]*)"', pos)
    if not last then
      _, last, argument = shell:find("^%s*(%S+)", pos)
    end
    if not last then
      break
    end
    args[#args + 1] = argument
    pos = last + 1
  end
  return args
end

---@param executable string
---@return Orbit.TerminalShellProfile?
local function profile(executable)
  local name = (executable:match("[^/\\]+$") or ""):lower():gsub("%.exe$", "")
  for _, candidate in ipairs(profiles) do
    if name == candidate.executable:gsub("%.exe$", "") then
      return candidate
    end
  end
end

---@return Orbit.TerminalShellSnapshot?
function M.capture()
  if vim.fn.has("win32") ~= 1 then
    return
  end
  refresh()
  return { values = values(), entries = vim.deepcopy(entries), active = active }
end

---@param snapshot Orbit.TerminalShellSnapshot?
function M.restore(snapshot)
  if snapshot then
    entries = vim.deepcopy(snapshot.entries)
    write(snapshot.values)
    active = snapshot.active
  end
end

---@param enabled boolean
function M.setup(enabled)
  if vim.fn.has("win32") ~= 1 then
    return
  end
  refresh()
  observe()
  local desired = values()
  for name, entry in pairs(entries) do
    if entry.owned ~= nil and desired[name] == entry.owned then
      desired[name] = entry.original
    end
    entry.owned = nil
  end
  if enabled then
    if not entries.shell.explicit then
      for _, candidate in ipairs(profiles) do
        if vim.fn.executable(candidate.executable) == 1 then
          desired.shell = candidate.executable
          entries.shell.owned = desired.shell
          break
        end
      end
    end
    local selected = profile(split(desired.shell)[1] or "")
    if selected then
      for name, value in pairs(selected.options) do
        if not entries[name].explicit then
          desired[name], entries[name].owned = value, value
        end
      end
    end
  end
  write(desired)
  active = enabled
end

---@return string[]
function M.argv()
  local args = split(vim.o.shell)
  local selected = vim.fn.has("win32") == 1 and profile(args[1] or "") or nil
  if #args == 1 and selected then
    vim.list_extend(args, selected.interactive)
  end
  return args
end

return M
