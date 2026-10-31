-- Verify the real Obsidian vault lifecycle through Orbit's Lazy boundary.
-- This networked integration test runs separately from hermetic validation.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local upstream = {
  url = "https://github.com/obsidian-nvim/obsidian.nvim.git",
  sha = "15af492b64f4677959fe95008f1d5b782fe1f86a",
}
local base = vim.fn.tempname() .. " orbit live Obsidian with spaces"
local checkout = vim.fs.joinpath(base, "obsidian.nvim")
local vault = vim.fs.joinpath(base, "vault with spaces")
local note_path = vim.fs.joinpath(vault, "live-note.md")
local initial_conceal = vim.wo.conceallevel

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. ": "
    .. tostring(result.stderr or result.stdout or result.code))
  return vim.trim(result.stdout or "")
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(checkout, "p") == 1)
  assert(vim.fn.mkdir(vim.fs.joinpath(vault, ".obsidian"), "p") == 1)
  assert(vim.fn.writefile({ "# Live note", "A real vault buffer." }, note_path) == 0)

  run({ "git", "init", checkout })
  run({ "git", "-C", checkout, "fetch", "--depth", "1", upstream.url, upstream.sha })
  run({ "git", "-C", checkout, "checkout", "--detach", "FETCH_HEAD" })
  assert(run({ "git", "-C", checkout, "rev-parse", "HEAD" }) == upstream.sha,
    "upstream Obsidian revision mismatch")
  vim.opt.rtp:prepend(checkout)

  local orbit = require("orbit")
  orbit.setup({ modules = { markdown = { preview = false, vault = vault } } })
  assert(package.loaded.obsidian == nil, "Orbit setup imported Obsidian eagerly")
  local specs = require("orbit.modules.markdown").spec()
  assert(#specs == 1 and specs[1][1] == "obsidian-nvim/obsidian.nvim")
  assert(specs[1].cond(), "existing vault must allow Lazy activation")
  assert(type(specs[1].opts) == "function"
    and type(specs[1].config) == "function")
  print("PASS real Obsidian remains lazy until its configured vault is demanded")

  -- Lazy loads the plugin/ script before invoking its config callback.
  vim.cmd("runtime plugin/obsidian.lua")
  assert(vim.api.nvim_get_commands({}).Obsidian ~= nil,
    "real upstream :Obsidian command was not registered")
  local opts = specs[1].opts()
  assert(vim.fs.normalize(opts.workspaces[1].path) == vim.fs.normalize(vault),
    "Obsidian vault path was not normalized consistently: "
      .. vim.inspect({ opts.workspaces[1].path, vault }))
  assert(opts.legacy_commands == false)
  specs[1].config(specs[1], opts)
  local obsidian = require("obsidian")
  assert(obsidian.get_client() ~= nil, "upstream Obsidian setup did not finish")
  assert(Obsidian.opts.legacy_commands == false)
  assert(Obsidian.opts.frontmatter.func
    == require("orbit.modules.markdown.notes").frontmatter)
  local function canonical(path)
    local resolved = vim.uv.fs_realpath(path) or path
    local normalized = vim.fs.normalize(resolved):gsub("\\", "/")
    return vim.fn.has("win32") == 1 and normalized:lower() or normalized
  end
  assert(canonical(tostring(Obsidian.workspace.path)) == canonical(vault),
    "upstream workspace selected a different vault: "
      .. vim.inspect({ tostring(Obsidian.workspace.path), vault }))
  assert(vim.wo.conceallevel == 2, "Orbit did not preserve Markdown conceal")
  assert(vim.api.nvim_get_commands({}).ObsidianNew == nil,
    "disabled legacy Obsidian command was unexpectedly installed")
  print("PASS real Obsidian command, workspace and frontmatter callback")

  vim.cmd("filetype on")
  vim.cmd("edit " .. vim.fn.fnameescape(note_path))
  assert(vim.bo.filetype == "markdown", "vault note did not detect Markdown")
  assert(vim.b.obsidian_buffer == true,
    "real Obsidian BufEnter observer did not attach to the vault note")
  vim.cmd("write")
  local saved = table.concat(vim.fn.readfile(note_path), "\n")
  assert(saved:match("^%-%-%-"), "real note write did not create frontmatter")
  assert(saved:find("created:", 1, true) and saved:find("modified:", 1, true),
    "Orbit frontmatter callback did not write portable timestamps")
  assert(saved:find("# Live note", 1, true),
    "upstream note save discarded existing Markdown content")
  print("PASS real Markdown BufEnter and on-disk frontmatter lifecycle")

  -- Reopen the saved note with user metadata to exercise a second real write.
  -- A fresh buffer forces upstream Obsidian to read the persisted frontmatter.
  local first_created = saved:match("\ncreated:%s*([^\n]+)")
    or saved:match("^created:%s*([^\n]+)")
  assert(first_created, "first save did not persist the created timestamp")
  local updated, modified_fields = {}, 0
  for _, line in ipairs(vim.fn.readfile(note_path)) do
    if line:match("^modified:") then
      updated[#updated + 1] = "modified: '2001-01-01 00:00:00'"
      updated[#updated + 1] = "custom: preserved-by-orbit"
      modified_fields = modified_fields + 1
    else
      updated[#updated + 1] = line
    end
  end
  assert(modified_fields == 1, "first save must contain one modified field")
  assert(vim.fn.writefile(updated, note_path) == 0)
  vim.cmd("bwipeout!")
  vim.cmd("edit " .. vim.fn.fnameescape(note_path))
  assert(vim.b.obsidian_buffer == true,
    "reopened note did not reattach to the real vault")
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "A second write." })
  vim.cmd("write")

  local rewritten = table.concat(vim.fn.readfile(note_path), "\n")
  local second_created = rewritten:match("\ncreated:%s*([^\n]+)")
    or rewritten:match("^created:%s*([^\n]+)")
  assert(second_created == first_created,
    "rewriting a note changed its original created timestamp")
  assert(rewritten:find("custom: preserved-by-orbit", 1, true),
    "rewriting a note discarded user frontmatter metadata")
  assert(not rewritten:find("2001-01-01 00:00:00", 1, true),
    "rewriting a note did not refresh its modified timestamp")
  assert(rewritten:find("# Live note", 1, true)
    and rewritten:find("A second write.", 1, true),
    "rewriting a note discarded Markdown content")
  local delimiters = 0
  for line in rewritten:gmatch("[^\n]+") do
    if line == "---" then delimiters = delimiters + 1 end
  end
  assert(delimiters == 2, "rewriting a note duplicated YAML frontmatter")
  print("PASS real Obsidian preserves metadata and one frontmatter on rewrite")
end, debug.traceback)

vim.wo.conceallevel = initial_conceal
pcall(vim.cmd, "silent! bwipeout!")
vim.fn.delete(base, "rf")
assert(ok, tostring(err))
print("Pinned real Obsidian vault integration passed.")
