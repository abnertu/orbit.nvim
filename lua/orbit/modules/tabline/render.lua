-- Render buffers from orbit.buffers, an explorer offset and tab pages.
local M = {}
local handler = "v:lua.require'orbit.modules.tabline.render'."

local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

---@param buffer integer
---@return string
local function name(buffer)
  local path = vim.api.nvim_buf_get_name(buffer)
  return path == "" and "[No Name]" or vim.fn.fnamemodify(path, ":t")
end

-- Add the parent directory when two buffers share a file name.
---@param buffers integer[]
---@return table<integer, string>
local function labels(buffers)
  local counts, result = {}, {}
  for _, buffer in ipairs(buffers) do
    local tail = name(buffer)
    counts[tail] = (counts[tail] or 0) + 1
  end
  for _, buffer in ipairs(buffers) do
    local tail = name(buffer)
    local path = vim.api.nvim_buf_get_name(buffer)
    if counts[tail] > 1 and path ~= "" then
      tail = vim.fn.fnamemodify(path, ":h:t") .. "/" .. tail
    end
    result[buffer] = tail
  end
  return result
end

local function icon(buffer)
  local icons = package.loaded["mini.icons"]
  local path = vim.api.nvim_buf_get_name(buffer)
  if not icons or path == "" then return "" end
  local ok, glyph = pcall(icons.get, "file", vim.fn.fnamemodify(path, ":t"))
  return ok and glyph and glyph .. " " or ""
end

-- Width of a left-side file explorer in the current tab.
local function offset()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buffer = vim.api.nvim_win_get_buf(win)
    if vim.bo[buffer].filetype == "NvimTree" and vim.api.nvim_win_get_position(win)[2] == 0 then
      return vim.api.nvim_win_get_width(win) + 1
    end
  end
  return 0
end

---@param buffer integer
---@param label string
---@param current boolean
---@return string, integer
local function tab(buffer, label, current)
  local group = current and "%#OrbitTbActive#" or "%#OrbitTbInactive#"
  local mark = vim.bo[buffer].modified and "●" or "󰅖"
  local text = " " .. icon(buffer) .. label .. " "
  local width = vim.api.nvim_strwidth(text) + vim.api.nvim_strwidth(mark) + 1
  return group .. "%" .. buffer .. "@" .. handler .. "select@" .. escape(text) .. "%X"
    .. "%" .. buffer .. "@" .. handler .. "close@" .. mark .. " %X", width
end

---@return string
function M.render()
  local width = offset()
  local parts = { width > 0 and ("%#OrbitTbOffset#" .. string.rep(" ", width)) or "" }
  local buffers = require("orbit.buffers").list()
  local names = labels(buffers)
  local current = vim.api.nvim_get_current_buf()
  local tabs = vim.api.nvim_list_tabpages()
  local tab_text = ""
  if #tabs > 1 then
    local items = {}
    local active = vim.api.nvim_get_current_tabpage()
    for index, page in ipairs(tabs) do
      local group = page == active and "%#OrbitTbTabActive#" or "%#OrbitTbTab#"
      items[#items + 1] = group .. "%" .. index .. "T " .. index .. " %T"
    end
    tab_text = table.concat(items)
  end

  -- Keep the current buffer visible when labels exceed the free width.
  local available = vim.o.columns - width - (#tabs > 1 and #tabs * 3 or 0)
  local rendered, widths, focus = {}, {}, 1
  for index, buffer in ipairs(buffers) do
    rendered[index], widths[index] = tab(buffer, names[buffer], buffer == current)
    if buffer == current then focus = index end
  end
  local first, last, used = focus, focus - 1, 0
  while last < #rendered and used + widths[last + 1] <= available do
    last = last + 1
    used = used + widths[last]
  end
  while first > 1 and used + widths[first - 1] <= available do
    first = first - 1
    used = used + widths[first]
  end
  for index = first, last do parts[#parts + 1] = rendered[index] end
  parts[#parts + 1] = "%#OrbitTbFill#%="
  parts[#parts + 1] = tab_text
  return table.concat(parts)
end

---Mouse handler: switch to the clicked buffer.
---@param buffer integer
function M.select(buffer)
  if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_set_current_buf(buffer) end
end

---Mouse handler: close the clicked buffer and keep the window layout.
---@param buffer integer
function M.close(buffer)
  local ok, err = require("orbit.buffers").close(buffer)
  if not ok then vim.notify(tostring(err), vim.log.levels.WARN, { title = "orbit.nvim tabline" }) end
end

local defaults = {
  OrbitTbActive = "TabLineSel", OrbitTbInactive = "TabLine", OrbitTbFill = "TabLineFill",
  OrbitTbOffset = "NvimTreeNormal", OrbitTbTab = "TabLine", OrbitTbTabActive = "TabLineSel",
}

---Define default links. Colorscheme changes clear them.
function M.define_highlights()
  for group, target in pairs(defaults) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

M.define_highlights()

return M
