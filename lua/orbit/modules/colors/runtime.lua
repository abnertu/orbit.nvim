-- Draw a color swatch before hex codes in visible lines of normal buffers.
-- Inline virtual text cannot be ephemeral, so marks are rebuilt for the
-- visible rows after edits, scrolling and window changes.
local M = {}

local ns = vim.api.nvim_create_namespace("orbit.colors")
local group_name = "OrbitColors"
---@type string
local swatch = "󱓻 "
---@type table<integer, true>
local pending = {}
---@type table<string, true>
local defined = {}
local lsp_styled = false
local swatch_set = false

---@param hex string six hex digits
---@return string
local function group(hex)
  local name = "OrbitColor_" .. hex:lower()
  if not defined[name] then
    vim.api.nvim_set_hl(0, name, { fg = tonumber(hex, 16) })
    defined[name] = true
  end
  return name
end

---Find hex color codes in one line.
---@param line string
---@return {col: integer, hex: string}[]
function M.matches(line)
  local result = {}
  for start, digits, finish in line:gmatch("()#(%x+)()") do
    local before = start > 1 and line:sub(start - 1, start - 1) or ""
    local after = line:sub(finish, finish)
    local length = #digits
    if not before:match("[%w_]") and not after:match("[%w_]")
      and (length == 3 or length == 6 or length == 8)
    then
      local hex = length == 3 and digits:gsub(".", "%0%0") or digits:sub(1, 6)
      result[#result + 1] = { col = start - 1, hex = hex }
    end
  end
  return result
end

---Rebuild swatches for every visible row of `buffer`.
---@param buffer integer
function M.update(buffer)
  pending[buffer] = nil
  if not vim.api.nvim_buf_is_valid(buffer) or vim.bo[buffer].buftype ~= "" then return end
  vim.api.nvim_buf_clear_namespace(buffer, ns, 0, -1)
  for _, win in ipairs(vim.fn.win_findbuf(buffer)) do
    local info = vim.fn.getwininfo(win)[1]
    local lines = vim.api.nvim_buf_get_lines(buffer, info.topline - 1, info.botline, false)
    for offset, line in ipairs(lines) do
      for _, match in ipairs(M.matches(line)) do
        vim.api.nvim_buf_set_extmark(buffer, ns, info.topline + offset - 2, match.col, {
          virt_text = { { swatch, group(match.hex) } },
          virt_text_pos = "inline",
          right_gravity = false,
        })
      end
    end
  end
end

local function schedule(buffer)
  if pending[buffer] then return end
  pending[buffer] = true
  vim.schedule(function() M.update(buffer) end)
end

---@param active boolean
---@param opts? Orbit.ColorsOptions
function M.set_hex(active, opts)
  pcall(vim.api.nvim_del_augroup_by_name, group_name)
  if opts and not swatch_set then swatch, swatch_set = opts.swatch, true end
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_clear_namespace(buffer, ns, 0, -1) end
  end
  if not active then return end
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI", "WinScrolled", "WinResized" }, {
    group = group,
    callback = function(args)
      if args.event == "WinScrolled" or args.event == "WinResized" then
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          schedule(vim.api.nvim_win_get_buf(win))
        end
      else
        schedule(args.buf)
      end
    end,
    desc = "Refresh Orbit color previews",
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      defined = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do schedule(vim.api.nvim_win_get_buf(win)) end
    end,
    desc = "Recreate Orbit color preview highlights",
  })
  for _, win in ipairs(vim.api.nvim_list_wins()) do schedule(vim.api.nvim_win_get_buf(win)) end
end

---@type boolean?
local lsp_original

-- The built-in LSP provider keeps one global style; Orbit sets it once.
-- Releasing ownership restores the enablement seen before Orbit owned it.
---@param owned boolean
---@param active boolean
---@param opts Orbit.ColorsOptions
function M.set_lsp(owned, active, opts)
  if not owned then
    if lsp_original ~= nil then vim.lsp.document_color.enable(lsp_original) end
    lsp_original = nil
    return
  end
  if lsp_original == nil then lsp_original = vim.lsp.document_color.is_enabled() end
  if active and not lsp_styled then
    vim.lsp.document_color.enable(true, nil, { style = opts.swatch })
    lsp_styled = true
  else
    vim.lsp.document_color.enable(active)
  end
end

---@return boolean?
function M.lsp_original()
  return lsp_original
end

---@param value boolean?
function M.set_lsp_original(value)
  lsp_original = value
end

M.namespace = ns

return M
