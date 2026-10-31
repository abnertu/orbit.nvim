-- Debounced lint execution with timer ownership tied to each buffer.
local M = {}
local generation = 0
local timers = {}
local group
local editing = {}

local function close_timer(buf)
  local timer = timers[buf]
  timers[buf] = nil
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
  end
end

local function linters_for(lint, ft)
  local exact = lint.linters_by_ft[ft]
  if exact then return vim.deepcopy(exact) end
  local result, seen = {}, {}
  for _, part in ipairs(vim.split(ft, ".", { plain = true })) do
    for _, name in ipairs(lint.linters_by_ft[part] or {}) do
      if not seen[name] then
        seen[name] = true
        result[#result + 1] = name
      end
    end
  end
  return result
end

local function run(lint, opts, buf, only_edit)
  if not vim.api.nvim_buf_is_valid(buf) or
    not vim.api.nvim_buf_is_loaded(buf) or
    vim.api.nvim_get_option_value("buftype", { buf = buf }) ~= ""
  then
    return
  end
  local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
  if ft == "bigfile" then return end

  local names = linters_for(lint, ft)
  if only_edit then
    names = vim.tbl_filter(function(name)
      return not vim.tbl_contains(opts.skip_while_editing, name)
    end, names)
  end
  if #names == 0 then return end
  vim.api.nvim_buf_call(buf, function()
    lint.try_lint(names)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "NvimLintRunPost", modeline = false,
    })
  end)
end

function M.setup(opts)
  generation = generation + 1
  local current_generation = generation
  for buf in pairs(timers) do close_timer(buf) end
  editing = {}
  local lint = require("lint")
  lint.linters_by_ft = vim.deepcopy(opts.linters_by_ft)
  vim.env.ESLINT_D_PPID = tostring(vim.fn.getpid())

  group = vim.api.nvim_create_augroup("OrbitLint", { clear = true })
  vim.api.nvim_create_autocmd(opts.events, {
    group = group,
    callback = function(event)
      local buf = event.buf
      editing[buf] = editing[buf] ~= false and event.event == "TextChanged"
      close_timer(buf)
      local timer = assert(vim.uv.new_timer(), "could not allocate lint timer")
      timers[buf] = timer
      timer:start(opts.debounce_ms, 0, function()
        vim.schedule(function()
          if generation ~= current_generation or timers[buf] ~= timer then
            return
          end
          close_timer(buf)
          local only_edit = editing[buf]
          editing[buf] = nil
          local ok, err = pcall(run, lint, opts, buf, only_edit)
          if not ok then
            vim.notify("Lint failed: " .. tostring(err), vim.log.levels.WARN)
          end
        end)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      close_timer(event.buf)
      editing[event.buf] = nil
    end,
  })
end

return M
