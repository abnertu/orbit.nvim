-- Build the native completion helpers through Orbit's Lazy callbacks.
-- Requires Git, network, make and a C compiler; missing tools fail the test.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
-- LuaSnip's jsregexp Makefile does not quote include paths, so avoid spaces here.
local workspace = vim.fn.tempname() .. "-live-native-builds"
-- Blink downloads its prebuilt matcher only from a release tag checkout.
local blink = { "https://github.com/saghen/blink.cmp.git", "v1.10.2", "78336bc89ee5365633bcf754d93df01678b5c08f" }
local luasnip = { "https://github.com/L3MON4D3/LuaSnip.git", "0abc8f390b278c3b4aabc4c004ac8a088b65cf24" }

local function run(argv, cwd)
  local result = vim.system(argv, { text = true, timeout = 300000, cwd = cwd }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or "") .. tostring(result.stdout or ""))
  return result.stdout or ""
end

local function checkout(name, url, ref, commit)
  local directory = vim.fs.joinpath(workspace, name)
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  -- LuaSnip resolves its jsregexp submodule relative to the origin remote.
  run({ "git", "-C", directory, "remote", "add", "origin", url })
  run({ "git", "-C", directory, "fetch", "--depth", "1", "origin", ref })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == commit)
  vim.opt.rtp:prepend(directory)
  return directory
end

local ok, err = xpcall(function()
  for _, tool in ipairs({ "git", "make" }) do
    assert(vim.fn.executable(tool) == 1, tool .. " is required on PATH")
  end
  local blink_dir = checkout("blink.cmp", blink[1], "refs/tags/" .. blink[2] .. ":refs/tags/" .. blink[2], blink[3])
  local luasnip_dir = checkout("LuaSnip", luasnip[1], luasnip[2], luasnip[2])

  require("orbit").setup()
  local spec = require("orbit.modules.completion").spec()[1]
  assert(spec[1] == "saghen/blink.cmp", "Orbit did not declare Blink")
  local snippets
  for _, dependency in ipairs(spec.dependencies) do
    if dependency[1] == "L3MON4D3/LuaSnip" then snippets = dependency end
  end
  assert(snippets, "Orbit did not declare LuaSnip")

  snippets.build({ dir = luasnip_dir })
  snippets.config(snippets, snippets.opts)
  assert(require("luasnip.util.jsregexp") ~= false, "LuaSnip did not load the built jsregexp")
  print("PASS Orbit builds and loads LuaSnip jsregexp")

  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  vim.cmd.startinsert()
  require("luasnip").lsp_expand("${1:orbit} ${1/(.*)/${1:/upcase}/}")
  vim.cmd.stopinsert()
  local line
  assert(vim.wait(5000, function()
    line = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1]
    return line == "orbit ORBIT"
  end, 20), "regex transform did not expand: " .. tostring(line))
  print("PASS a LuaSnip regex transform expands with jsregexp")

  assert(spec.opts.fuzzy.implementation == "prefer_rust_with_warning")
  spec.config(spec, spec.opts)
  local fuzzy = require("blink.cmp.fuzzy")
  assert(vim.wait(240000, function() return fuzzy.implementation_type == "rust" end, 100),
    "Blink did not activate the Rust matcher: " .. tostring(fuzzy.implementation_type))
  assert(vim.fn.filereadable(vim.fs.joinpath(blink_dir, "target", "release", "version")) == 1,
    "Blink did not record the downloaded matcher version")
  print("PASS Blink downloads and activates the Rust fuzzy matcher")
end, debug.traceback)

vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real native completion builds passed.")
