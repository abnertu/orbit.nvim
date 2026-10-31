-- Start parser highlighting in normal buffers without breaking unparsed files.
local M = {}
local group
local pending = {}

local function start(buffer)
  if not vim.api.nvim_buf_is_valid(buffer)
    or vim.api.nvim_get_option_value("buftype", { buf = buffer }) ~= ""
  then
    pending[buffer] = nil
    return
  end
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = buffer })
  if filetype == "" or filetype == "bigfile" then
    pending[buffer] = nil
    return
  end
  local ok = pcall(vim.treesitter.start, buffer)
  pending[buffer] = not ok or nil
end

function M.setup()
  if group then
    return
  end
  local options = require("orbit.modules.treesitter_plugins").current_options()
  if options then
    require("orbit.modules.treesitter_plugins.predicates").setup(options)
  end
  group = vim.api.nvim_create_augroup("OrbitTreesitterStart", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(event)
      start(event.buf)
    end,
    desc = "Start Tree-sitter for normal filetype buffers",
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(event)
      if pending[event.buf] then
        start(event.buf)
      end
    end,
    desc = "Retry Tree-sitter after a parser becomes available",
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      pending[event.buf] = nil
    end,
    desc = "Discard Tree-sitter retry state for wiped buffers",
  })
end

return M
