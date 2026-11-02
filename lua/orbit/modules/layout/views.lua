-- Build Edgy views that capture only editor-relative Trouble splits.
local M = {}

---@param pos Edgy.Pos
---@return fun(buf: integer, win: integer): boolean
function M.trouble_filter(pos)
  return function(_, win)
    local trouble = vim.w[win].trouble
    return type(trouble) == "table"
      and trouble.position == pos
      and trouble.type == "split"
      and trouble.relative == "editor"
      and not vim.w[win].trouble_preview
  end
end

---@param size number
---@return Edgy.Config
function M.build(size)
  local opts = { animate = { enabled = false } }
  for _, pos in ipairs({ "top", "bottom", "left", "right" }) do
    opts[pos] = {
      {
        ft = "trouble",
        filter = M.trouble_filter(pos),
        size = (pos == "left" or pos == "right") and { width = size } or { height = size },
      },
    }
  end
  return opts
end

return M
