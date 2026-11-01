-- Exercise pinned Snacks dashboard, picker layouts and notifier filter.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local pinned = "882c996cf28183f4d63640de0b4c02ec886d01f2"
local upstream = "https://github.com/folke/snacks.nvim.git"
local directory = vim.fn.tempname() .. " live Snacks with spaces"
-- Messages printed while picker floats are open can abort headless Neovim.
-- Collect results and print them after every float has closed.
local results = {}

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

local function floats()
  return #vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative ~= ""
  end, vim.api.nvim_list_wins())
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1", upstream, pinned })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pinned,
    "upstream Snacks revision mismatch")
  vim.opt.rtp:prepend(directory)
  vim.o.columns, vim.o.lines = 200, 50

  -- Headless Neovim 0.12 can abort in au_cleanup when any tab line is shown
  -- while Snacks switches picker windows. The tab line has its own tests.
  require("orbit").setup({ modules = { tabline = { enabled = false } } })
  assert(package.loaded.snacks == nil, "root setup imported Snacks before Lazy activation")
  local spec = require("orbit.modules.snacks").spec()[1]
  spec.config(spec, spec.opts)

  local expected = {
    default = { width = 174, preview = true },
    select = { width = 120, preview = false },
    vscode = { width = 80, preview = false },
    vertical = { width = 98, preview = true },
  }
  for _, name in ipairs({ "default", "select", "vscode", "vertical" }) do
    local picker = Snacks.picker({
      items = { { text = "alpha", file = "alpha.txt" } }, format = "text", layout = name,
    })
    assert(vim.wait(5000, function() return picker.layout and picker.layout.root:valid() end, 20),
      name .. " picker did not open")
    local width = picker.layout.root.opts.width
    local preview = not picker.layout:is_hidden("preview")
    assert(width == expected[name].width,
      name .. " layout width " .. tostring(width) .. " ~= " .. expected[name].width)
    assert(preview == expected[name].preview, name .. " preview visibility mismatch")
    picker:close()
    assert(vim.wait(5000, function() return floats() == 0 end, 20), name .. " picker left floats")
    results[#results + 1] = "PASS real Snacks " .. name .. " picker layout"
  end

  -- The startup section reads Lazy statistics; Lazy is outside this boundary.
  package.loaded["lazy.stats"] = {
    stats = function() return { startuptime = 12.5, count = 3, loaded = 2 } end,
  }
  local project = directory .. "/orbit-dashboard-project"
  assert(vim.fn.mkdir(project, "p") == 1)
  run({ "git", "init", project })
  local recent = project .. "/orbit-recent-note.txt"
  assert(vim.fn.writefile({ "recent" }, recent) == 0)
  vim.v.oldfiles = { recent }
  Snacks.dashboard.open()
  assert(vim.wait(5000, function() return vim.bo.filetype == "snacks_dashboard" end, 20))
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  local _, titles = text:gsub("Recent Files", "")
  assert(titles == 2, "recent-files section did not render beside the key\n" .. text)
  for _, needle in ipairs({ "Powered By", "Projects", "orbit-recent-note.txt",
    "orbit-dashboard-project", "2/3 plugins" }) do
    assert(text:find(needle, 1, true), "dashboard is missing " .. needle .. "\n" .. text)
  end
  results[#results + 1] = "PASS real Snacks dashboard renders header and sections"

  Snacks.notify("roslyn: -32000 request cancelled")
  Snacks.notify("Orbit notification kept")
  -- Filtered notifications stay in history but are never displayed.
  local function shown()
    local lines = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= "" then
        local buf = vim.api.nvim_win_get_buf(win)
        vim.list_extend(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      end
    end
    return table.concat(lines, "\n")
  end
  assert(vim.wait(5000, function()
    return shown():find("Orbit notification kept", 1, true) ~= nil
  end, 20), "kept notification was not displayed")
  assert(not shown():find("roslyn", 1, true), "ignored notification was displayed")
  Snacks.notifier.hide()
  assert(vim.wait(5000, function()
    return not shown():find("Orbit notification kept", 1, true)
  end, 20), "notification stayed visible after hide")
  results[#results + 1] = "PASS real Snacks notifier filters ignored sources"
end, debug.traceback)

vim.fn.delete(directory, "rf")
for _, line in ipairs(results) do print(line) end
assert(ok, tostring(err))
print("Pinned upstream Snacks integration tests passed.")
