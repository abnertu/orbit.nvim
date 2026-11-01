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

  -- Exercise the real modern command, not only direct note-buffer writes.
  -- Upstream may generate an ID, so assert the vault boundary, not a filename.
  vim.cmd("Obsidian new orbit-created-note")
  local new_path = canonical(vim.api.nvim_buf_get_name(0))
  assert(vim.startswith(new_path, canonical(vault) .. "/"),
    "new note opened outside the configured vault: " .. new_path)
  assert(new_path ~= canonical(note_path),
    "new-note command reused the original note")
  assert(vim.fn.filereadable(new_path) == 1,
    "new-note command did not persist the new file")
  assert(vim.bo.filetype == "markdown" and vim.b.obsidian_buffer == true,
    "new note did not attach to the real Obsidian buffer lifecycle")
  vim.api.nvim_buf_set_lines(0, -1, -1, false,
    { "Created through the real Obsidian command." })
  vim.cmd("write")
  local created = table.concat(vim.fn.readfile(new_path), "\n")
  assert(created:find("Created through the real Obsidian command.", 1, true),
    "new-note write discarded Markdown content")
  assert(created:find("created:", 1, true) and created:find("modified:", 1, true),
    "new-note command did not persist Orbit frontmatter timestamps")
  assert(table.concat(vim.fn.readfile(note_path), "\n") == rewritten,
    "new-note command modified the previously saved note")
  print("PASS real Obsidian new-note command, vault boundary and persisted content")

  -- Exercise the actual range-aware upstream command in the new vault note.
  -- The pinned upstream order cycles unchecked -> in progress -> important.
  local task_row = vim.api.nvim_buf_line_count(0) + 1
  vim.api.nvim_buf_set_lines(0, -1, -1, false, {
    "- [ ] pending task",
    "- [x] completed task",
    "Unrelated Markdown prose.",
  })
  vim.cmd(("%d,%dObsidian toggle_checkbox"):format(task_row, task_row + 1))
  local tasks = vim.api.nvim_buf_get_lines(0, task_row - 1, task_row + 2, false)
  assert(vim.deep_equal(tasks, {
    "- [~] pending task",
    "- [ ] completed task",
    "Unrelated Markdown prose.",
  }), "real range checkbox command changed the wrong rows: " .. vim.inspect(tasks))

  vim.api.nvim_win_set_cursor(0, { task_row, 0 })
  vim.cmd("Obsidian toggle_checkbox")
  tasks = vim.api.nvim_buf_get_lines(0, task_row - 1, task_row + 2, false)
  assert(vim.deep_equal(tasks, {
    "- [!] pending task",
    "- [ ] completed task",
    "Unrelated Markdown prose.",
  }), "real current-line checkbox command did not advance its state: "
    .. vim.inspect(tasks))

  vim.cmd("write")
  local persisted_tasks = vim.fn.readfile(new_path)
  assert(vim.deep_equal(vim.list_slice(persisted_tasks, task_row, task_row + 2), tasks),
    "checkbox changes were not persisted through the real vault buffer")
  assert(table.concat(vim.fn.readfile(note_path), "\n") == rewritten,
    "checkbox command changed the previously saved vault note")
  print("PASS real Obsidian range/current-line checkbox commands and persistence")

  -- Use a fixed date to test the real daily-note command on both platforms.
  -- Reopening the date must reuse the note without resetting user content.
  local daily_path = vim.fs.joinpath(vault, "2024-06-15.md")
  vim.cmd("Obsidian today 2024-6-15")
  assert(vim.wait(5000, function()
    return canonical(vim.api.nvim_buf_get_name(0)) == canonical(daily_path)
  end, 20), "dated daily-note command did not open the expected vault note")
  assert(vim.fn.filereadable(daily_path) == 1,
    "dated daily-note command did not persist its note")
  assert(vim.bo.filetype == "markdown" and vim.b.obsidian_buffer == true,
    "dated daily note did not attach to the real vault lifecycle")
  local first_daily = table.concat(vim.fn.readfile(daily_path), "\n")
  assert(first_daily:find("created:", 1, true)
    and first_daily:find("modified:", 1, true),
    "dated daily note did not persist Orbit frontmatter")
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "Daily note user content." })
  vim.cmd("write")
  local saved_daily = table.concat(vim.fn.readfile(daily_path), "\n")
  assert(saved_daily:find("Daily note user content.", 1, true),
    "dated daily note did not persist user content")

  vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  vim.cmd("Obsidian today 2024-6-15")
  assert(vim.wait(5000, function()
    return canonical(vim.api.nvim_buf_get_name(0)) == canonical(daily_path)
  end, 20), "reopening a dated daily note did not select its existing buffer")
  assert(table.concat(vim.fn.readfile(daily_path), "\n") == saved_daily,
    "reopening a dated daily note overwrote persisted user content")
  assert(table.concat(vim.fn.readfile(note_path), "\n") == rewritten,
    "dated daily-note command modified an unrelated vault note")
  print("PASS real Obsidian dated daily-note creation and idempotent reopening")

  -- Route the real :Obsidian open command through a captured desktop opener.
  -- No browser is launched, but the upstream command must encode vault paths.
  local uri_note = vim.fs.joinpath(vault, "uri note with spaces.md")
  assert(vim.fn.writefile({ "# URI note", "Second line." }, uri_note) == 0)
  -- Use the resolved path so Windows short temp-directory aliases match the vault root.
  vim.cmd("edit " .. vim.fn.fnameescape(assert(vim.uv.fs_realpath(uri_note))))
  assert(vim.b.obsidian_buffer == true,
    "URI note did not attach to the real vault lifecycle")
  local opened = {}
  local original_opener = Obsidian.opts.open.func
  Obsidian.opts.open.func = function(uri)
    opened[#opened + 1] = uri
  end
  vim.cmd("Obsidian open")
  assert(opened[1] == "obsidian://open?vault=vault%20with%20spaces"
      .. "&file=uri%20note%20with%20spaces.md",
    "real Obsidian open command emitted an invalid vault URI: "
      .. vim.inspect(opened))

  Obsidian.opts.open.use_advanced_uri = true
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("Obsidian open")
  assert(opened[2] == "obsidian://advanced-uri?vault=vault%20with%20spaces"
      .. "&filepath=uri%20note%20with%20spaces.md&line=2",
    "real Obsidian advanced URI lost the note path or cursor line: "
      .. vim.inspect(opened))
  Obsidian.opts.open.func = original_opener
  assert(table.concat(vim.fn.readfile(note_path), "\n") == rewritten,
    "opening an external URI modified the previously saved note")
  print("PASS real Obsidian open command encodes standard and advanced vault URIs")

  -- Audit the real vault without a picker or desktop application.
  -- The URI fixture intentionally lacks frontmatter and must be reported.
  local notifications = {}
  local previous_notify = vim.notify
  vim.notify = function(message, level)
    notifications[#notifications + 1] = { message = tostring(message), level = level }
  end
  local check_ok, check_err = pcall(vim.cmd, "Obsidian check")
  vim.notify = previous_notify
  assert(check_ok, "real Obsidian vault check failed: " .. tostring(check_err))
  local warning
  for _, notification in ipairs(notifications) do
    if notification.message:find("uri note with spaces.md", 1, true)
      and notification.message:find("missing frontmatter", 1, true) then
      warning = notification
      break
    end
  end
  assert(warning and warning.level == vim.log.levels.WARN
    and warning.message:find("Checked ", 1, true),
    "real vault check did not report the missing frontmatter: "
      .. vim.inspect(notifications))
  assert(table.concat(vim.fn.readfile(uri_note), "\n") == "# URI note\nSecond line.",
    "vault check modified the note without frontmatter")
  assert(table.concat(vim.fn.readfile(note_path), "\n") == rewritten,
    "vault check modified a previously saved note")
  print("PASS real Obsidian vault audit warns without changing notes")
end, debug.traceback)

vim.wo.conceallevel = initial_conceal
pcall(vim.cmd, "silent! bwipeout!")
vim.fn.delete(base, "rf")
assert(ok, tostring(err))
print("Pinned real Obsidian vault integration passed.")
