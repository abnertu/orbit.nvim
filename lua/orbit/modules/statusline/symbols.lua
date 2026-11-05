local M = {}

---@type {statusline: fun(opts: trouble.Config): Orbit.StatuslineSymbolProvider}?
local source
---@type Orbit.StatuslineSymbolProvider?
local provider
local separator = "%#OrbitStSymbolSep#  "
local boundary = "\31"
-- The section starts at its separator glyph; the renderer owns outer gaps.
local leading = "%#OrbitStSymbolSep# "

---Trouble owns symbol requests and refreshes. Rendering never imports a plugin.
---@return string
function M.render()
  local trouble = package.loaded.trouble
  if not trouble or type(trouble.statusline) ~= "function" then
    return ""
  end
  if trouble ~= source then
    local ok, result = pcall(trouble.statusline, {
      mode = "symbols",
      groups = {},
      title = false,
      filter = { range = true },
      format = "{kind_icon}{symbol.name:OrbitStSymbols}" .. boundary,
      hl_group = "OrbitStSymbols",
    })
    if not (ok and type(result) == "table" and type(result.get) == "function") then
      return ""
    end
    source, provider = trouble, result
  end
  if not provider then
    return ""
  end
  local ok, text = pcall(provider.get)
  if not ok or type(text) ~= "string" or text == "" then
    return ""
  end
  -- An explicit format boundary preserves escaped percent signs and highlights.
  local parts = {}
  for _, item in ipairs(vim.split(text, boundary, { plain = true })) do
    -- Trouble can append highlighted padding after the last item.
    local visible = item:gsub("%%#[^#]+#", ""):gsub("%%%*", "")
    if visible:find("%S") then
      parts[#parts + 1] = item:gsub("^%s+", ""):gsub("%s+$", "")
    end
  end
  if #parts == 0 then
    return ""
  end
  if #parts > 3 then
    parts = { parts[1], "…", parts[#parts - 1], parts[#parts] }
  end
  return leading .. table.concat(parts, separator)
end

return M
