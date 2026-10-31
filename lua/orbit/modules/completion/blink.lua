local M = {}

local function snippet_forward(cmp)
  if cmp.snippet_active({ direction = 1 }) then
    return cmp.snippet_forward()
  end
  return false
end

---@param opts Orbit.CompletionOptions
function M.build(opts)
  return {
    snippets = { preset = "luasnip" },
    keymap = {
      preset = opts.preset,
      ["<C-p>"] = { "select_prev", "fallback" },
      ["<C-n>"] = { "select_next", "fallback" },
      ["<C-j>"] = { "select_next", "fallback" },
      ["<C-k>"] = { "select_prev", "fallback" },
      ["<C-S>"] = { "show", "show_documentation", "hide_documentation" },
      ["<C-u>"] = { "scroll_documentation_up", "fallback" },
      ["<C-d>"] = { "scroll_documentation_down", "fallback" },
      ["<C-e>"] = { function(cmp)
        if cmp.is_visible() then cmp.hide() else cmp.show() end
        return true
      end },
      ["<C-y>"] = { "select_and_accept" },
      ["<Tab>"] = { snippet_forward, "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
    },
    appearance = { nerd_font_variant = "mono" },
    completion = {
      accept = { create_undo_point = true, auto_brackets = { enabled = true } },
      list = { selection = { preselect = true, auto_insert = true } },
      menu = {
        border = "rounded",
        draw = { treesitter = { "lsp" }, columns = {
          { "kind_icon" },
          { "label", "label_description", gap = 1 },
          { "source_name" },
        } },
      },
      documentation = {
        auto_show = opts.documentation_auto_show,
        auto_show_delay_ms = opts.documentation_delay,
        draw = function(options)
          return require("orbit.modules.completion.runtime")
            .draw_documentation(options)
        end,
        window = { border = "rounded" },
      },
      ghost_text = { enabled = opts.ghost_text },
    },
    cmdline = {
      enabled = opts.cmdline,
      keymap = {
        preset = "cmdline",
        ["<Right>"] = false, ["<Left>"] = false,
        ["<C-j>"] = { "select_next", "fallback" },
        ["<C-k>"] = { "select_prev", "fallback" },
      },
      completion = {
        list = { selection = { preselect = false } },
        menu = { auto_show = function()
          return vim.fn.getcmdtype() == ":"
        end },
        ghost_text = { enabled = true },
      },
    },
    sources = {
      default = { "lazydev", "lsp", "path", "snippets", "buffer" },
      per_filetype = { lua = { inherit_defaults = true, "lazydev" } },
      providers = {
        lazydev = {
          name = "LazyDev", module = "lazydev.integrations.blink",
          score_offset = 100,
        },
        lsp = { fallbacks = {} },
      },
    },
    fuzzy = { implementation = "prefer_rust_with_warning" },
  }
end

return M
