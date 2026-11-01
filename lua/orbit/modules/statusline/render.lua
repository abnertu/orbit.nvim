-- Render the global status line from native editor state.
local M = {}

---@type table<string, {[1]: string, [2]: string}>
local modes = {
  n = { "NORMAL", "Normal" }, no = { "NORMAL", "Normal" },
  i = { "INSERT", "Insert" }, ic = { "INSERT", "Insert" },
  v = { "VISUAL", "Visual" }, V = { "V-LINE", "Visual" }, ["\22"] = { "V-BLOCK", "Visual" },
  s = { "SELECT", "Visual" }, S = { "S-LINE", "Visual" }, ["\19"] = { "S-BLOCK", "Visual" },
  R = { "REPLACE", "Replace" }, Rv = { "V-REPLACE", "Replace" },
  c = { "COMMAND", "Command" }, t = { "TERMINAL", "Terminal" }, nt = { "N-TERMINAL", "Normal" },
}

-- Escape user-controlled text so it cannot inject statusline items.
---@param text string
---@return string
local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

---@param group string
---@param text string
---@return string
local function part(group, text)
  return "%#" .. group .. "#" .. text
end

local function mode()
  local current = vim.api.nvim_get_mode().mode
  local item = modes[current] or modes[current:sub(1, 1)] or { current:upper(), "Normal" }
  return part("OrbitStMode" .. item[2], " " .. item[1] .. " ")
end

local function file(buffer)
  local name = vim.api.nvim_buf_get_name(buffer)
  local tail = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":t")
  local icon = ""
  local icons = package.loaded["mini.icons"]
  if icons and name ~= "" then
    local ok, glyph = pcall(icons.get, "file", tail)
    if ok and glyph then icon = glyph .. " " end
  end
  local modified = vim.bo[buffer].modified and " ●" or ""
  return part("OrbitStFile", " " .. escape(icon .. tail) .. modified .. " ")
end

local function git(buffer)
  local head = vim.b[buffer].gitsigns_head
  if type(head) ~= "string" or head == "" then return "" end
  local text = "  " .. escape(head)
  local status = vim.b[buffer].gitsigns_status_dict
  if type(status) == "table" then
    for _, item in ipairs({ { "added", "+" }, { "changed", "~" }, { "removed", "-" } }) do
      local count = status[item[1]]
      if type(count) == "number" and count > 0 then text = text .. " " .. item[2] .. count end
    end
  end
  return part("OrbitStGit", text .. " ")
end

local function diagnostics(buffer)
  local counts = vim.diagnostic.count(buffer)
  local result = {}
  local severities = {
    { vim.diagnostic.severity.ERROR, "E", "OrbitStError" },
    { vim.diagnostic.severity.WARN, "W", "OrbitStWarn" },
    { vim.diagnostic.severity.INFO, "I", "OrbitStInfo" },
    { vim.diagnostic.severity.HINT, "H", "OrbitStHint" },
  }
  for _, item in ipairs(severities) do
    local count = counts[item[1]]
    if count and count > 0 then result[#result + 1] = part(item[3], " " .. item[2] .. count) end
  end
  return table.concat(result)
end

local function lsp(buffer)
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
    names[#names + 1] = client.name
  end
  if #names == 0 then return "" end
  table.sort(names)
  return part("OrbitStLsp", "  " .. escape(table.concat(names, ", ")) .. " ")
end

local function cwd()
  return part("OrbitStCwd", " 󰉋 " .. escape(vim.fn.fnamemodify(vim.fn.getcwd(), ":t")) .. " ")
end

---@return string
function M.render()
  local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_win_get_buf(win)
  return table.concat({
    mode(), file(buffer), git(buffer), part("OrbitStFill", "%="),
    diagnostics(buffer), lsp(buffer), cwd(), part("OrbitStPos", " %l:%c %P "),
  })
end

-- Default groups link to standard ones, so colorschemes can override them.
local defaults = {
  OrbitStModeNormal = "PmenuSel", OrbitStModeInsert = "DiffAdd", OrbitStModeVisual = "Visual",
  OrbitStModeReplace = "DiffDelete", OrbitStModeCommand = "DiffChange",
  OrbitStModeTerminal = "DiffText", OrbitStFile = "StatusLine", OrbitStGit = "StatusLine",
  OrbitStFill = "StatusLine", OrbitStError = "DiagnosticError", OrbitStWarn = "DiagnosticWarn",
  OrbitStInfo = "DiagnosticInfo", OrbitStHint = "DiagnosticHint", OrbitStLsp = "StatusLine",
  OrbitStCwd = "StatusLine", OrbitStPos = "PmenuSel",
}
---Define default links. Colorscheme changes clear them, so the owner
---calls this again after each ColorScheme event.
function M.define_highlights()
  for name, target in pairs(defaults) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

M.define_highlights()

return M
