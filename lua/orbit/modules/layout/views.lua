-- Build Edgy views that capture only editor-relative Trouble splits.
local M = {}

---@alias Orbit.LayoutPos 'top'|'bottom'|'left'|'right'

---@class Orbit.LayoutView
---@field ft string
---@field filter fun(buf: integer, win: integer): boolean
---@field size {width?: number, height?: number}

---@class Orbit.LayoutConfig
---@field top Orbit.LayoutView[]
---@field bottom Orbit.LayoutView[]
---@field left Orbit.LayoutView[]
---@field right Orbit.LayoutView[]
---@field animate {enabled: boolean}

---@param pos Orbit.LayoutPos
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
---@return Orbit.LayoutConfig
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
