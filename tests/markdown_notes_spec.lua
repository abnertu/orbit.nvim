-- Obsidian vault Lazy entry point, frontmatter and restart-only settings.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.markdown")
local notes = require("orbit.modules.markdown.notes")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

orbit.setup()
local initial = feature.capture()
local vault = vim.fn.tempname() .. " vault with spaces"
vim.fn.mkdir(vault, "p")

check("vault integration is absent without an explicit vault", function()
  assert(#feature.spec() == 1)
  assert(package.loaded.obsidian == nil)
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    markdown = { vault = 42 },
  } })
  assert(not ok and tostring(err):find("vault", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
end)

check("configured vault is gated by directory existence at Lazy demand", function()
  feature.setup({ vault = vault })
  local specs = feature.spec()
  assert(#specs == 2)
  local item = specs[2]
  assert(item[1] == "obsidian-nvim/obsidian.nvim")
  assert(item.version == "*" and item.ft == "markdown")
  assert(item.cond())
  assert(package.loaded.obsidian == nil)
  local opts = item.opts()
  assert(opts.workspaces[1].name == "knowledge base")
  assert(opts.workspaces[1].path == vault)
  assert(opts.legacy_commands == false)
  assert(type(opts.frontmatter.func) == "function")
  vim.fn.delete(vault, "rf")
  assert(not item.cond(), "missing vault must prevent plugin activation")
  vim.fn.mkdir(vault, "p")
end)

check("Obsidian setup is deferred and sets Markdown conceal after success", function()
  local calls = 0
  package.preload.obsidian = function()
    return { setup = function(opts)
      assert(opts.workspaces[1].path == vault)
      assert(opts.frontmatter.func == notes.frontmatter)
      calls = calls + 1
    end }
  end
  local original = vim.wo.conceallevel
  vim.wo.conceallevel = 0
  local item = feature.spec()[2]
  item.config(nil, item.opts())
  assert(calls == 1 and vim.wo.conceallevel == 2)
  vim.wo.conceallevel = original
  package.loaded.obsidian, package.preload.obsidian = nil, nil
end)

check("frontmatter preserves note metadata and refreshes modified time", function()
  for _, id in ipairs({ "AGENTS", "CLAUDE", "SKILL" }) do
    assert(vim.tbl_isempty(notes.frontmatter({ id = id })))
  end
  local frontmatter = notes.frontmatter({
    id = "daily", aliases = { "day" }, tags = { "journal" },
    metadata = { created = "2020-01-01", modified = "old", custom = "yes" },
  })
  assert(frontmatter.id == "daily")
  assert(frontmatter.aliases[1] == "day" and frontmatter.tags[1] == "journal")
  assert(frontmatter.created == "2020-01-01" and frontmatter.custom == "yes")
  assert(frontmatter.modified ~= "old")
  assert(frontmatter.modified:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"))
  local plain = notes.frontmatter({ id = "new" })
  assert(plain.created == plain.modified)
end)

check("frontmatter overlay preserves explicit metadata and source ownership", function()
  local metadata = {
    id = "metadata-id", aliases = { "metadata alias" },
    created = "2020-02-03", modified = "past",
    custom = false,
  }
  local value = notes.frontmatter({
    id = "note-id", aliases = { "note alias" }, metadata = metadata,
  })
  assert(value.id == "metadata-id")
  assert(vim.deep_equal(value.aliases, { "metadata alias" }))
  assert(value.created == "2020-02-03" and value.custom == false)
  assert(value.modified ~= "past")
  assert(metadata.modified == "past", "metadata must remain unchanged")
  assert(metadata.id == "metadata-id")
end)

check("disabled notes and restart-only vault preserve accepted settings", function()
  feature.setup({ notes = false, vault = vault })
  assert(#feature.spec() == 1)
  feature.restore(initial)
  assert(#feature.spec() == 1)
  orbit.setup({ modules = { markdown = { vault = vault } } })
  assert(orbit.get_config().modules.markdown.vault == "")
  assert(orbit.get_pending_restart()["orbit.modules.markdown.vault"] == vault)
end)

vim.fn.delete(vault, "rf")
print(string.format("%d Obsidian vault tests passed.", passed))
