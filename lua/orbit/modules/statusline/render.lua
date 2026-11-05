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

---Each redraw passes one context to every component.
---@class Orbit.StatuslineContext
---@field buffer integer
---@field win integer
---@field width integer Status line width in cells.

---A component returns content without outer blank cells, or "" when empty.
---@alias Orbit.StatuslineComponent fun(ctx: Orbit.StatuslineContext): string
---@class Orbit.StatuslineContainer
---@field kind "container"
---@field children Orbit.StatuslineChild[]
---@field gap? integer
---@class Orbit.StatuslineSpacer
---@field kind "spacer"|"separator"
---@field width? integer
---@class Orbit.StatuslineMarker
---@field kind "marker"
---@field text string
---@field boundary? boolean A side boundary ends the current spacer run.
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

---A dim divider glyph with one gap on each side. It follows the spacer rules,
---and a merged run that holds a separator renders the separator.
---@return Orbit.StatuslineSpacer
function M.separator()
  return { kind = "separator" }
end

---The flexible fill between the left and right sides.
---@return Orbit.StatuslineMarker
function M.fill()
  return { kind = "marker", text = "%#OrbitStFill#%=", boundary = true }
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
---@param ctx Orbit.StatuslineContext
---@param default integer
---@return string
local function evaluate(item, ctx, default)
  if type(item) == "function" then
    return item(ctx)
  end
  local visible = {}
  for _, child in ipairs(item.children) do
    local text = evaluate(child, ctx, default)
    if text ~= "" then
      visible[#visible + 1] = text
    end
  end
  return table.concat(visible, blank(item.gap or default))
end

---@param win integer
---@return Orbit.StatuslineContext
local function context(win)
  local global = vim.o.laststatus == 3
  return {
    buffer = vim.api.nvim_win_get_buf(win),
    win = win,
    width = global and vim.o.columns or vim.api.nvim_win_get_width(win),
  }
end

---Render a layout for one window.
---@param layout Orbit.StatuslineItem[]
---@param win integer
---@return string
function M.compose(layout, win)
  local ctx = context(win)
  local default = require("orbit.modules.statusline").gap()
  local output, seen = {}, false
  ---@type {index: integer, width: integer, separator: boolean}?
  local pending
  for _, item in ipairs(layout) do
    local kind = type(item) == "table" and item.kind or nil
    if kind == "spacer" or kind == "separator" then
      local cells = item.width or default
      -- A spacer before any content has nothing to separate.
      if pending then
        pending.width = math.max(pending.width, cells)
        pending.separator = pending.separator or kind == "separator"
      elseif seen then
        output[#output + 1] = ""
        pending = { index = #output, width = cells, separator = kind == "separator" }
      end
    elseif kind == "marker" then
      if item.boundary then
        -- A run never crosses the fill: it keeps blank space before the fill,
        -- and the next side starts like the line start.
        if pending then
          output[pending.index] = blank(pending.width)
          pending = nil
        end
        seen = false
      end
      output[#output + 1] = item.text
    else
      local text = evaluate(item, ctx, default)
      if text ~= "" then
        if pending then
          local space = blank(pending.width)
          output[pending.index] = pending.separator
              and space .. part("OrbitStDivider", "·") .. space
            or space
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

-- Narrow status lines drop detail in this order. Mode, file name and position stay.
local minimum = { symbols = 120, lsp = 100, git_counts = 90, detail = 80, git = 60 }

---@return string
local function mode()
  local current = vim.api.nvim_get_mode().mode
  local item = modes[current] or modes[current:sub(1, 1)] or { current:upper(), "Normal" }
  return part("OrbitStMode" .. item[2], "▌ " .. item[1])
end

---@return string
local function recording()
  local register = vim.fn.reg_recording()
  return register == "" and "" or part("OrbitStWarn", "\u{F044A} " .. escape(register))
end

---@param ctx Orbit.StatuslineContext
---@return string
local function git(ctx)
  local buffer = ctx.buffer
  local head = vim.b[buffer].gitsigns_head
  if
    ctx.width < minimum.git
    or type(head) ~= "string"
    or head == ""
    or vim.b[buffer].gitsigns_git_status
  then
    return ""
  end
  local text = part("OrbitStGit", escape(head))
  local status = vim.b[buffer].gitsigns_status_dict
  if type(status) == "table" and ctx.width >= minimum.git_counts then
    for _, item in ipairs({
      { "added", "+", "OrbitStGitAdd" },
      { "changed", "~", "OrbitStGitChange" },
      { "removed", "-", "OrbitStGitDelete" },
    }) do
      local count = status[item[1]]
      if type(count) == "number" and count > 0 then
        text = text .. part(item[3], " " .. item[2] .. count)
      end
    end
  end
  return text
end

---@param ctx Orbit.StatuslineContext
---@return string
local function file(ctx)
  local buffer = ctx.buffer
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
  local directory = #segments > 0
      and ctx.width >= minimum.detail
      and table.concat(segments, "/") .. "/"
    or ""
  local glyph, highlight = require("orbit.modules.icons.render").file(name, "OrbitStFile")
  local modified = vim.bo[buffer].modified and part("OrbitStModified", " ●") or ""
  return part(highlight, glyph .. " ")
    .. part("OrbitStPath", escape(directory))
    .. part("OrbitStFile", escape(tail))
    .. modified
end

---Name a terminal, help, list or plugin buffer. File buffers return "".
---@param ctx Orbit.StatuslineContext
---@return string
local function label(ctx)
  local buftype = vim.bo[ctx.buffer].buftype
  if buftype == "" then
    return ""
  end
  local name = vim.api.nvim_buf_get_name(ctx.buffer)
  if buftype == "terminal" then
    -- term://{cwd}//{pid}:{command}
    local command = name:match("^term://.-//%d+:(.*)$") or name
    -- A program path with spaces arrives quoted.
    local program = command:match('^"([^"]+)"')
      or command:match("^'([^']+)'")
      or command:match("^%S+")
      or command
    program = vim.fn.fnamemodify(program, ":t"):gsub("%.exe$", "")
    return part("OrbitStFile", "\u{F120} " .. escape(program))
  elseif buftype == "help" then
    return part("OrbitStDim", "help ")
      .. part("OrbitStFile", escape(vim.fn.fnamemodify(name, ":t:r")))
  elseif buftype == "quickfix" then
    local info = vim.fn.getwininfo(ctx.win)[1] or {}
    local title = vim.w[ctx.win].quickfix_title
    return part("OrbitStFile", info.loclist == 1 and "location list" or "quickfix")
      .. (
        type(title) == "string" and title ~= "" and part("OrbitStDim", " " .. escape(title)) or ""
      )
  end
  local filetype = vim.bo[ctx.buffer].filetype
  return part("OrbitStFile", escape(filetype ~= "" and filetype or buftype))
end

---@param ctx Orbit.StatuslineContext
---@return string
local function symbols(ctx)
  if ctx.width < minimum.symbols or vim.bo[ctx.buffer].buftype ~= "" then
    return ""
  end
  return require("orbit.modules.statusline.symbols").render()
end

---@param ctx Orbit.StatuslineContext
---@return string
local function diagnostics(ctx)
  local counts = vim.diagnostic.count(ctx.buffer)
  local result = {}
  for _, item in ipairs({
    { vim.diagnostic.severity.ERROR, "\u{F057} ", "OrbitStError" },
    { vim.diagnostic.severity.WARN, "\u{F071} ", "OrbitStWarn" },
    { vim.diagnostic.severity.HINT, "\u{F06E9} ", "OrbitStHint" },
    { vim.diagnostic.severity.INFO, "\u{F02FC} ", "OrbitStInfo" },
  }) do
    local count = counts[item[1]]
    if count and count > 0 then
      result[#result + 1] = part(item[3], item[2] .. count)
    end
  end
  return table.concat(result, " ")
end

---@param ctx Orbit.StatuslineContext
---@return string
local function lsp(ctx)
  if ctx.width < minimum.lsp then
    return ""
  end
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = ctx.buffer })) do
    if client.name ~= "copilot" then
      names[#names + 1] = client.name
    end
  end
  table.sort(names)
  return #names > 0 and part("OrbitStLsp", escape(table.concat(names, " "))) or ""
end

---@param ctx Orbit.StatuslineContext
---@return string
local function position(ctx)
  if vim.bo[ctx.buffer].buftype == "terminal" then
    return ""
  end
  return part("OrbitStPos", "%l:%v")
    .. (ctx.width >= minimum.detail and part("OrbitStDim", " %P") or "")
end

-- Flat sections with dim dividers. Only the mode bar carries an accent color.
---@type Orbit.StatuslineItem[]
local layout = {
  M.container({ mode, recording }),
  M.separator(),
  git,
  M.separator(),
  -- A long line cuts the path from its start and keeps the mode and branch.
  M.truncate(),
  M.container({ file, label, symbols }),
  -- A blank spacer, so no divider is drawn across the fill.
  M.spacer(),
  M.fill(),
  diagnostics,
  M.separator(),
  lsp,
  M.separator(),
  position,
}

---@return string
function M.render()
  local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
  return M.compose(layout, win)
end

-- Default groups link to standard ones, so colorschemes can override them.
local defaults = {
  OrbitStModeNormal = "Function",
  OrbitStModeInsert = "String",
  OrbitStModeVisual = "Statement",
  OrbitStModeReplace = "DiagnosticError",
  OrbitStModeCommand = "Constant",
  OrbitStModeTerminal = "Special",
  OrbitStModeSelect = "Statement",
  OrbitStModeNTerminal = "Constant",
  OrbitStModeConfirm = "Question",
  OrbitStFill = "StatusLine",
  OrbitStDivider = "Comment",
  OrbitStDim = "Comment",
  OrbitStFile = "StatusLine",
  OrbitStPath = "Comment",
  OrbitStModified = "DiagnosticWarn",
  OrbitStGit = "Comment",
  OrbitStGitAdd = "Added",
  OrbitStGitChange = "Changed",
  OrbitStGitDelete = "Removed",
  OrbitStSymbols = "StatusLine",
  OrbitStSymbolSep = "Comment",
  OrbitStError = "DiagnosticError",
  OrbitStWarn = "DiagnosticWarn",
  OrbitStInfo = "DiagnosticInfo",
  OrbitStHint = "DiagnosticHint",
  OrbitStLsp = "Comment",
  OrbitStPos = "StatusLine",
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
