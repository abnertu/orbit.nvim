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

---A component returns content without outer blank cells, or "" when empty.
---@alias Orbit.StatuslineComponent fun(buffer: integer): string
---@class Orbit.StatuslineContainer
---@field kind "container"
---@field children Orbit.StatuslineChild[]
---@field gap? integer
---@class Orbit.StatuslineSpacer
---@field kind "spacer"
---@field width? integer
---@class Orbit.StatuslineMarker
---@field kind "marker"
---@field text string
---@alias Orbit.StatuslineChild Orbit.StatuslineComponent|Orbit.StatuslineContainer
---@alias Orbit.StatuslineItem Orbit.StatuslineChild|Orbit.StatuslineSpacer|Orbit.StatuslineMarker

---@param value? integer
---@param label string
---@return integer?
local function width(value, label)
  assert(
    value == nil or (type(value) == "number" and value >= 0 and value % 1 == 0),
    label .. " must be a non-negative integer"
  )
  return value
end

---Group children and join the non-empty ones with `gap` blank cells.
---A missing `gap` uses `modules.statusline.gap` at each redraw.
---@param children Orbit.StatuslineChild[]
---@param opts? {gap?: integer}
---@return Orbit.StatuslineContainer
function M.container(children, opts)
  opts = opts or {}
  for index, child in ipairs(children) do
    assert(
      type(child) == "function" or (type(child) == "table" and child.kind == "container"),
      "container child " .. index .. " must be a component or a container"
    )
  end
  return { kind = "container", children = children, gap = width(opts.gap, "container gap") }
end

---Blank cells between layout items. They render only between visible content,
---and adjacent spacers render once at the largest width.
---A missing `n` uses `modules.statusline.gap` at each redraw.
---@param n? integer
---@return Orbit.StatuslineSpacer
function M.spacer(n)
  return { kind = "spacer", width = width(n, "spacer width") }
end

---The flexible fill between the left and right sides.
---@return Orbit.StatuslineMarker
function M.fill()
  return { kind = "marker", text = "%#OrbitStFill#%=" }
end

---The point where a long status line starts truncation.
---@return Orbit.StatuslineMarker
function M.truncate()
  return { kind = "marker", text = "%<" }
end

---@param cells integer
---@return string
local function blank(cells)
  return cells > 0 and part("OrbitStFill", string.rep(" ", cells)) or ""
end

---@param item Orbit.StatuslineChild
---@param buffer integer
---@param default integer
---@return string
local function evaluate(item, buffer, default)
  if type(item) == "function" then
    return item(buffer)
  end
  local visible = {}
  for _, child in ipairs(item.children) do
    local text = evaluate(child, buffer, default)
    if text ~= "" then
      visible[#visible + 1] = text
    end
  end
  return table.concat(visible, blank(item.gap or default))
end

---Render a layout for one buffer.
---@param layout Orbit.StatuslineItem[]
---@param buffer integer
---@return string
function M.compose(layout, buffer)
  local default = require("orbit.modules.statusline").gap()
  local output, seen = {}, false
  ---@type {index: integer, width: integer}?
  local pending
  for _, item in ipairs(layout) do
    local kind = type(item) == "table" and item.kind or nil
    if kind == "spacer" then
      local cells = item.width or default
      -- A spacer before any content has nothing to separate.
      if pending then
        pending.width = math.max(pending.width, cells)
      elseif seen then
        output[#output + 1] = ""
        pending = { index = #output, width = cells }
      end
    elseif kind == "marker" then
      output[#output + 1] = item.text
    else
      local text = evaluate(item, buffer, default)
      if text ~= "" then
        if pending then
          output[pending.index] = blank(pending.width)
          pending = nil
        end
        output[#output + 1] = text
        seen = true
      end
    end
  end
  -- A trailing pending spacer stays empty.
  return table.concat(output)
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
local function symbols()
  return require("orbit.modules.statusline.symbols").render()
end

---@type Orbit.StatuslineItem[]
local layout = {
  M.container({ mode, recording }),
  M.truncate(),
  M.spacer(),
  M.container({ git, file, symbols }),
  M.spacer(),
  M.fill(),
  M.container({ diagnostics, ai, lsp, workspace }),
}

---@return string
function M.render()
  local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
  return M.compose(layout, vim.api.nvim_win_get_buf(win))
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
