-- External completion APIs are accessed only from their Lazy callbacks.
local M = {}
local snippets_started = false
local blink_started = false

function M.build_luasnip(plugin)
  local command = { "make", "install_jsregexp" }
  if vim.fn.has("win32") == 1 then
    local path = vim.uv.fs_realpath(vim.v.progpath) or vim.v.progpath
    table.insert(command, 2, "NEOVIM_BIN_PATH=" ..
      vim.fs.dirname(vim.fs.normalize(path)))
  end
  local result = vim.system(command, { cwd = plugin.dir, text = true }):wait(120000)
  if result.code ~= 0 then
    error("LuaSnip native build failed:\n" ..
      tostring(result.stderr or "") .. tostring(result.stdout or ""), 0)
  end
end

function M.setup_luasnip(opts)
  if snippets_started then return end
  local luasnip = require("luasnip")
  luasnip.config.set_config(opts)
  luasnip.filetype_extend("jsx", { "javascript", "javascriptreact" })
  luasnip.filetype_extend("sql", { "tsql" })
  require("luasnip.loaders.from_vscode").lazy_load({ exclude = { "sql" } })
  require("luasnip.loaders.from_lua").load()
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = vim.api.nvim_create_augroup("OrbitSnippets", { clear = true }),
    callback = function()
      local session = luasnip.session
      if session.current_nodes[vim.api.nvim_get_current_buf()]
        and not session.jump_active
      then
        luasnip.unlink_current()
      end
    end,
  })
  snippets_started = true
end

local function detail(item)
  local value = item.detail
  if type(value) == "table" then value = table.concat(value, "\n") end
  if type(value) == "string" and value ~= "" then return vim.trim(value) end
end

function M.draw_documentation(opts)
  local item = opts.item
  local lines, markdown = {}, {}
  if type(item.documentation) == "string" or
    type(item.documentation) == "table"
  then
    markdown = vim.lsp.util.convert_input_to_markdown_lines(
      item.documentation, markdown)
  end
  local extra = detail(item)
  if extra and not table.concat(markdown, "\n"):find(extra, 1, true) then
    local ft = vim.bo.filetype:gsub("%..*$", "")
    local fence = string.rep(string.char(96), 3)
    lines[#lines + 1] = fence .. ft
    vim.list_extend(lines, vim.split(extra, "\n", { trimempty = true }))
    lines[#lines + 1] = fence
  end
  vim.list_extend(lines, markdown)
  if #lines == 0 then
    opts.default_implementation()
  else
    opts.default_implementation({
      detail = "",
      documentation = { kind = "markdown", value = table.concat(lines, "\n") },
    })
  end
end

function M.setup_blink(opts)
  if blink_started then return end
  require("orbit.modules.completion.cmdline").install()
  require("blink.cmp").setup(opts)
  blink_started = true
end

return M
