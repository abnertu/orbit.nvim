-- C# SQL injection predicates. Exclude strings needing escape decoding:
-- Tree-sitter source ranges cannot represent the resulting decoded SQL.
local M = {}
local installed = false

local function captured(match, id)
  local nodes = match[id]
  return nodes and nodes[1] or nil
end

local function text(node, source)
  return vim.treesitter.get_node_text(node, source)
end

local function marker(node, source)
  return node ~= nil and node:type() == "comment"
    and text(node, source):lower():match("^//%s*language%s*=%s*sql%s*$") ~= nil
end

local function supported(node, source)
  if not node then return false end
  local function escaped(current)
    if current:type() == "escape_sequence" then return true end
    for child in current:iter_children() do
      if escaped(child) then return true end
    end
    return false
  end
  if escaped(node) then return false end
  local kind, value = node:type(), text(node, source)
  if kind == "verbatim_string_literal" then
    return value:sub(3, -2):find('""', 1, true) == nil
  end
  if kind == "interpolated_string_expression"
    and (value:sub(1, 3) == '$@"' or value:sub(1, 3) == '@$"')
  then
    return value:sub(4, -2):find('""', 1, true) == nil
  end
  return true
end

local function preceding_marker(node, source)
  while node do
    local kind = node:type()
    if kind == "local_declaration_statement"
      or kind == "expression_statement" or kind == "field_declaration"
    then
      return marker(node:prev_named_sibling(), source)
    end
    node = node:parent()
  end
  return false
end

---@param opts Orbit.TreesitterPluginsOptions
function M.setup(opts)
  if installed then return end
  local sql = opts.sql_injections
  local query = vim.treesitter.query
  query.add_predicate("orbit-sql-string-supported?", function(match, _, source, spec)
    return supported(captured(match, spec[2]), source)
  end, { force = true })
  query.add_predicate("orbit-sql-comment-injection-enabled?", function(match, _, source, spec)
    return sql.comment and marker(captured(match, spec[2]), source) or false
  end, { force = true })
  query.add_predicate("orbit-sql-auto-injection-enabled?", function(match, _, source, spec)
    if not sql.auto then return false end
    local node = captured(match, spec[2])
    if not node or not text(node, source):lower():match("^sql") then return false end
    return not (sql.comment and preceding_marker(node, source))
  end, { force = true })
  installed = true
end

return M
