-- Harpoon display and UI lifecycle without importing the external plugin at setup.
local M = {}
local namespace = vim.api.nvim_create_namespace("orbit.harpoon")

---Format path segments without requiring Plenary.
---@param path string
---@param length number
---@param root? string
---@return string
function M.pretty_path(path, length, root)
  if path == "" then return "" end
  local normalized = vim.fs.normalize(path)
  if root then
    local prefix = vim.fs.normalize(root)
    if normalized:sub(1, #prefix + 1) == prefix .. "/" then
      normalized = normalized:sub(#prefix + 2)
    end
  end
  local parts = vim.split(normalized, "[\\/]", { plain = false })
  if length == 1 then return parts[#parts] end
  if #parts <= length then return table.concat(parts, "/") end
  local trimmed = { parts[1], "…" }
  vim.list_extend(trimmed,
    vim.list_slice(parts, #parts - length + 2, #parts))
  return table.concat(trimmed, "/")
end

function M.format_display(path)
  local icon = ""
  local ok, icons = pcall(require, "mini.icons")
  if ok then icon = icons.get("file", path) or "" end
  return "  " .. icon .. " " .. path
end

---@param config table
---@param value? string
---@param length number
function M.create_list_item(config, value, length)
  if not value then
    local path = vim.api.nvim_buf_get_name(0)
    local root = config.get_root_dir()
    value = vim.fs.relpath(root, path) or path
  end
  local buffer = vim.fn.bufnr(value, false)
  local pos = buffer ~= -1 and vim.api.nvim_win_get_cursor(0) or { 1, 0 }
  return {
    value = value,
    context = {
      row = pos[1], col = pos[2],
      short_path = M.pretty_path(value, length, vim.fn.getcwd()),
    },
  }
end

function M.highlight_current_file(length)
  return {
    UI_CREATE = function(cx)
      local current = M.pretty_path(cx.current_file, length, vim.fn.getcwd())
      if current == "" or not vim.api.nvim_buf_is_valid(cx.bufnr) then return end
      local display = M.format_display(current)
      for line, entry in pairs(cx.contents or {}) do
        if type(line) == "number" and type(entry) == "string" and entry ~= ""
          and display:find(entry, 1, true)
        then
          local content = vim.api.nvim_buf_get_lines(
            cx.bufnr, line - 1, line, false)[1]
          if content and #content >= 2 then
            vim.api.nvim_buf_set_extmark(cx.bufnr, namespace, line - 1, 2, {
              end_col = #content,
              hl_group = "active_context",
            })
            if vim.api.nvim_win_is_valid(cx.win_id) then
              vim.api.nvim_win_set_cursor(cx.win_id, { line, 0 })
            end
          end
        end
      end
    end,
  }
end

local started = false
---@param length number
function M.setup(length)
  if started then return end
  local harpoon = require("harpoon")
  harpoon:setup({
    default = {
      create_list_item = function(config, value)
        return M.create_list_item(config, value, length)
      end,
      display = function(item)
        return M.format_display(item.context.short_path or "")
      end,
    },
  })
  harpoon:extend(M.highlight_current_file(length))
  started = true
end

return M
