-- Validate the real C# and SQL grammar/query pipeline, not source text.
-- nvim-treesitter pins grammar revisions; compiled parsers run in Neovim.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local pinned = "a9c4e1457e2e59f1b82c8f78dcdb3b2517555200"
local source = "https://github.com/nvim-treesitter/nvim-treesitter.git"
local plugin = vim.fn.tempname() .. " pinned nvim treesitter plugin"
local site = vim.fn.tempname() .. " pinned parsers site with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. " failed: "
    .. tostring(result.stderr or result.stdout or result.code))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(plugin, "p") == 1)
  assert(vim.fn.mkdir(site, "p") == 1)
  run({ "git", "init", plugin })
  run({ "git", "-C", plugin, "fetch", "--depth", "1", source, pinned })
  run({ "git", "-C", plugin, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", plugin, "rev-parse", "HEAD" })) == pinned,
    "Tree-sitter manager source checkout mismatch")
  vim.opt.rtp:prepend(plugin)

  local orbit = require("orbit")
  local feature = require("orbit.modules.treesitter_plugins")
  orbit.setup()
  assert(package.loaded["nvim-treesitter"] == nil,
    "root setup eagerly imported nvim-treesitter")
  local spec = feature.spec()[1]
  assert(spec and spec[1] == "nvim-treesitter/nvim-treesitter")
  assert(spec.branch == "main")
  require("orbit.modules.treesitter_plugins.runtime").setup()

  -- The real parser manager uses fixed grammar revisions from its registry:
  -- C# v0.23.5 and SQL gh-pages 174cebb880f10bc7c5a24aa289431949d26d3c09.
  local ts = require("nvim-treesitter")
  ts.setup({ install_dir = site })
  assert(ts.install({ "c_sharp", "sql" }):wait(240000),
    "pinned Tree-sitter grammar compilation or installation failed")
  local installed = ts.get_installed()
  assert(vim.list_contains(installed, "c_sharp"))
  assert(vim.list_contains(installed, "sql"))
  print("PASS pinned C# and SQL grammar compilation and manager setup")

  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".cs")
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
    "class Demo {",
    "    void Run() {",
    "        // language=sql",
    '        var query = """SELECT 10""";',
    '        var sqlOther = """SELECT 20""";',
    '        var sqlPlain = "SELECT 30";',
    '        var data = """NOT AN INJECTION""";',
    "    }",
    "}",
  })
  vim.api.nvim_set_option_value("filetype", "cs", { buf = buffer })
  local parser = assert(vim.treesitter.get_parser(buffer, "c_sharp"))
  local query = assert(vim.treesitter.query.get("c_sharp", "injections"),
    "merged upstream/Orbit C# injections query is unavailable")
  local matches = {}
  for _, match, metadata in query:iter_matches(
    parser:parse()[1]:root(), buffer, 0, -1, { all = true })
  do
    if metadata["injection.language"] == "sql" then
      for capture, nodes in pairs(match) do
        if query.captures[capture] == "injection.content" then
          for _, node in ipairs(nodes) do
            local content = vim.treesitter.get_node_text(node, buffer)
            if content:find("SELECT", 1, true) then
              matches[content] = (matches[content] or 0) + 1
            end
          end
        end
      end
    end
  end
  assert(matches["SELECT 10"] == 1,
    "comment-annotated raw SQL was not injected exactly once: "
      .. vim.inspect(matches))
  assert(matches["SELECT 20"] == 1,
    "sql-prefixed raw SQL was not injected exactly once: "
      .. vim.inspect(matches))
  assert(matches["SELECT 30"] == 1,
    "sql-prefixed ordinary string was not injected exactly once: "
      .. vim.inspect(matches))
  print("PASS real C# SQL query predicates accept raw and ordinary string literals")

  parser:parse()
  local sql_tree_count = 0
  parser:for_each_tree(function(_, language_tree)
    if language_tree:lang() == "sql" then
      sql_tree_count = sql_tree_count + 1
    end
  end)
  assert(sql_tree_count > 0,
    "real LanguageTree failed to build an injected SQL parser")
  assert(vim.treesitter.query.get("sql", "highlights"),
    "merged SQL highlight queries failed to compile")
  print("PASS parsed SQL child LanguageTree and real SQL highlight query")

  vim.api.nvim_buf_delete(buffer, { force = true })
end, debug.traceback)

vim.fn.delete(plugin, "rf")
vim.fn.delete(site, "rf")
assert(ok, tostring(err))
print("Pinned real C# SQL injection tests passed.")
