-- Reuse loaded icon providers without activating a plugin from a render loop.
local M = {}

---@param path string
---@param background string
---@return string glyph
---@return string highlight
function M.file(path, background)
  local glyph, source = "󰈚", "DevIconDefault"
  local icons = package.loaded["mini.icons"]
  if icons and path ~= "" then
    local ok, icon, group = pcall(icons.get, "file", vim.fn.fnamemodify(path, ":t"))
    if ok and type(icon) == "string" and icon ~= "" then
      glyph, source = icon, group or source
    end
  end
  local fg = vim.api.nvim_get_hl(0, { name = source, link = false }).fg
    or vim.api.nvim_get_hl(0, { name = "DevIconDefault", link = false }).fg
    or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg
  local bg = vim.api.nvim_get_hl(0, { name = background, link = false }).bg
  local name = "OrbitIcon_" .. background .. "_" .. source:gsub("[^%w_]", "_")
  local spec = { fg = fg, bg = bg }
  if not vim.deep_equal(vim.api.nvim_get_hl(0, { name = name, link = false }), spec) then
    vim.api.nvim_set_hl(0, name, spec)
  end
  return glyph, name
end

return M
