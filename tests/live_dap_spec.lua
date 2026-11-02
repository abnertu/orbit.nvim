-- Real pinned nvim-dap client against a Lua-owned DAP TCP adapter.
-- The fixture provides the wire protocol, not a mock of the nvim-dap API.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local pinned = "e03a0f2b786ccbf3398ed445d9700df8ed1e7627"
local source = "https://github.com/Orbit-Lua/nvim-dap.git"
local directory = vim.fn.tempname() .. " live dap with spaces"
local listener, client
local protocol_error

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. " failed: "
    .. tostring(result.stderr or result.stdout or result.code))
  return result.stdout or ""
end

local function close(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1", source, pinned })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pinned,
    "nvim-dap checkout revision mismatch")
  vim.opt.rtp:prepend(directory)

  local orbit = require("orbit")
  local feature = require("orbit.modules.dap")
  orbit.setup({ modules = { dap = { coreclr = false } } })
  assert(package.loaded.dap == nil, "root setup eagerly imported nvim-dap")
  local spec = feature.spec()[1]
  assert(spec and spec[1] == "Orbit-Lua/nvim-dap")
  assert(type(spec.config) == "function")
  spec.config()
  local dap = require("dap")
  assert(type(dap.adapters.python) == "function",
    "Orbit failed to register Python through real nvim-dap")
  assert(#dap.configurations.python == 2,
    "Orbit did not register real nvim-dap Python configurations")
  spec.config()
  assert(#dap.configurations.python == 2,
    "repeated callback registered duplicate configurations")
  print("PASS pinned real nvim-dap Lazy activation and adapter ownership")

  local requests = {}
  local sequence = 100
  local received = ""
  local function send(payload)
    local body = vim.json.encode(payload)
    client:write("Content-Length: " .. #body .. "\r\n\r\n" .. body)
  end
  local function respond(req, body)
    sequence = sequence + 1
    send({
      seq = sequence, type = "response", success = true,
      command = req.command, request_seq = req.seq, body = body or {},
    })
  end
  local function on_message(request)
    if request.type ~= "request" then return end
    requests[#requests + 1] = request
    if request.command == "initialize" then
      assert(request.arguments.clientID == "neovim")
      respond(request, { supportsConfigurationDoneRequest = true })
    elseif request.command == "attach" then
      assert(request.arguments.request == "attach")
      respond(request)
      sequence = sequence + 1
      send({ seq = sequence, type = "event", event = "initialized", body = {} })
    elseif request.command == "setBreakpoints" then
      local bps = request.arguments.breakpoints or {}
      local reply = {}
      for _, bp in ipairs(bps) do
        reply[#reply + 1] = { verified = true, line = bp.line }
      end
      respond(request, { breakpoints = reply })
    elseif request.command == "configurationDone" then
      respond(request)
    elseif request.command == "disconnect" then
      respond(request)
    else
      error("Unexpected real DAP request: " .. tostring(request.command))
    end
  end
  local function consume(chunk)
    received = received .. chunk
    while true do
      local finish = received:find("\r\n\r\n", 1, true)
      if not finish then return end
      local header = received:sub(1, finish - 1)
      local length = tonumber(header:match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
      assert(length and length > 0, "missing DAP Content-Length header")
      if #received < finish + 3 + length then return end
      local body = received:sub(finish + 4, finish + 3 + length)
      received = received:sub(finish + 4 + length)
      on_message(vim.json.decode(body))
    end
  end
  listener = assert(vim.uv.new_tcp())
  assert(listener:bind("127.0.0.1", 0))
  local port = assert(listener:getsockname()).port
  assert(listener:listen(8, function(failure)
    if failure then
      protocol_error = tostring(failure)
      return
    end
    client = assert(vim.uv.new_tcp())
    assert(listener:accept(client))
    client:read_start(function(read_error, chunk)
      if read_error then protocol_error = tostring(read_error); return end
      if not chunk then return end
      local valid, message = xpcall(function() consume(chunk) end, debug.traceback)
      if not valid then protocol_error = message end
    end)
  end))

  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".py")
  vim.api.nvim_set_option_value("filetype", "python", { buf = buffer })
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "print('DAP fixture')" })
  dap.set_breakpoint()
  local bps = require("dap.breakpoints").get(buffer)
  assert(type(bps[buffer]) == "table" and #bps[buffer] == 1,
    "real nvim-dap breakpoint was not recorded")

  local config = {
    type = "python", request = "attach", name = "Orbit live Python attach",
    connect = { host = "127.0.0.1", port = port },
  }
  dap.run(config)
  local ready = vim.wait(12000, function()
    return protocol_error ~= nil or (dap.session() ~= nil
      and dap.session().initialized == true)
  end, 20)
  assert(protocol_error == nil, tostring(protocol_error))
  assert(ready and dap.session() and dap.session().initialized,
    "real nvim-dap did not complete DAP initialize/attach/configurationDone")
  local names = vim.tbl_map(function(req) return req.command end, requests)
  assert(vim.deep_equal(names, {
    "initialize", "attach", "setBreakpoints", "configurationDone",
  }), "DAP message order or breakpoint registration failed: " .. vim.inspect(names))
  assert(requests[3].arguments.source.path ~= nil,
    "real DAP setBreakpoints was missing the source path")
  assert(requests[3].arguments.breakpoints[1].line == 1,
    "real DAP setBreakpoints had an incorrect source line")
  print("PASS real DAP TCP initialize/attach/breakpoints/configurationDone")

  local disconnected = false
  dap.disconnect({}, function(failure)
    assert(not failure, "real DAP disconnect failed")
    disconnected = true
  end)
  assert(vim.wait(12000, function()
    return protocol_error ~= nil or disconnected
  end, 20), "real DAP disconnect did not acknowledge")
  assert(not protocol_error, tostring(protocol_error))
  assert(vim.wait(5000, function()
    return dap.session() == nil
  end, 20), "real DAP session stayed registered after disconnect")
  assert(requests[#requests].command == "disconnect")
  print("PASS real DAP TCP disconnect and client session cleanup")
  dap.clear_breakpoints()
  vim.api.nvim_buf_delete(buffer, { force = true })
end, debug.traceback)

close(client)
close(listener)
vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned real nvim-dap integration tests passed.")
