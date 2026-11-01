-- Exercise Completion's real callbacks without fetching external plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.completion")
local runtime = require("orbit.modules.completion.runtime")
local passed = 0
---@type {suppress_events_for_callback: fun(self: {ignore_next_cursor_moved: boolean}, callback: fun())}
local cmdline_events = {
  -- Model the external 1.x boundary before Orbit installs its compatibility guard.
  suppress_events_for_callback = function(self, callback)
    local before = vim.fn.getcmdpos()
    callback()
    self.ignore_next_cursor_moved = true
    if vim.fn.getcmdpos() == before then
      vim.defer_fn(function() self.ignore_next_cursor_moved = false end, 20)
    end
  end,
}

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("completion imports no external plugins and advertises native defaults", function()
  assert(#feature.spec() == 0)
  orbit.setup()
  local item = feature.spec()[1]
  assert(item[1] == "saghen/blink.cmp" and item.version == "1.*")
  assert(vim.deep_equal(item.event, { "InsertEnter", "CmdlineEnter", "LspAttach" }))
  assert(item.dependencies[1][1] == "L3MON4D3/LuaSnip")
  assert(item.dependencies[2][1] == "windwp/nvim-autopairs")
  assert(item.dependencies[3][1] == "folke/lazydev.nvim")
  assert(item.opts.keymap.preset == "enter")
  assert(item.opts.keymap["<C-y>"][1] == "select_and_accept")
  assert(item.opts.completion.documentation.auto_show_delay_ms == 200)
  assert(item.opts.sources.default[1] == "lazydev")
  assert(item.opts.sources.default[2] == "lsp")
  assert(item.opts.sources.providers.lazydev.module == "lazydev.integrations.blink")
  assert(item.opts.snippets.preset == "luasnip")
  assert(package.loaded["blink.cmp"] == nil)
end)

check("Blink keymaps implement toggle and snippet fallback", function()
  local item = feature.spec()[1]
  local visible, show, hide = false, 0, 0
  local cmp = {
    is_visible = function() return visible end,
    show = function() show = show + 1; visible = true end,
    hide = function() hide = hide + 1; visible = false end,
  }
  assert(item.opts.keymap["<C-e>"][1](cmp))
  assert(show == 1)
  assert(item.opts.keymap["<C-e>"][1](cmp))
  assert(hide == 1)
  local jumped = 0
  cmp.snippet_active = function(opts)
    assert(opts.direction == 1)
    return true
  end
  cmp.snippet_forward = function() jumped = jumped + 1; return true end
  assert(item.opts.keymap["<Tab>"][1](cmp))
  assert(jumped == 1)
  cmp.snippet_active = function() return false end
  assert(item.opts.keymap["<Tab>"][1](cmp) == false)
end)

check("LuaSnip setup extends JSX/SQL and installs one cleanup handler", function()
  local configured, extended, loaded, unlinked = 0, {}, 0, 0
  local session = { current_nodes = {}, jump_active = false }
  package.preload.luasnip = function()
    return {
      config = { set_config = function(opts)
        assert(opts.history and opts.updateevents == "TextChanged,TextChangedI")
        configured = configured + 1
      end },
      filetype_extend = function(ft, values)
        extended[ft] = values
      end,
      session = session,
      unlink_current = function() unlinked = unlinked + 1 end,
    }
  end
  package.preload["luasnip.loaders.from_vscode"] = function()
    return { lazy_load = function(opts)
      assert(opts.exclude[1] == "sql")
      loaded = loaded + 1
    end }
  end
  package.preload["luasnip.loaders.from_lua"] = function()
    return { load = function() loaded = loaded + 1 end }
  end

  local snip = feature.spec()[1].dependencies[1]
  snip.config(nil, snip.opts)
  snip.config(nil, snip.opts)
  assert(configured == 1 and loaded == 2)
  assert(extended.jsx[2] == "javascriptreact")
  assert(extended.sql[1] == "tsql")
  assert(#vim.api.nvim_get_autocmds({
    group = "OrbitSnippets", event = "InsertLeave",
  }) == 1)

  local buf = vim.api.nvim_get_current_buf()
  session.current_nodes[buf] = {}
  vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf, modeline = false })
  assert(unlinked == 1)
  package.loaded.luasnip, package.preload.luasnip = nil, nil
  package.loaded["luasnip.loaders.from_vscode"],
    package.preload["luasnip.loaders.from_vscode"] = nil, nil
  package.loaded["luasnip.loaders.from_lua"],
    package.preload["luasnip.loaders.from_lua"] = nil, nil
