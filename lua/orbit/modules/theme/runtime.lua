-- Apply the selected colorscheme and Orbit highlight overrides.
-- The runtime is inert until the colorscheme plugin starts it.
local M = {}

---@alias Orbit.ThemeRuntimeState {started: boolean, colorscheme?: string, highlights: boolean}

local group_name = "OrbitTheme"
local started = false
---@type Orbit.ThemeOptions?
local options

---@param group string
---@param attr 'fg'|'bg'
---@return integer?
local function color(group, attr)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  return ok and hl[attr] or nil
end

---Blend `from` toward `to` by `percent` of the distance.
---@param from integer
---@param to integer
---@param percent number
---@return integer
local function mix(from, to, percent)
  local result = 0
  for shift = 16, 0, -8 do
    local a = bit.band(bit.rshift(from, shift), 0xff)
    local b = bit.band(bit.rshift(to, shift), 0xff)
    local channel = math.floor(a + (b - a) * percent / 100 + 0.5)
    result = result + bit.lshift(channel, shift)
  end
  return result
end

---@class Orbit.ThemePalette
---@field red integer
---@field yellow integer
---@field green integer
---@field blue integer
---@field purple integer
---@field grey integer
---@field white integer
---@field black integer
---@field one_bg integer

-- Derive named colors from standard groups so any colorscheme works.
---@return Orbit.ThemePalette
function M.palette()
  local dark = vim.o.background == "dark"
  local bg = color("Normal", "bg") or (dark and 0x1a1b26 or 0xe1e2e7)
  local fg = color("Normal", "fg") or (dark and 0xc0caf5 or 0x3760bf)
  return {
    red = color("DiagnosticError", "fg") or 0xf7768e,
    yellow = color("DiagnosticWarn", "fg") or 0xe0af68,
    green = color("String", "fg") or 0x9ece6a,
    blue = color("Function", "fg") or 0x7aa2f7,
    purple = color("Statement", "fg") or 0xbb9af7,
    grey = color("Comment", "fg") or mix(fg, bg, 50),
    white = fg,
    black = mix(bg, dark and 0 or 0xffffff, 15),
    one_bg = mix(bg, fg, 8),
  }
end

---@param c Orbit.ThemePalette
---@return table<string, vim.api.keyset.highlight>
function M.groups(c)
  local curl = { undercurl = true }
  return {
    ["@comment"] = { fg = c.grey, italic = true },
    ["@comment.todo"] = { fg = c.black, bg = c.green },
    Comment = { fg = c.grey, italic = true },
    IblChar = { fg = c.grey },
    IblScopeChar = { fg = c.purple },
    NvimTreeOpenedFolderName = { fg = c.green, bold = true },
    TreesitterContext = { link = "CursorLine" },
    LspInlayHint = { fg = 0x808080, bg = c.one_bg, italic = true },
    DevIconDefault = { fg = c.white },
    MiniIconsGrey = { link = "DevIconDefault" },
    NormalFloat = { fg = c.white, bg = c.black },
    FloatBorder = { fg = c.blue, bg = c.black },
    FloatTitle = { fg = c.blue, bg = c.black },
    active_context = { fg = c.blue },
    CmpGhostText = { link = "Comment", default = true },
    DapBreakpointColor = { fg = c.red },
    HangarCategoryActive = { fg = c.black, bg = c.green },
    HangarCategoryInactive = { fg = c.grey, bg = c.one_bg },
    NoiceCmdlineIcon = { fg = c.purple },
    NoiceCmdlinePopupBorder = { fg = c.green },
    NoiceCmdlinePopup = { bg = c.black },
    NoiceMini = { bg = c.black },
    NoiceCmdlinePopupBorderSearch = { fg = c.yellow },
    NoiceCmdlinePopupTitle = { fg = c.blue },
    NoicePopupBorder = { fg = c.blue },
    SnacksLazygitActiveBorder = { fg = c.purple, bold = true },
    SnacksPickerMatch = { fg = c.green, bold = true },
    SnacksPickerDir = { fg = c.blue },
    SnacksPickerPathHidden = { fg = c.blue },
    DiagnosticUnderlineError = vim.tbl_extend("force", curl, { sp = c.red }),
    DiagnosticUnderlineWarn = vim.tbl_extend("force", curl, { sp = c.yellow }),
    DiagnosticUnderlineInfo = vim.tbl_extend("force", curl, { sp = c.green }),
    DiagnosticUnderlineHint = vim.tbl_extend("force", curl, { sp = c.purple }),
    DiagnosticVirtualTextError = { fg = c.red, bg = mix(c.red, c.black, 75) },
    DiagnosticVirtualTextWarn = { fg = c.yellow, bg = mix(c.yellow, c.black, 75) },
    DiagnosticVirtualTextInfo = { fg = c.green, bg = mix(c.green, c.black, 75) },
    DiagnosticVirtualTextHint = { fg = c.purple, bg = mix(c.purple, c.black, 75) },
  }
end

function M.apply_highlights()
  for name, spec in pairs(M.groups(M.palette())) do
    vim.api.nvim_set_hl(0, name, spec)
  end
end

local function sync_group()
  pcall(vim.api.nvim_del_augroup_by_name, group_name)
  if not (started and options and options.highlights) then return end
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = M.apply_highlights,
    desc = "Apply Orbit highlight overrides",
  })
end

---@param name string
---@return boolean
function M.apply(name)
  local ok, err = pcall(vim.cmd.colorscheme, name)
  if not ok then
    vim.notify("[theme] " .. tostring(err), vim.log.levels.WARN)
  end
  return ok
end

local function activate()
  sync_group()
  if not options then return end
  if vim.g.colors_name ~= options.colorscheme then
    M.apply(options.colorscheme)
  elseif options.highlights then
    M.apply_highlights()
  end
end

---Start applying themes. Lazy calls this once from the colorscheme plugin.
function M.start()
  started = true
  options = options or require("orbit.modules.theme").current_options()
  activate()
end

---@param next_options Orbit.ThemeOptions
function M.update(next_options)
  local had_highlights = options ~= nil and options.highlights
  options = vim.deepcopy(next_options)
  if not started then return end
  activate()
  -- Reapplying the scheme removes overrides that are no longer wanted.
  if had_highlights and not options.highlights and vim.g.colors_name then
    M.apply(vim.g.colors_name)
  end
end

---@return Orbit.ThemeRuntimeState
function M.capture()
  return {
    started = started,
    colorscheme = vim.g.colors_name,
    highlights = options ~= nil and options.highlights == true,
  }
end

---Undo a failed transaction: restore the previous scheme and observer.
---@param state Orbit.ThemeRuntimeState
function M.restore(state)
  local had_highlights = options ~= nil and options.highlights == true
  started = state.started
  options = require("orbit.modules.theme").current_options()
  sync_group()
  if not started or not state.colorscheme then return end
  if vim.g.colors_name ~= state.colorscheme or had_highlights ~= state.highlights then
    M.apply(state.colorscheme)
  end
end

---Persist a selected colorscheme to an existing settings file.
---@param name string
---@return boolean, string?
function M.persist(name)
  local path = require("orbit.modules.commands").path()
  return require("orbit.settings").update(path, { "modules", "theme", "colorscheme" }, name)
end

return M
