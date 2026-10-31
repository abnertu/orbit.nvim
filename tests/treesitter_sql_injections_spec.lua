-- Exercise C# SQL injection predicates at Neovim's real query registration boundary.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.treesitter_plugins")
local runtime = require("orbit.modules.treesitter_plugins.runtime")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

local callbacks, calls = {}, 0
local add = vim.treesitter.query.add_predicate
local get_text = vim.treesitter.get_node_text
vim.treesitter.query.add_predicate = function(name, callback, opts)
  assert(opts.force == true)
  callbacks[name] = callback
  calls = calls + 1
  return add(name, callback, opts)
end
vim.treesitter.get_node_text = function(node)
  return node.value
end

local function node(kind, value, children)
  local current = { value = value }
  function current:type() return kind end
  function current:iter_children()
    local index = 0
    return function()
      index = index + 1
      return (children or {})[index]
    end
  end
  function current:parent() return current.up end
  function current:prev_named_sibling() return current.previous end
  return current
end
local function run(name, captured)
  local fn = assert(callbacks["orbit-sql-" .. name .. "?"])
  return fn({ [1] = { captured } }, nil, 0, { name, 1 })
end

check("schema settings use LuaDoc defaults, with no eager predicate import", function()
  assert(package.loaded["orbit.modules.treesitter_plugins.predicates"] == nil)
  orbit.setup()
  assert(vim.deep_equal(orbit.get_config().modules.treesitter_plugins.sql_injections,
    { comment = true, auto = true }))
end)

check("Tree-sitter startup registers exactly three runtime predicates once", function()
  runtime.setup()
  runtime.setup()
  assert(calls == 3)
  assert(callbacks["orbit-sql-string-supported?"])
  assert(callbacks["orbit-sql-comment-injection-enabled?"])
  assert(callbacks["orbit-sql-auto-injection-enabled?"])
end)

check("marker injection accepts case and spaces only for language=sql", function()
  assert(run("comment-injection-enabled", node("comment", "// LANGUAGE = SQL")))
  assert(run("comment-injection-enabled", node("comment", "// language=sql")))
  assert(not run("comment-injection-enabled", node("comment", "// language=python")))
  assert(not run("comment-injection-enabled", node("identifier", "// language=sql")))
end)

check("auto injection recognizes sql prefixes and avoids duplicate marked literals", function()
  local sql = node("identifier", "sql_posts")
  assert(run("auto-injection-enabled", sql))
  local not_sql = node("identifier", "query")
  assert(not run("auto-injection-enabled", not_sql))
  local parent = node("local_declaration_statement", "")
  parent.previous = node("comment", "// language=sql")
  sql.up = parent
  assert(not run("auto-injection-enabled", sql))
  parent.previous = node("comment", "// language=python")
  assert(run("auto-injection-enabled", sql))
end)

check("string support excludes escapes, doubled verbatim quotes and interpolation escapes", function()
  assert(run("string-supported", node("raw_string_literal", '"""SELECT 1"""')))
  assert(run("string-supported", node("verbatim_string_literal", '@"SELECT 1"')))
  assert(not run("string-supported", node("verbatim_string_literal", '@"SELECT ""a"""')))
  assert(not run("string-supported", node("interpolated_string_expression", '$@"SELECT ""a"""')))
  assert(run("string-supported", node("interpolated_string_expression", '$"SELECT {table}"')))
  local escaped = node("string_literal", '"SELECT \\n"', { node("escape_sequence", "\\n") })
  assert(not run("string-supported", escaped))
  local nested = node("interpolated_string_expression", '$"SELECT {table}"', {
    node("string_content", "SELECT ", { node("escape_sequence", "\\t") }),
  })
  assert(not run("string-supported", nested))
  assert(not run("string-supported", nil))
end)

check("disabled marker and auto injection options are independently respected", function()
  package.loaded["orbit.modules.treesitter_plugins.predicates"] = nil
  require("orbit.modules.treesitter_plugins.predicates").setup({
    sql_injections = { comment = false, auto = true },
  })
  assert(not run("comment-injection-enabled", node("comment", "// language=sql")))
  local sql = node("identifier", "sqlItems")
  local parent = node("expression_statement", "")
  parent.previous = node("comment", "// language=sql")
  sql.up = parent
  assert(run("auto-injection-enabled", sql))
  package.loaded["orbit.modules.treesitter_plugins.predicates"] = nil
  require("orbit.modules.treesitter_plugins.predicates").setup({
    sql_injections = { comment = true, auto = false },
  })
  assert(not run("auto-injection-enabled", node("identifier", "sqlItems")))
  assert(run("comment-injection-enabled", node("comment", "// language=sql")))
end)

check("source query is loadable and references the registered predicate names", function()
  local path = vim.fs.joinpath(root, "after", "queries", "c_sharp", "injections.scm")
  local lines = vim.fn.readfile(path)
  local source = table.concat(lines, "\n")
  assert(source:find("; extends", 1, true))
  assert(source:find("(raw_string_literal)", 1, true))
  assert(source:find("(interpolated_string_expression", 1, true))
  for _, name in ipairs({
    "string-supported", "comment-injection-enabled", "auto-injection-enabled",
  }) do
    assert(source:find("#orbit-sql-" .. name .. "?", 1, true))
  end
end)

check("invalid saved injection options preserve accepted state", function()
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    treesitter_plugins = { sql_injections = { comment = "bad" } },
  } })
  assert(not ok and tostring(err):find("comment", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
  orbit.setup({ modules = {
    treesitter_plugins = { sql_injections = { comment = false } },
  } })
  assert(orbit.get_config().modules.treesitter_plugins.sql_injections.comment)
  local deferred = orbit.get_pending_restart()
  assert(deferred["orbit.modules.treesitter_plugins.sql_injections"].comment == false)
end)

vim.treesitter.query.add_predicate = add
vim.treesitter.get_node_text = get_text
print(string.format("%d C# SQL injection predicate tests passed.", passed))
