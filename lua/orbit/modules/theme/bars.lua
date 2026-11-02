-- Status and buffer bar roles match orbitvim's default round style.
local palette = require("orbit.modules.theme.palette")

---@param c Orbit.ThemePalette
---@return table<string, vim.api.keyset.highlight>
return function(c)
  local status = c.statusline_bg
  local groups = {
    StatusLine = { bg = status, fg = c.white },
    StatusLineNC = { bg = status, fg = c.light_grey },
    OrbitStFill = { bg = status },
    OrbitStGit = { fg = palette.lighten(c.light_grey, 8), bg = status, bold = true },
    OrbitStLsp = { fg = c.nord_blue, bg = status },
    OrbitStAi = { fg = c.cyan, bg = status },
    OrbitStFile = { fg = c.white, bg = status },
    OrbitStPath = { fg = c.light_grey, bg = status },
    OrbitStSymbols = { fg = c.white, bg = status },
    OrbitStSymbolSep = { fg = c.white, bg = status },
    OrbitStCwdIcon = { fg = c.one_bg, bg = c.red },
    OrbitStCwd = { fg = c.white, bg = c.lightbg },
    OrbitStCwdSep = { fg = c.red, bg = status },
    OrbitStPosSep = { fg = c.green, bg = status },
    OrbitStPosSepMid = { fg = c.green, bg = c.lightbg },
    OrbitStPosIcon = { fg = c.black, bg = c.green },
    OrbitStPos = { fg = c.green, bg = c.lightbg },
    TabLine = { bg = c.black2 },
    OrbitTbActive = { fg = c.white, bg = c.black },
    OrbitTbInactive = { fg = c.light_grey, bg = c.black2 },
    OrbitTbFill = { bg = c.black2 },
    OrbitTbActiveModified = { fg = c.green, bg = c.black },
    OrbitTbInactiveModified = { fg = c.red, bg = c.black2 },
    OrbitTbActiveClose = { fg = c.red, bg = c.black },
    OrbitTbInactiveClose = { fg = c.light_grey, bg = c.black2 },
    OrbitTbOffset = { link = "NvimTreeNormal" },
    OrbitTbOffsetSep = { link = "NvimTreeWinSeparator" },
  }
  for suffix, color in pairs({ Error = c.red, Warn = c.yellow, Info = c.green, Hint = c.purple }) do
    groups["OrbitSt" .. suffix] = { fg = color, bg = status }
  end
  for mode, color in pairs({
    Normal = c.nord_blue, Visual = c.cyan, Insert = c.dark_purple, Terminal = c.green,
    NTerminal = c.yellow, Replace = c.orange, Confirm = c.teal, Command = c.green, Select = c.blue,
  }) do
    groups["OrbitStMode" .. mode] = { fg = c.black, bg = color, bold = true }
    groups["OrbitStMode" .. mode .. "Sep"] = { fg = color, bg = status }
  end
  return groups
end
