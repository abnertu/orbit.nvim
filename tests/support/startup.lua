-- Child-only observations around real startup; runtime behavior stays with Orbit.
---@class Orbit.StartupTestOptions
---@field root string
---@field lazy string
---@field plugins boolean
---@field interface boolean

---@class Orbit.StartupTestEvent
---@field event string
---@field buffer integer
---@field name string
---@field ui boolean
---@field shiftwidth integer

---@class Orbit.StartupTestBuffer
---@field id integer
---@field name string
---@field listed boolean
---@field buftype string

---@class Orbit.StartupTestSnapshot
---@field entered boolean
---@field journal Orbit.StartupTestEvent[]
---@field buffers Orbit.StartupTestBuffer[]
---@field current integer
---@field name string
---@field lines string[]
---@field cwd string
---@field fileposts integer
---@field setups integer
---@field status string
---@field lazy_loaded boolean
---@field shiftwidth integer
---@field tabstop integer
---@field errors string[]
---@field errmsg string

---@param opts Orbit.StartupTestOptions
return function(opts)
  vim.opt.rtp:prepend(opts.root)
  -- Keep user packages outside the fixture while retaining built-in plugins.
  vim.o.packpath = vim.env.VIMRUNTIME
  -- Exercise Orbit's directory owner without netrw replacing its argument.
  vim.g.loaded_netrwPlugin = 1
  vim.g.editorconfig = true
  vim.cmd("filetype plugin indent on")

  ---@type Orbit.StartupTestEvent[]
  local journal = {}
  ---@type string[]
  local errors = {}
  local fileposts, setups, first_file = 0, 0, nil
  local group = vim.api.nvim_create_augroup("OrbitTestStartup", {})

  ---@param event string
  ---@param buffer integer
  local function record(event, buffer)
    journal[#journal + 1] = {
      event = event, buffer = buffer,
      name = vim.api.nvim_buf_get_name(buffer),
      ui = #vim.api.nvim_list_uis() > 0,
      shiftwidth = vim.bo[buffer].shiftwidth,
    }
  end

  vim.notify = function(message, level)
    if level and level >= vim.log.levels.WARN then
      errors[#errors + 1] = tostring(message)
    end
  end
  vim.api.nvim_create_autocmd({
    "VimEnter", "UIEnter", "BufReadPre", "BufReadPost", "BufNewFile", "FileType",
  }, {
    group = group,
    callback = function(event)
      record(event.event, event.buf)
      if event.event == "FileType" and event.buf == first_file then
        -- Only the real EditorConfig replay can restore the project value.
        vim.bo[event.buf].shiftwidth = 11
        vim.bo[event.buf].tabstop = 11
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "FilePost",
    callback = function(event)
      fileposts = fileposts + 1
      first_file = event.buf
      record("FilePost", event.buf)
    end,
  })

  -- Delegate to the actual built-in implementation, including native calls.
  local editorconfig = require("editorconfig")
  local configure = editorconfig.config
  editorconfig.config = function(buffer)
    configure(buffer)
    record("EditorConfig", buffer)
  end

  if opts.interface then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group, once = true,
      callback = function()
        vim.bo.buftype = "nofile"
        vim.bo.buflisted = false
        vim.api.nvim_buf_set_name(0, "orbit-test-startup-interface")
      end,
    })
  end

  local orbit = require("orbit")
  local options = { modules = { plugins = {
    enabled = opts.plugins, path = opts.plugins and opts.lazy or "",
  } } }
  orbit.setup(options)

  -- RPC requests access closure-owned state without adding internal globals.
  package.loaded["orbit.tests.startup"] = {
    -- The local Git fixture calls this only when Orbit activates its checkout.
    lazy_setup = function()
      setups = setups + 1
      vim.api.nvim_create_autocmd("BufReadPre", {
        group = vim.api.nvim_create_augroup("OrbitTestLazyRead", {}),
        callback = function(event) record("LazyRead", event.buf) end,
      })
    end,
    ---@return Orbit.StartupTestSnapshot
    snapshot = function()
      ---@type Orbit.StartupTestBuffer[]
      local buffers = {}
      for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        buffers[#buffers + 1] = {
          id = buffer, name = vim.api.nvim_buf_get_name(buffer),
          listed = vim.bo[buffer].buflisted, buftype = vim.bo[buffer].buftype,
        }
      end
      return {
        entered = vim.v.vim_did_enter == 1,
        journal = journal, buffers = buffers,
        current = vim.api.nvim_get_current_buf(), name = vim.api.nvim_buf_get_name(0),
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false), cwd = vim.fn.getcwd(),
        fileposts = fileposts, setups = setups,
        status = require("orbit.modules.plugins").status(),
        lazy_loaded = package.loaded.lazy ~= nil,
        shiftwidth = vim.bo.shiftwidth, tabstop = vim.bo.tabstop,
        errors = errors, errmsg = vim.v.errmsg,
      }
    end,
    repeat_setup = function()
      orbit.setup(options)
      orbit.setup(options)
    end,
    ---@param path string
    edit = function(path) vim.cmd.edit(vim.fn.fnameescape(path)) end,
  }
end
