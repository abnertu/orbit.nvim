-- Exercise pinned Snacks dashboard sections and notifier filter.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local lock = dofile(root .. "/tests/support/live_lock.lua")
local directory = vim.fn.tempname() .. " live Snacks with spaces"
-- Messages printed while floats are open can abort headless Neovim.
-- Collect results and print them after every float has closed.
local results = {}

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(
    result.code == 0,
    vim.inspect(argv) .. " failed: " .. tostring(result.stderr or result.stdout)
  )
  return result.stdout or ""
end

local ok, err = xpcall(function()
  lock.checkout("snacks.nvim", "folke/snacks.nvim", directory)
  vim.opt.rtp:prepend(directory)
  vim.o.columns, vim.o.lines = 200, 50

  -- Headless Neovim 0.12 can abort in au_cleanup when a tab line is shown
  -- while Snacks opens floating windows. The tab line has its own tests.
  require("orbit").setup({ modules = { tabline = { enabled = false } } })
  assert(package.loaded.snacks == nil, "root setup imported Snacks before Lazy activation")
  local spec = require("orbit.modules.snacks").spec()[1]
  spec.config(spec, spec.opts)

  -- The startup section reads Lazy statistics; Lazy is outside this boundary.
  package.loaded["lazy.stats"] = {
    stats = function()
      return { startuptime = 12.5, count = 3, loaded = 2 }
    end,
  }
  local project = directory .. "/orbit-dashboard-project"
  assert(vim.fn.mkdir(project, "p") == 1)
  run({ "git", "init", project })
  local recent = project .. "/orbit-recent-note.txt"
  assert(vim.fn.writefile({ "recent" }, recent) == 0)
  vim.v.oldfiles = { recent }
  Snacks.dashboard.open()
  assert(vim.wait(5000, function()
    return vim.bo.filetype == "snacks_dashboard"
  end, 20))
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  local _, titles = text:gsub("Recent Files", "")
  assert(titles == 2, "recent-files section did not render beside the key\n" .. text)
  for _, needle in ipairs({
    "Powered By",
    "Projects",
    "orbit-recent-note.txt",
    "orbit-dashboard-project",
    "2/3 plugins",
  }) do
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
  assert(
    vim.wait(5000, function()
      return shown():find("Orbit notification kept", 1, true) ~= nil
    end, 20),
    "kept notification was not displayed"
  )
  assert(not shown():find("roslyn", 1, true), "ignored notification was displayed")
  Snacks.notifier.hide()
  assert(
    vim.wait(5000, function()
      return not shown():find("Orbit notification kept", 1, true)
    end, 20),
    "notification stayed visible after hide"
  )
  results[#results + 1] = "PASS real Snacks notifier filters ignored sources"

  -- Without an owner, list() falls back to handle order and hides the defect.
  local buffers = require("orbit.buffers")
  assert(buffers.attached("corekeys"), "corekeys did not attach the buffer order")
  local picks = directory .. "/orbit-picks"
  assert(vim.fn.mkdir(picks, "p") == 1)
  local paths = {}
  local names = { "pick-a.txt", "pick-b.txt", "pick-c.txt", "pick-d.txt", "pick-e.txt" }
  vim.list_extend(names, { "pick-f.txt", "pick-broken.txt" })
  for _, name in ipairs(names) do
    paths[name] = vim.fs.normalize(picks .. "/" .. name)
    assert(vim.fn.writefile({ name }, paths[name]) == 0)
  end
  -- Unloaded buffers made in a-b order; selecting b first separates
  -- selection order from handle order.
  local a, b = vim.fn.bufadd(paths["pick-a.txt"]), vim.fn.bufadd(paths["pick-b.txt"])
  assert(a < b)
  vim.cmd("enew")

  local function tiled()
    return #vim.tbl_filter(function(win)
      return vim.api.nvim_win_get_config(win).relative == ""
    end, vim.api.nvim_tabpage_list_wins(0))
  end

  ---@param selection string[] Files to select, in order; empty confirms the cursor item.
  ---@param cursor string File under the cursor at confirm.
  ---@param key? string Confirm key; `<S-CR>` routes through `jump`.
  local function confirm(selection, cursor, key)
    local before = tiled()
    local picker = Snacks.picker.files({ cwd = picks })
    assert(
      vim.wait(10000, function()
        return picker:count() == #names and not picker:is_active() and picker.input.win:valid()
      end, 20),
      "files picker did not list the fixtures"
    )
    local items = {}
    for item in picker:iter() do
      items[vim.fs.basename(item.file)] = item
    end
    for _, name in ipairs(selection) do
      picker.list:select(items[name])
    end
    picker.list:view(items[cursor].idx)
    vim.api.nvim_set_current_win(picker.input.win.win)
    vim.api.nvim_feedkeys(vim.keycode(key or "<CR>"), "xt", false)
    assert(
      vim.wait(5000, function()
        return picker.closed and vim.api.nvim_buf_get_name(0) == paths[cursor]
      end, 20),
      "confirm did not enter " .. cursor
    )
    vim.wait(50)
    assert(tiled() == before, "confirm changed the window count")
  end

  ---@param wanted integer[]
  ---@return integer[]
  local function ordered(wanted)
    return vim.tbl_filter(function(buffer)
      return vim.list_contains(wanted, buffer)
    end, buffers.list())
  end

  confirm({ "pick-b.txt", "pick-a.txt" }, "pick-b.txt")
  local order = ordered({ a, b })
  assert(
    vim.deep_equal(order, { b, a }),
    "multi-select confirm order " .. vim.inspect(order) .. ", want " .. vim.inspect({ b, a })
  )
  assert(vim.api.nvim_buf_is_loaded(a), "second selected file stayed unloaded")
  results[#results + 1] = "PASS real Snacks multi-select confirm loads files in selection order"

  confirm({ "pick-d.txt", "pick-c.txt" }, "pick-d.txt", "<S-CR>")
  local c, d = vim.fn.bufnr(paths["pick-c.txt"]), vim.fn.bufnr(paths["pick-d.txt"])
  order = ordered({ c, d })
  assert(vim.deep_equal(order, { d, c }), "jump route order " .. vim.inspect(order))
  results[#results + 1] = "PASS real Snacks multi-select jump route loads every file"

  -- A swap conflict (E325) aborts bufload only in a TUI. A failing read
  -- autocommand takes the same path in headless Neovim.
  vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = "*/pick-broken.txt",
    callback = function()
      error("orbit broken read")
    end,
  })
  confirm({ "pick-e.txt", "pick-broken.txt" }, "pick-e.txt")
  local e, broken = vim.fn.bufnr(paths["pick-e.txt"]), vim.fn.bufnr(paths["pick-broken.txt"])
  assert(vim.deep_equal(ordered({ e, broken }), { e }), "failed load changed the order")
  assert(not vim.api.nvim_buf_is_loaded(broken), "failed load left its buffer loaded")
  results[#results + 1] = "PASS real Snacks multi-select confirm defers a failed load"

  confirm({}, "pick-f.txt")
  local f = vim.fn.bufnr(paths["pick-f.txt"])
  order = ordered({ a, b, c, d, e, f })
  assert(vim.deep_equal(order, { b, a, d, c, e, f }), "single confirm order " .. vim.inspect(order))
  results[#results + 1] = "PASS real Snacks single confirm appends the cursor file"
end, debug.traceback)

-- Neovim can crash at exit while a picker float stays open.
if not ok and rawget(_G, "Snacks") then
  for _, picker in ipairs(Snacks.picker.get()) do
    picker:close()
  end
end
vim.fn.delete(directory, "rf")
for _, line in ipairs(results) do
  print(line)
end
assert(ok, tostring(err))
print("Pinned upstream Snacks integration tests passed.")
