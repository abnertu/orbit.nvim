-- The status line is flat with a mode bar; the buffer bar keeps orbitvim's round style.

---@param c Orbit.ThemePalette
---@return table<string, vim.api.keyset.highlight>
return function(c)
  local status = c.statusline_bg
  local groups = {
    StatusLine = { bg = status, fg = c.white },
    StatusLineNC = { bg = status, fg = c.light_grey },
    OrbitStFill = { bg = status },
    OrbitStDivider = { fg = c.light_grey, bg = status },
    OrbitStDim = { fg = c.light_grey, bg = status },
    OrbitStGit = { fg = c.light_grey, bg = status },
    OrbitStGitAdd = { fg = c.green, bg = status },
    OrbitStGitChange = { fg = c.yellow, bg = status },
    OrbitStGitDelete = { fg = c.red, bg = status },
    OrbitStLsp = { fg = c.light_grey, bg = status },
    OrbitStFile = { fg = c.white, bg = status, bold = true },
    OrbitStModified = { fg = c.yellow, bg = status },
    OrbitStReadonly = { fg = c.red, bg = status },
    OrbitStFormat = { fg = c.yellow, bg = status },
    OrbitStPath = { fg = c.light_grey, bg = status },
    OrbitStSymbols = { fg = c.white, bg = status },
    OrbitStSymbolSep = { fg = c.light_grey, bg = status },
    OrbitStPos = { fg = c.white, bg = status },
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
    Normal = c.nord_blue,
    Visual = c.cyan,
    Insert = c.dark_purple,
    Terminal = c.green,
    NTerminal = c.yellow,
    Replace = c.orange,
    Confirm = c.teal,
    Command = c.green,
    Select = c.blue,
  }) do
    groups["OrbitStMode" .. mode] = { fg = color, bg = status, bold = true }
  end
  return groups
end