end)

check("Blink and autopairs config callbacks each call their plugin once", function()
  local blink_calls, pair_calls = 0, 0
  package.preload["blink.cmp"] = function()
    return { setup = function(opts)
      assert(opts.completion.ghost_text.enabled == false)
      blink_calls = blink_calls + 1
    end }
  end
  package.preload["blink.cmp.lib.cmdline_events"] = function() return cmdline_events end
  package.preload["nvim-autopairs"] = function()
    return { setup = function(opts)
      assert(opts.disable_filetype[2] == "vim")
      pair_calls = pair_calls + 1
    end }
  end
  local item = feature.spec()[1]
  item.config(nil, item.opts)
  item.config(nil, item.opts)
  local pairs = item.dependencies[2]
  pairs.config(nil, pairs.opts)
  assert(blink_calls == 1 and pair_calls == 1)
  package.loaded["blink.cmp"], package.preload["blink.cmp"] = nil, nil
  package.loaded["blink.cmp.lib.cmdline_events"], package.preload["blink.cmp.lib.cmdline_events"] = nil, nil
  package.loaded["nvim-autopairs"], package.preload["nvim-autopairs"] = nil, nil
end)

check("older commandline timeouts cannot release newer previews or other instances", function()
  local original_pos, original_mode, original_defer = vim.fn.getcmdpos, vim.api.nvim_get_mode, vim.defer_fn
  local cursor, mode = 1, "c"
  ---@type fun()[]
  local deferred = {}
  vim.fn.getcmdpos = function() return cursor end
  vim.api.nvim_get_mode = function() return { mode = mode } end
  vim.defer_fn = function(callback, delay)
    assert(delay == 20)
    deferred[#deferred + 1] = callback
  end
  local ok, err = xpcall(function()
    local first = { ignore_next_cursor_moved = false }
    local second = { ignore_next_cursor_moved = false }
    cmdline_events.suppress_events_for_callback(first, function() end)
    assert(#deferred == 1 and first.ignore_next_cursor_moved)
    cmdline_events.suppress_events_for_callback(first, function() cursor = 2 end)
    assert(#deferred == 1, "cursor-changing preview scheduled a release")
    deferred[1]()
    assert(first.ignore_next_cursor_moved, "old timeout cleared newer preview suppression")
    cmdline_events.suppress_events_for_callback(first, function() end)
    cmdline_events.suppress_events_for_callback(second, function() end)
    assert(#deferred == 3)
    deferred[2]()
    assert(not first.ignore_next_cursor_moved and second.ignore_next_cursor_moved,
      "latest release changed another event instance")
    deferred[3]()
    assert(not second.ignore_next_cursor_moved, "latest no-movement timeout did not release")
    mode = "n"
    local called = false
    cmdline_events.suppress_events_for_callback(first, function() called = true end)
    assert(called and not first.ignore_next_cursor_moved and #deferred == 3,
      "non-commandline callback changed suppression")
  end, debug.traceback)
  vim.fn.getcmdpos, vim.api.nvim_get_mode, vim.defer_fn = original_pos, original_mode, original_defer
  assert(ok, err)
end)

check("documentation deduplicates detail without discarding Markdown", function()
  local recorded
  runtime.draw_documentation({
    item = { detail = "local value", documentation = "Document text" },
    default_implementation = function(content)
      recorded = content
    end,
  })
  assert(recorded and recorded.detail == "")
  local value = recorded.documentation.value
  assert(value:find("local value", 1, true))
  assert(value:find("Document text", 1, true))
  assert(value:find(string.rep(string.char(96), 3), 1, true))
end)

check("invalid settings and restart-only edits retain accepted state", function()
  local original = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    completion = { documentation_delay = -1 },
  } })
  assert(not ok and tostring(err):find("documentation_delay", 1, true))
  assert(vim.deep_equal(orbit.get_config(), original))
  orbit.setup({ modules = { completion = { ghost_text = true } } })
  assert(orbit.get_config().modules.completion.ghost_text == false)
  assert(orbit.get_pending_restart()["orbit.modules.completion.ghost_text"] == true)
end)

print(string.format("%d completion tests passed.", passed))
