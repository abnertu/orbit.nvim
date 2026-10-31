-- Start parser highlighting in normal buffers without breaking unparsed files.
local M = {}
local group

local function start(buffer)
  if not vim.api.nvim_buf_is_valid(buffer)
    or vim.api.nvim_get_option_value("buftype", { buf = buffer }) ~= ""
    or vim.api.nvim_get_option_value("filetype", { buf = buffer }) == "bigfile"
  then
    return
  end
  pcall(vim.treesitter.start, buffer)
end

function M.setup()
  if group then
    return
  end
  group = vim.api.nvim_create_augroup("OrbitTreesitterStart", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(event)
      start(event.buf)
    end,
    desc = "Start Tree-sitter for normal filetype buffers",
  })
end

return M
