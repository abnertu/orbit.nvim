-- Verify the specialist TypeScript diagnostic handler through real Neovim LSP.
-- A local Lua TCP server speaks JSON-RPC; no TypeScript tool is mocked or loaded.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local uv = vim.uv
local listener, peer
local protocol_error
local function close(h)
  if h and not h:is_closing() then h:close() end
end

local ok, err = xpcall(function()
  require("orbit").setup()
  local provider = require("orbit.modules.lsp_providers.runtime")
  local opts = provider.typescript_options(
    require("orbit").get_config().modules.lsp_providers)
  assert(package.loaded["typescript-tools"] == nil,
    "specialist provider unexpectedly imported TypeScript tools")
  assert(type(opts.handlers["textDocument/publishDiagnostics"]) == "function")

  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".ts")
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
    "const example: number = 1;",
  })
  vim.api.nvim_set_option_value("filetype", "typescript", { buf = buffer })
  local file_uri = vim.uri_from_bufnr(buffer)

  local request_log, next_seq, bytes = {}, 80, ""
  local published = false
  local function send(message)
    local json = vim.json.encode(message)
    peer:write("Content-Length: " .. #json .. "\r\n\r\n" .. json)
  end
  local function reply(request, body)
    next_seq = next_seq + 1
    send({
      jsonrpc = "2.0", id = request.id, result = body or vim.empty_dict(),
    })
  end
  local function publish()
    local function d(source, message)
      return {
        range = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 5 },
        },
        severity = 2, source = source, message = message,
      }
    end
    published = true
    send({
      jsonrpc = "2.0", method = "textDocument/publishDiagnostics",
      params = {
        uri = file_uri, diagnostics = {
          d("tsserver", "duplicate"), d("tsserver", "duplicate"),
          d("tsserver", "distinct"),
          d("other", "repeat"), d("other", "repeat"),
        },
      },
    })
  end
  local function handle(message)
    if not message.method then return end
    request_log[#request_log + 1] = message.method
    if message.method == "initialize" then
      assert(message.id ~= nil)
      reply(message, { capabilities = {
        textDocumentSync = { openClose = true, change = 1 },
        semanticTokensProvider = {
          legend = { tokenTypes = {}, tokenModifiers = {} },
          full = true,
        },
      }, serverInfo = { name = "orbit-lua-fixture" } })
    elseif message.method == "initialized" then
      -- didOpen is delivered immediately after the server initializes.
    elseif message.method == "textDocument/didOpen" then
      assert(message.params.textDocument.uri == file_uri)
      publish()
    elseif message.method == "shutdown" then
      reply(message)
    elseif message.method == "exit" then
      close(peer)
    elseif message.id ~= nil then
      reply(message)
    end
  end
  local function receive(chunk)
    bytes = bytes .. chunk
    while true do
      local boundary = bytes:find("\r\n\r\n", 1, true)
      if not boundary then return end
      local size = tonumber(bytes:sub(1, boundary - 1)
        :match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
      assert(size and size > 0, "LSP frame missing Content-Length")
      if #bytes < boundary + 3 + size then return end
      local payload = bytes:sub(boundary + 4, boundary + 3 + size)
      bytes = bytes:sub(boundary + 4 + size)
      handle(vim.json.decode(payload))
    end
  end

  listener = assert(uv.new_tcp())
  assert(listener:bind("127.0.0.1", 0))
  local port = assert(listener:getsockname()).port
  assert(listener:listen(1, function(failure)
    if failure then protocol_error = tostring(failure); return end
    peer = assert(uv.new_tcp())
    assert(listener:accept(peer))
    peer:read_start(function(read_error, chunk)
      if read_error then protocol_error = tostring(read_error); return end
      if not chunk then return end
      local good, message = xpcall(function() receive(chunk) end, debug.traceback)
      if not good then protocol_error = message end
    end)
  end))

  local client_id = assert(vim.lsp.start({
    name = "orbit-typescript-live",
    cmd = vim.lsp.rpc.connect("127.0.0.1", port),
    root_dir = vim.fn.getcwd(),
    filetypes = opts.filetypes,
    handlers = opts.handlers,
    on_attach = opts.on_attach,
  }), "native LSP failed to start its TCP client")

  assert(vim.wait(12000, function()
    return protocol_error ~= nil or
      (published and #vim.diagnostic.get(buffer) == 4)
  end, 25), "native TypeScript diagnostics did not arrive")
  assert(not protocol_error, tostring(protocol_error))
  local diagnostics = vim.diagnostic.get(buffer)
  local counts = {}
  for _, diagnostic in ipairs(diagnostics) do
    counts[diagnostic.message] = (counts[diagnostic.message] or 0) + 1
  end
  assert(counts.duplicate == 1 and counts.distinct == 1
      and counts["repeat"] == 2,
    "TypeScript duplicate filtering removed distinct/other diagnostics: "
      .. vim.inspect(counts))
  assert(vim.tbl_contains(request_log, "initialize")
    and vim.tbl_contains(request_log, "textDocument/didOpen"))
  print("PASS real Neovim LSP publishDiagnostics deduplicates only tsserver")

  local client = assert(vim.lsp.get_client_by_id(client_id))
  assert(client.initialized)
  assert(client.server_capabilities.semanticTokensProvider == nil,
    "TypeScript provider did not disable conflicting semantic tokens")
  client:stop()
  assert(vim.wait(12000, function()
    return protocol_error ~= nil
      or (vim.tbl_contains(request_log, "shutdown")
        and vim.tbl_contains(request_log, "exit"))
  end, 25), "native LSP client failed to shut down cleanly")
  assert(not protocol_error, tostring(protocol_error))
  print("PASS real TypeScript LSP initialize/on_attach and shutdown lifecycle")
  vim.api.nvim_buf_delete(buffer, { force = true })
end, debug.traceback)

close(peer)
close(listener)
assert(ok, tostring(err))
print("Native TCP TypeScript LSP integration tests passed.")
