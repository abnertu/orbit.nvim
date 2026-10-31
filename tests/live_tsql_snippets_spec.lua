-- Verify the original T-SQL corpus against the real pinned LuaSnip parser.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local pinned = "458560534a73f7f8d7a11a146c801db00b081df0"
local source = "https://github.com/L3MON4D3/LuaSnip.git"
local directory = vim.fn.tempname() .. " live LuaSnip"
local original_buffer = vim.api.nvim_get_current_buf()
local luasnip

local function run(args)
  local result = vim.system(args, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(args) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1", source, pinned })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(run({ "git", "-C", directory, "rev-parse", "HEAD" }):gsub("%s+$", "") == pinned)
  vim.opt.rtp:prepend(directory)

  local orbit = require("orbit")
  local completion = require("orbit.modules.completion")
  orbit.setup()
  assert(package.loaded.luasnip == nil, "startup imported LuaSnip eagerly")
  local spec = completion.spec()[1].dependencies[1]
  assert(spec[1] == "L3MON4D3/LuaSnip")
  spec.config(nil, spec.opts)
  luasnip = require("luasnip")

  local by_trigger = {}
  for _, snippet in ipairs(dofile(root .. "/luasnippets/tsql.lua")) do
    assert(not by_trigger[snippet.trigger], "duplicate T-SQL trigger")
    by_trigger[snippet.trigger] = snippet
  end

  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  vim.bo[buffer].filetype = "tsql"
  local function expand(trigger)
    luasnip.unlink_current()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    luasnip.snip_expand(assert(by_trigger[trigger], trigger):copy())
    return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  end

  local read = expand("cprocr")
  assert(read:find("CREATE OR ALTER PROCEDURE dbo.GetEntity", 1, true))
  assert(read:find("WHERE e.EntityId = @EntityId;", 1, true))
  local write = expand("cprocw")
  assert(write:find("SET XACT_ABORT ON;", 1, true))
  assert(write:find("ROLLBACK TRANSACTION;", 1, true))
  assert(write:find("THROW;", 1, true))
  assert(luasnip.jumpable(1), "procedure snippet did not create jump points")
  local dynamic = expand("dynsql")
  assert(dynamic:find("EXEC sys.sp_executesql", 1, true))
  assert(dynamic:find("@Status = @Status", 1, true))
  local ident = expand("dynident")
  assert(ident:find("QUOTENAME(@SortColumn)", 1, true))

  for trigger in pairs(by_trigger) do
    local expanded = expand(trigger)
    assert(not expanded:match("SELECT%s+%*"), trigger)
    assert(not expanded:find("RAISERROR", 1, true), trigger)
    assert(not expanded:find("EXEC (@Sql)", 1, true), trigger)
    assert(not expanded:match("%" .. string.char(36) .. "{%d"), trigger)
  end
  print("PASS real LuaSnip expansion for all T-SQL snippets")
  vim.api.nvim_set_current_buf(original_buffer)
  vim.api.nvim_buf_delete(buffer, { force = true })
end, debug.traceback)

if luasnip then pcall(luasnip.unlink_current) end
if vim.api.nvim_buf_is_valid(original_buffer) then
  pcall(vim.api.nvim_set_current_buf, original_buffer)
end
vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned upstream LuaSnip integration tests passed.")
