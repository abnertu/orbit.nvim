-- LuaSnip discovers this entry through its standard Lua snippets loader.
-- Template data lives under the orbit namespace and loads only on demand.
local parse = require("luasnip").parser.parse_snippet

local families = {
  require("orbit.snippets.tsql.database_objects_and_schema_changes"),
  require("orbit.snippets.tsql.indexes_and_sequences"),
  require("orbit.snippets.tsql.programmable_objects"),
  require("orbit.snippets.tsql.queries_joins_ctes_and_windows"),
  require("orbit.snippets.tsql.data_modification"),
  require(
    "orbit.snippets.tsql.control_flow_temporary_storage_and_transactions"
  ),
  require("orbit.snippets.tsql.dynamic_sql"),
  require("orbit.snippets.tsql.security_and_object_lifecycle"),
  require("orbit.snippets.tsql.constraint_and_column_fragments"),
  require(
    "orbit.snippets.tsql.common_expressions_and_statement_fragments"
  ),
}
local snippets, seen = {}, {}
for _, family in ipairs(families) do
  for _, declaration in ipairs(family) do
    local trigger, name, body = unpack(declaration)
    assert(not seen[trigger], "duplicate T-SQL snippet trigger: " .. trigger)
    seen[trigger] = true
    snippets[#snippets + 1] =
      parse({ trig = trigger, name = name, dscr = name }, vim.trim(body))
  end
end
return snippets
