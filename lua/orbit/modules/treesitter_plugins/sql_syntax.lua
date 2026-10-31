-- Restore focused T-SQL syntax where the SQL parser has no useful nodes.
-- Follow explicit buffer and global dialect selections instead of overwriting them.
local M = {}

local function markdown_dialect(dialect)
  local mapping = "sql=" .. dialect
  local current = vim.g.markdown_fenced_languages
  local langs = type(current) == "table" and vim.deepcopy(current) or {}
  for _, name in ipairs(langs) do
    if type(name) == "string" and name:match("^sql=") then
      vim.g.markdown_fenced_languages = vim.tbl_filter(function(lang)
        return lang ~= "sql"
      end, langs)
      return
    end
  end
  for i, name in ipairs(langs) do
    if name == "sql" then
      langs[i] = mapping
      vim.g.markdown_fenced_languages = langs
      return
    end
  end
  langs[#langs + 1] = mapping
  vim.g.markdown_fenced_languages = langs
end

local function load_syntax(buf, name)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("syntax clear")
    vim.b.current_syntax = nil
    vim.cmd.runtime({ "syntax/" .. name .. ".vim", bang = true })
  end)
end

---@param buf number
---@param opts Orbit.TreesitterPluginsOptions
---@return boolean
function M.apply(buf, opts)
  if not opts.sql_syntax_fallback then return false end
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
  if filetype == "sql" then
    if vim.b[buf].sql_type_override == nil and vim.g.sql_type_default == nil then
      vim.b[buf].sql_type_override = opts.sql_dialect
    end
    load_syntax(buf, "sql")
    return true
  elseif filetype == "markdown" and opts.sql_markdown_fenced_fallback then
    markdown_dialect(opts.sql_dialect)
    load_syntax(buf, "markdown")
    return true
  end
  return false
end

return M
