-- Noice options are constructed only at its Lazy activation boundary.
local M = {}

---@alias Orbit.NoiceOptions {routes: table<string, any>[], cmdline: table<string, any>, messages: table<string, boolean>, popupmenu: table<string, any>, lsp: table<string, any>, presets: table<string, boolean>, views: table<string, any>}

local ignored_messages = {
  "; after #%d+", "; before #%d+",
  "%d+L, %d+B", "%d+ fewer lines", "%d+ more lines",
  "%d+ lines yanked", "%d+ lines moved",
  "%d+ lines [><]ed%s+%d+ time",
  "Error INVALID_SERVER_MESSAGE: nil",
  "snacks/util/init.lua:207: Invalid window id",
}
local ignored_progress = { "Searching in files", "pyright" }

local function any(patterns)
  return vim.tbl_map(function(pattern)
    return { find = pattern }
  end, patterns)
end

local function docs_size(c)
  return {
    max_width = math.max(1, math.min(c.doc_max_width,
      math.floor(vim.o.columns * 0.5))),
    max_height = math.max(1, math.min(c.doc_max_height,
      math.floor(vim.o.lines * 0.4))),
  }
end

---@param c Orbit.MessagesOptions
---@return Orbit.NoiceOptions
function M.options(c)
  local documentation_window = { border = "single", size = docs_size(c) }
  return {
    routes = {
      {
        view = "formatter_progress",
        opts = { timeout = 5000 },
        filter = {
          event = "notify",
          cond = function(message)
            return message.opts and message.opts.orbit_formatter ~= nil
          end,
        },
      },
      {
        view = "notify",
        filter = { event = "msg_show", any = any(ignored_messages) },
        opts = { skip = true },
      },
      {
        view = "mini",
        filter = {
          event = "lsp", kind = "progress", any = any(ignored_progress),
        },
        opts = { skip = true },
      },
    },
    cmdline = { enabled = c.cmdline, view = "cmdline_popup" },
    messages = { enabled = c.messages },
    popupmenu = { enabled = c.popupmenu, backend = "nui" },
    lsp = {
      override = {
        ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
        ["vim.lsp.util.stylize_markdown"] = true,
        ["cmp.entry.get_documentation"] = true,
      },
      hover = {
        enabled = c.hover, silent = true,
        opts = vim.deepcopy(documentation_window),
      },
      signature = {
        enabled = c.signature,
        auto_open = {
          enabled = true, trigger = true,
          luasnip = true, throttle = 50,
        },
        opts = vim.tbl_extend("force", vim.deepcopy(documentation_window), {
          focusable = false,
        }),
      },
      progress = { enabled = c.progress },
      message = { enabled = c.lsp_message },
    },
    presets = {
      bottom_search = true,
      command_palette = true,
      long_message_to_split = true,
      inc_rename = false,
      lsp_doc_border = true,
    },
    views = {
      formatter_progress = {
        view = "mini",
        format = {
          { "{data.orbit_formatter_icon} ",
            hl_group = "NoiceLspProgressSpinner" },
          { "{message}", hl_group = "NoiceLspProgressTitle" },
        },
      },
      popup = {
        win_options = {
          winhighlight = {
            Normal = "BlinkCmpMenu",
            FloatBorder = "BlinkCmpMenuBorder",
          },
        },
      },
      mini = { position = { row = -3, col = "100%" } },
      popupmenu = { position = "bottom" },
      cmdline_popup = {
        border = { style = "rounded" },
        position = { col = 0.5, row = 0.3 },
      },
      cmdline_popupmenu = {
        border = { style = "rounded" },
        position = { col = 0.5, row = 0.56 },
      },
    },
  }
end

return M
