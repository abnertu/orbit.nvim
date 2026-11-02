local M = {}

---@param group string
---@param attr 'fg'|'bg'
---@return integer?
local function color(group, attr)
  return vim.api.nvim_get_hl(0, { name = group, link = false })[attr]
end

---@param from integer
---@param to integer
---@param percent number
---@return integer
function M.mix(from, to, percent)
  local result = 0
  for shift = 16, 0, -8 do
    local a = bit.band(bit.rshift(from, shift), 0xff)
    local b = bit.band(bit.rshift(to, shift), 0xff)
    result = result + bit.lshift(math.floor(a + (b - a) * percent / 100), shift)
  end
  return result
end

---Adjust HSL lightness without changing hue or saturation.
---@param value integer
---@param percent number
---@return integer
function M.lighten(value, percent)
  local channels = {}
  for shift = 16, 0, -8 do
    channels[#channels + 1] = bit.band(bit.rshift(value, shift), 0xff) / 255
  end
  local high, low = math.max(unpack(channels)), math.min(unpack(channels))
  local light, delta = (high + low) / 2, high - low
  local next_light = math.max(0, math.min(1, light + percent / 100))
  local scale = delta == 0 and 0
    or (1 - math.abs(2 * next_light - 1)) / (1 - math.abs(2 * light - 1))
  local result = 0
  for index, channel in ipairs(channels) do
    local adjusted =
      math.max(0, math.min(255, math.floor(((channel - light) * scale + next_light) * 255)))
    result = result + bit.lshift(adjusted, (3 - index) * 8)
  end
  return result
end

---@return Orbit.ThemePalette
function M.resolve()
  if vim.g.colors_name == "tokyonight-night" or vim.g.colors_name == "tokyonight" then
    return vim.deepcopy(require("orbit.modules.theme.tokyonight"))
  end
  -- Other schemes keep their own foreground, accents and light/dark background.
  local bg = color("Normal", "bg") or (vim.o.background == "dark" and 0x1a1b26 or 0xe1e2e7)
  local fg = color("Normal", "fg") or 0xc0caf5
  local c = {
    black = bg,
    white = fg,
    red = color("DiagnosticError", "fg") or 0xf7768e,
    yellow = color("DiagnosticWarn", "fg") or 0xe0af68,
    green = color("String", "fg") or 0x9ece6a,
    blue = color("Function", "fg") or 0x7aa2f7,
    purple = color("Statement", "fg") or 0xbb9af7,
    cyan = color("Special", "fg") or 0x7dcfff,
    orange = color("Number", "fg") or 0xff9e64,
    grey = color("Comment", "fg") or M.mix(fg, bg, 60),
  }
  c.darker_black = M.mix(bg, vim.o.background == "dark" and 0 or 0xffffff, 15)
  c.black2, c.one_bg = M.mix(bg, fg, 4), M.mix(bg, fg, 8)
  c.one_bg2, c.one_bg3 = M.mix(bg, fg, 16), M.mix(bg, fg, 12)
  c.grey_fg, c.grey_fg2, c.light_grey = c.grey, c.grey, c.grey
  c.line, c.lightbg = M.mix(bg, fg, 15), M.mix(bg, fg, 12)
  c.statusline_bg = color("StatusLine", "bg") or M.mix(bg, fg, 2)
  c.nord_blue, c.folder_bg, c.pmenu_bg = c.blue, c.blue, c.blue
  c.dark_purple, c.pink, c.baby_pink = c.purple, c.red, c.red
  c.teal, c.vibrant_green, c.sun = c.cyan, c.green, c.yellow
  c.base16 = {
    base00 = bg,
    base01 = c.darker_black,
    base02 = c.one_bg3,
    base03 = c.grey,
    base04 = c.grey_fg,
    base05 = fg,
    base06 = fg,
    base07 = fg,
    base08 = color("Identifier", "fg") or c.cyan,
    base09 = c.orange,
    base0A = color("Type", "fg") or c.cyan,
    base0B = c.green,
    base0C = c.cyan,
    base0D = c.blue,
    base0E = c.purple,
    base0F = c.red,
  }
  return c
end

return M
