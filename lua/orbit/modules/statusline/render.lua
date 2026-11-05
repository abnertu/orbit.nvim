-- Render the global status line from native editor state.
local M = {}

---@type table<string, {[1]: string, [2]: string}>
local modes = {
  n = { "NORMAL", "Normal" },
  no = { "NORMAL", "Normal" },
  i = { "INSERT", "Insert" },
  ic = { "INSERT", "Insert" },
  v = { "VISUAL", "Visual" },
  V = { "V-LINE", "Visual" },
  ["\22"] = { "V-BLOCK", "Visual" },
  s = { "SELECT", "Select" },
  S = { "S-LINE", "Select" },
  ["\19"] = { "S-BLOCK", "Select" },
  R = { "REPLACE", "Replace" },
  Rv = { "V-REPLACE", "Replace" },
  c = { "COMMAND", "Command" },
  t = { "TERMINAL", "Terminal" },
  nt = { "NTERMINAL", "NTerminal" },
  r = { "PROMPT", "Confirm" },
  rm = { "MORE", "Confirm" },
  ["r?"] = { "CONFIRM", "Confirm" },
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
  local group = "OrbitStMode" .. item[2]
  return part(group .. "Sep", "")
    .. part(group, " " .. item[1])
    .. part(group .. "Sep", "")
end

---@param buffer integer
---@return string
local function file(buffer)
  local name = vim.api.nvim_buf_get_name(buffer)
  if vim.bo[buffer].buftype ~= "" or vim.bo[buffer].filetype == "NvimTree" then
    return ""
  end
  local relative = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":.")
  local segments = vim.split(relative:gsub("\\", "/"), "/", { plain = true })
  if #segments > 3 then
    segments = { segments[1], "…", segments[#segments - 1], segments[#segments] }
  end
  local tail = table.remove(segments) or relative
  local directory = #segments > 0 and table.concat(segments, "/") .. "/" or ""
  local glyph, highlight = require("orbit.modules.icons.render").file(name, "OrbitStFile")
  local modified = vim.bo[buffer].modified and " ●" or ""
  return part(highlight, glyph .. " ")
    .. part("OrbitStPath", escape(directory))
    .. part("OrbitStFile", escape(tail) .. modified)
end

local function git(buffer)
  local head = vim.b[buffer].gitsigns_head
  if type(head) ~= "string" or head == "" or vim.b[buffer].gitsigns_git_status then
    return ""
  end
  local text = " " .. escape(head)
  local status = vim.b[buffer].gitsigns_status_dict
  if type(status) == "table" then
    for _, item in ipairs({ { "added", " " }, { "changed", " " }, { "removed", " " } }) do
      local count = status[item[1]]
      if type(count) == "number" and count > 0 then
        text = text .. " " .. item[2] .. count
      end
    end
  end
  return part("OrbitStGit", text)
end

local function diagnostics(buffer)
  local counts = vim.diagnostic.count(buffer)
  local result = {}
  local severities = {
    { vim.diagnostic.severity.ERROR, " ", "OrbitStError" },
    { vim.diagnostic.severity.WARN, " ", "OrbitStWarn" },
    { vim.diagnostic.severity.HINT, "󰛩 ", "OrbitStHint" },
    { vim.diagnostic.severity.INFO, "󰋼 ", "OrbitStInfo" },
  }
  for _, item in ipairs(severities) do
    local count = counts[item[1]]
    if count and count > 0 then
      result[#result + 1] = part(item[3], item[2] .. count)
    end
  end
  return table.concat(result, " ")
end

---Return the blank cells between sections, in the fill color.
---@return string
local function gap()
  local width = require("orbit.modules.statusline").gap()
  return width > 0 and part("OrbitStFill", string.rep(" ", width)) or ""
end

---Join non-empty sections, so an empty section leaves no extra gap.
---@param sections string[]
---@param spacer string
---@return string
local function join(sections, spacer)
  local visible = {}
  for _, section in ipairs(sections) do
    if section ~= "" then
      visible[#visible + 1] = section
    end
  end
  return table.concat(visible, spacer)
end

---@param buffer integer
---@return string
local function ai(buffer)
  local clients = vim.lsp.get_clients({ bufnr = buffer, name = "copilot" })
  return #clients > 0 and part("OrbitStAi", "") or ""
end

---@param buffer integer
---@return string
local function lsp(buffer)
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
    if client.name ~= "copilot" then
      names[#names + 1] = client.name
    end
  end
  if #names == 0 then
    return ""
  end
  table.sort(names)
  return part(
    "OrbitStLsp",
    "  LSP" .. (vim.o.columns > 100 and " ~ " .. escape(table.concat(names, ", ")) or "")
  )
end

---@param separator string
---@return string
local function position(separator)
  return part(separator, "") .. part("OrbitStPosIcon", " ") .. part("OrbitStPos", " %l/%v ")
end

-- The cwd and position blocks form one pill; their seam takes no gap.
---@return string
local function workspace()
  if vim.o.columns <= 85 then
    return position("OrbitStPosSep")
  end
  return part("OrbitStCwdSep", "")
    .. part("OrbitStCwdIcon", "󰉋 ")
    .. part("OrbitStCwd", " " .. escape(vim.fn.fnamemodify(vim.fn.getcwd(), ":t")) .. " ")
    .. position("OrbitStPosSepMid")
end

---@return string
local function recording()
  local register = vim.fn.reg_recording()
  return register == "" and "" or part("OrbitStWarn", "󰑊 " .. escape(register))
end

---@return string
function M.render()
  local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_win_get_buf(win)
  local spacer = gap()
  local tail = join({
    git(buffer),
    file(buffer),
    require("orbit.modules.statusline.symbols").render(),
  }, spacer)
  return join({ mode(), recording() }, spacer)
    .. "%<"
    .. (tail ~= "" and spacer .. tail or "")
    .. spacer
    .. part("OrbitStFill", "%=")
    .. join({ diagnostics(buffer), ai(buffer), lsp(buffer), workspace() }, spacer)
end

-- Default groups link to standard ones, so colorschemes can override them.
local defaults = {
  OrbitStModeNormal = "PmenuSel",
  OrbitStModeInsert = "DiffAdd",
  OrbitStModeVisual = "Visual",
  OrbitStModeReplace = "DiffDelete",
  OrbitStModeCommand = "DiffChange",
  OrbitStModeTerminal = "DiffText",
  OrbitStFile = "StatusLine",
  OrbitStGit = "StatusLine",
  OrbitStFill = "StatusLine",
  OrbitStError = "DiagnosticError",
  OrbitStWarn = "DiagnosticWarn",
  OrbitStInfo = "DiagnosticInfo",
  OrbitStHint = "DiagnosticHint",
  OrbitStLsp = "StatusLine",
  OrbitStCwd = "StatusLine",
  OrbitStPos = "PmenuSel",
  OrbitStAi = "Special",
  OrbitStPath = "Comment",
  OrbitStSymbols = "StatusLine",
  OrbitStSymbolSep = "StatusLine",
  OrbitStCwdIcon = "StatusLine",
  OrbitStCwdSep = "StatusLine",
  OrbitStPosIcon = "PmenuSel",
  OrbitStPosSep = "StatusLine",
  OrbitStPosSepMid = "StatusLine",
  OrbitStModeSelect = "Visual",
  OrbitStModeNTerminal = "DiffChange",
  OrbitStModeConfirm = "Question",
}
---Define default links. Colorscheme changes clear them, so the owner
---calls this again after each ColorScheme event.
function M.define_highlights()
  for name, target in pairs(defaults) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  for _, suffix in ipairs({
    "Normal",
    "Insert",
    "Visual",
    "Replace",
    "Command",
    "Terminal",
    "Select",
    "NTerminal",
    "Confirm",
  }) do
    vim.api.nvim_set_hl(
      0,
      "OrbitStMode" .. suffix .. "Sep",
      { link = "StatusLine", default = true }
    )
  end
end

M.define_highlights()

return M
