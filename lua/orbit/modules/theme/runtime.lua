-- Apply the selected colorscheme and Orbit highlight overrides.
-- The runtime is inert until the colorscheme plugin starts it.
local M = {}

---@alias Orbit.ThemeRuntimeState {started: boolean, colorscheme?: string, highlights: boolean}

local group_name = "OrbitTheme"
local started = false
---@type Orbit.ThemeOptions?
local options

local palette = require("orbit.modules.theme.palette")
local mix = palette.mix
---@type Orbit.ThemePalette?
local active_palette
---@type string?
local palette_scheme

---@return Orbit.ThemePalette
function M.palette()
  if active_palette and palette_scheme == vim.g.colors_name then
    return vim.deepcopy(active_palette)
  end
  return palette.resolve()
end

---@param c Orbit.ThemePalette
---@return table<string, vim.api.keyset.highlight>
function M.groups(c)
  local term, program = vim.env.TERM or "", vim.env.TERM_PROGRAM or ""
  local curly = not not vim.g.neovide
    or vim.fn.has("gui_running") == 1
    or term:find("kitty", 1, true) ~= nil
    or ({ WezTerm = true, ["iTerm.app"] = true, ghostty = true })[program] == true
  local curl = { undercurl = curly, underline = not curly }
  local inherited = vim.tbl_extend(
    "force",
    require("orbit.modules.theme.editor")(c),
    require("orbit.modules.theme.plugins")(c),
    require("orbit.modules.theme.bars")(c)
  )
  return vim.tbl_extend("force", inherited, {
    ["@comment"] = { fg = c.grey_fg, italic = true },
    ["@comment.todo"] = { fg = c.grey, bg = c.green },
    Comment = { fg = c.light_grey, italic = true },
    IblChar = { fg = c.grey },
    IblScopeChar = { fg = c.purple },
    NvimTreeOpenedFolderName = { fg = c.green, bold = true },
    TreesitterContext = { link = "CursorLine" },
    LspInlayHint = { fg = 0x808080, bg = c.one_bg, italic = true },
    DevIconDefault = { fg = c.white },
    MiniIconsGrey = { link = "DevIconDefault" },
    NormalFloat = { bg = c.black },
    FloatBorder = { fg = c.blue },
    FloatTitle = { fg = c.blue, bg = c.black },
    active_context = { fg = c.blue },
    CmpGhostText = { link = "Comment", default = true },
    DapBreakpointColor = { fg = c.red },
    DapStopped = { fg = c.green },
    DapBreakpoint = { fg = c.green },
    DapBreakpointCondition = { fg = c.green },
    DapBreakpointRejected = { fg = c.green },
    DapLogPoint = { fg = c.green },
    Underlined = { sp = 0x565f89, underline = true, undercurl = false },
    HangarCategoryActive = { fg = c.black, bg = c.green },
    HangarCategoryInactive = { fg = c.light_grey, bg = c.one_bg },
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
    ExDarkBg = { bg = c.darker_black },
    ExDarkBorder = { fg = c.darker_black, bg = c.darker_black },
    ExBlack2Bg = { bg = c.black2 },
    ExBlack2Border = { fg = c.black2, bg = c.black2 },
    ExBlack2border = { fg = c.black2, bg = c.black2 },
    ExBlack3Bg = { bg = c.one_bg2 },
    ExBlack3Border = { fg = c.one_bg2, bg = c.one_bg2 },
    ExRed = { fg = c.red },
    ExYellow = { fg = c.yellow },
    ExBlue = { fg = c.blue },
    ExGreen = { fg = c.green },
    ExLightGrey = { fg = palette.lighten(c.grey, vim.o.background == "dark" and 35 or -35) },
    CommentFg = { fg = c.light_grey },
    DiagnosticUnderlineError = vim.tbl_extend("force", curl, { sp = c.red }),
    DiagnosticUnderlineWarn = vim.tbl_extend("force", curl, { sp = c.yellow }),
    DiagnosticUnderlineInfo = vim.tbl_extend("force", curl, { sp = c.green }),
    DiagnosticUnderlineHint = vim.tbl_extend("force", curl, { sp = c.purple }),
    DiagnosticVirtualTextError = { fg = c.red, bg = mix(c.red, c.black, 75) },
    DiagnosticVirtualTextWarn = { fg = c.yellow, bg = mix(c.yellow, c.black, 75) },
    DiagnosticVirtualTextInfo = { fg = c.green, bg = mix(c.green, c.black, 75) },
    DiagnosticVirtualTextHint = { fg = c.purple, bg = mix(c.purple, c.black, 75) },
  })
end

---@param refresh? boolean
function M.apply_highlights(refresh)
  if refresh or not active_palette or palette_scheme ~= vim.g.colors_name then
    active_palette, palette_scheme = palette.resolve(), vim.g.colors_name
  end
  local groups = M.groups(active_palette)
  if palette_scheme == "tokyonight-night" or palette_scheme == "tokyonight" then
    -- Preserve orbitvim's Tokyo Night Tree-sitter polish.
    groups["@punctuation.bracket"] = { fg = active_palette.purple }
    groups["@function.method.call"] = { fg = active_palette.red }
    groups["@function.call"] = { fg = active_palette.blue }
    groups["@variable.parameter"] = { fg = active_palette.orange }
  end
  for name, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, name, spec)
  end
end

---Reapply owned colors after a plugin installs unconditional fallback groups.
function M.refresh()
  if started and options and options.highlights then
    M.apply_highlights()
  end
end

local function sync_group()
  pcall(vim.api.nvim_del_augroup_by_name, group_name)
  if not (started and options and options.highlights) then
    return
  end
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      M.apply_highlights(true)
    end,
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
  if not options then
    return
  end
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
  if not started then
    return
  end
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
  if not started or not state.colorscheme then
    return
  end
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
