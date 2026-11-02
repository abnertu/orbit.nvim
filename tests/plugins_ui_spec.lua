-- Late UI subscribers receive their first event without replaying old observers.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local earlier, grouped, ungrouped = 0, 0, 0
vim.api.nvim_create_autocmd("UIEnter", {
  callback = function()
    earlier = earlier + 1
  end,
})
package.preload.lazy = function()
  return {
    setup = function()
      vim.api.nvim_create_autocmd("UIEnter", {
        group = vim.api.nvim_create_augroup("OrbitTestLateUI", {}),
        once = true,
        callback = function()
          grouped = grouped + 1
        end,
      })
      vim.api.nvim_create_autocmd("UIEnter", {
        once = true,
        callback = function(event)
          assert(event.event == "UIEnter" and not event.group and event.buf > 0)
          assert(event.data.token == "first", "UI subscriber lost its event data")
          ungrouped = ungrouped + 1
        end,
      })
    end,
  }
end
require("orbit").setup({ modules = { plugins = { enabled = true } } })
vim.api.nvim_exec_autocmds("UIEnter", { modeline = false, data = { token = "first" } })
assert(earlier == 1, "earlier UI observer replayed")
assert(grouped == 1 and ungrouped == 1, "new UI subscribers missed the first UIEnter")
vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
assert(earlier == 2 and grouped == 1 and ungrouped == 1, "one-shot UI subscribers ran twice")
print("PASS first UI demand reaches only new observers and preserves once semantics")
