-- Check the legacy T-SQL collection through LuaSnip's actual entry file.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local previous_loaded = package.loaded.luasnip
local previous_preload = package.preload.luasnip
package.loaded.luasnip = nil
package.preload.luasnip = function()
  return {
    parser = {
      parse_snippet = function(opts, body)
        assert(type(opts.trig) == "string" and opts.trig ~= "")
        assert(type(opts.name) == "string" and opts.name == opts.dscr)
        assert(type(body) == "string" and body ~= "")
        return { trigger = opts.trig, name = opts.name, body = body }
      end,
    },
  }
end

local ok, snippets = xpcall(function()
  return dofile(root .. "/luasnippets/tsql.lua")
end, debug.traceback)
package.loaded.luasnip = previous_loaded
package.preload.luasnip = previous_preload
assert(ok, tostring(snippets))

local by_trigger = {}
for _, snippet in ipairs(snippets) do
  assert(not by_trigger[snippet.trigger],
    "duplicate T-SQL trigger: " .. snippet.trigger)
  by_trigger[snippet.trigger] = snippet
  assert(not snippet.body:match("SELECT%s+%*"),
    "unsafe wildcard in " .. snippet.trigger)
  assert(not snippet.body:find("RAISERROR", 1, true),
    "legacy error syntax in " .. snippet.trigger)
end
assert(#snippets == 105,
  "legacy T-SQL snippet inventory changed: " .. #snippets)

local expected = {
  cprocr = "CREATE OR ALTER PROCEDURE",
  cprocw = "SET XACT_ABORT ON",
  dynsql = "sys.sp_executesql",
  dynident = "QUOTENAME(@SortColumn)",
  sel = "SELECT",
}
for trigger, text in pairs(expected) do
  assert(by_trigger[trigger], "missing T-SQL trigger " .. trigger)
  assert(by_trigger[trigger].body:find(text, 1, true),
    "missing expected content for " .. trigger)
end
print("PASS 105 unique T-SQL declarations and representative templates")
