-- Build markdown-preview.nvim through Orbit and drive a real headless browser.
-- Requires Git, network and Chrome or Edge; ORBIT_BROWSER overrides the path.
-- A small Lua WebSocket client speaks the Chrome DevTools Protocol over vim.uv.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local bit = require("bit")
local windows = vim.fn.has("win32") == 1
local pin = { "https://github.com/iamcco/markdown-preview.nvim.git", "a923f5fc5ba36a3b17e289dc35dc17f66d0548ee" }
local workspace = vim.fn.tempname() .. " live markdown preview with spaces"
local browser, socket

local function run(argv, cwd)
  local result = vim.system(argv, { text = true, timeout = 300000, cwd = cwd }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or "") .. tostring(result.stdout or ""))
  return result.stdout or ""
end

local function wait(timeout, predicate, message)
  assert(vim.wait(timeout, predicate, 50), message)
end

local function find_browser()
  local candidates = { vim.env.ORBIT_BROWSER }
  if windows then
    for _, base in ipairs({ vim.env["ProgramFiles"], vim.env["ProgramFiles(x86)"] }) do
      if base then
        candidates[#candidates + 1] = base .. "\\Google\\Chrome\\Application\\chrome.exe"
        candidates[#candidates + 1] = base .. "\\Microsoft\\Edge\\Application\\msedge.exe"
      end
    end
  else
    vim.list_extend(candidates, { "google-chrome", "google-chrome-stable", "chromium",
      "chromium-browser", "microsoft-edge" })
  end
  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= "" and vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
  error("Chrome or Edge is required; set ORBIT_BROWSER")
end

-- Minimal RFC 6455 client: masked text frames out, unfragmented frames in.
local function connect(port, path)
  local tcp, buffer, opened, failure = assert(vim.uv.new_tcp()), "", false, nil
  local messages = {}
  local function frames()
    while #buffer >= 2 do
      local length, offset = bit.band(buffer:byte(2), 0x7f), 3
      if length == 126 then
        if #buffer < 4 then return end
        length, offset = buffer:byte(3) * 256 + buffer:byte(4), 5
      elseif length == 127 then
        if #buffer < 10 then return end
        length = 0
        for index = 3, 10 do length = length * 256 + buffer:byte(index) end
        offset = 11
      end
      if #buffer < offset + length - 1 then return end
      local opcode = bit.band(buffer:byte(1), 0x0f)
      if opcode == 1 then messages[#messages + 1] = buffer:sub(offset, offset + length - 1) end
      buffer = buffer:sub(offset + length)
    end
  end
  tcp:connect("127.0.0.1", port, function(connect_error)
    if connect_error then failure = connect_error; return end
    tcp:read_start(function(read_error, chunk)
      if read_error or not chunk then failure = read_error or "closed"; return end
      buffer = buffer .. chunk
      if not opened then
        local boundary = buffer:find("\r\n\r\n", 1, true)
        if not boundary then return end
        if not buffer:match("^HTTP/1%.1 101") then failure = buffer; return end
        buffer, opened = buffer:sub(boundary + 4), true
      end
      frames()
    end)
    tcp:write(table.concat({
      "GET " .. path .. " HTTP/1.1", "Host: 127.0.0.1:" .. port, "Upgrade: websocket",
      "Connection: Upgrade", "Sec-WebSocket-Key: b3JiaXQtbGl2ZS1wcmV2aWV3",
      "Sec-WebSocket-Version: 13", "", "",
    }, "\r\n"))
  end)
  wait(30000, function() return opened or failure ~= nil end, "DevTools did not accept the socket")
  assert(not failure, "DevTools socket failed: " .. tostring(failure))

  local next_id = 0
  local client = { tcp = tcp }
  function client.call(method, params, session)
    next_id = next_id + 1
    local id = next_id
    local payload = vim.json.encode({ id = id, method = method,
      params = params or vim.empty_dict(), sessionId = session })
    local length = #payload
    local header = length < 126 and string.char(0x81, 0x80 + length)
      or string.char(0x81, 0x80 + 126, math.floor(length / 256), length % 256)
    local mask = { 0x4f, 0x72, 0x62, 0x74 }
    local bytes = {}
    for index = 1, length do
      bytes[index] = string.char(bit.bxor(payload:byte(index), mask[(index - 1) % 4 + 1]))
    end
    tcp:write(header .. string.char(unpack(mask)) .. table.concat(bytes))
    local response
    wait(30000, function()
      for index, message in ipairs(messages) do
        local decoded = vim.json.decode(message)
        if decoded.id == id then
          response = decoded
          table.remove(messages, index)
          return true
        end
      end
      return failure ~= nil
    end, method .. " got no DevTools response")
    assert(response, "DevTools socket failed: " .. tostring(failure))
    assert(not response.error, method .. ": " .. vim.inspect(response.error))
    return response.result
  end
  return client
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  local browser_path = find_browser()
  -- The prebuilt server finds its app directory by this Lazy checkout name.
  local plugin = vim.fs.joinpath(workspace, "markdown-preview.nvim")
  assert(vim.fn.mkdir(plugin, "p") == 1)
  run({ "git", "init", plugin })
  run({ "git", "-C", plugin, "fetch", "--depth", "1", pin[1], pin[2] })
  run({ "git", "-C", plugin, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", plugin, "rev-parse", "HEAD" })) == pin[2])
  vim.opt.rtp:prepend(plugin)

  require("orbit").setup()
  local spec = require("orbit.modules.markdown").spec()[1]
  assert(spec[1] == "iamcco/markdown-preview.nvim", "Orbit did not declare markdown-preview")
  spec.build({ dir = plugin })
  local runtime = require("orbit.modules.markdown.runtime")
  local platform = runtime.platform_name(windows, vim.fn.has("mac") == 1, vim.uv.os_uname().machine)
  assert(vim.uv.fs_stat(runtime.executable(plugin, platform)), "preview build produced no binary")
  print("PASS Orbit builds the real markdown-preview binary")

  -- The browser function records the URL; the test opens it in a real browser.
  vim.cmd([[
    function! OrbitLivePreviewOpen(url) abort
      let g:orbit_live_preview_url = a:url
    endfunction
  ]])
  vim.g.mkdp_browserfunc = "OrbitLivePreviewOpen"
  vim.cmd("filetype on")
  vim.cmd.runtime("plugin/mkdp.vim")
  local note = vim.fs.joinpath(workspace, "note.md")
  assert(vim.fn.writefile({ "# Orbit preview", "", "first-revision" }, note) == 0)
  vim.cmd.edit(vim.fn.fnameescape(note))
  local buffer = vim.api.nvim_get_current_buf()
  assert(vim.fn.exists(":MarkdownPreviewToggle") == 2, "preview commands are missing")
  vim.cmd.MarkdownPreviewToggle()
  wait(60000, function() return vim.g.orbit_live_preview_url ~= nil end,
    "markdown-preview did not report a page URL")
  local url = vim.g.orbit_live_preview_url
  print("PASS MarkdownPreviewToggle starts the server at " .. url)

  local profile = vim.fs.joinpath(workspace, "browser profile")
  assert(vim.fn.mkdir(profile, "p") == 1)
  browser = vim.system({ browser_path, "--headless=new", "--no-sandbox", "--no-first-run",
    "--disable-gpu", "--remote-debugging-port=0", "--user-data-dir=" .. profile, url })
  local active = vim.fs.joinpath(profile, "DevToolsActivePort")
  wait(60000, function() return vim.fn.filereadable(active) == 1
    and #vim.fn.readfile(active) >= 2 end, "browser did not open DevTools")
  local lines = vim.fn.readfile(active)
  socket = connect(tonumber(lines[1]), lines[2])
  local target
  wait(30000, function()
    for _, info in ipairs(socket.call("Target.getTargets").targetInfos) do
      if info.type == "page" and info.url:find(url, 1, true) then target = info end
    end
    return target ~= nil
  end, "browser did not load " .. url)
  local session = socket.call("Target.attachToTarget",
    { targetId = target.targetId, flatten = true }).sessionId
  local function page_text()
    local result = socket.call("Runtime.evaluate", { expression = "document.body.innerText",
      returnByValue = true }, session).result
    return result.value or ""
  end
  wait(30000, function() return page_text():find("first-revision", 1, true) ~= nil end,
    "browser page did not render the note: " .. page_text())
  print("PASS a real browser renders the preview page")

  vim.api.nvim_buf_set_lines(buffer, 2, 3, false, { "second-revision" })
  -- markdown-preview refreshes on cursor events, not on TextChanged.
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buffer })
  wait(30000, function() return page_text():find("second-revision", 1, true) ~= nil end,
    "the edit did not reach the browser page: " .. page_text())
  print("PASS a buffer edit reaches the browser page")

  local port = tonumber(url:match(":(%d+)/"))
  local function accepts()
    local probe, settled, connected = assert(vim.uv.new_tcp()), false, false
    probe:connect("127.0.0.1", port, function(failure)
      connected, settled = failure == nil, true
      probe:close()
    end)
    vim.wait(2000, function() return settled end, 20)
    if not settled then probe:close() end
    return connected
  end
  assert(accepts(), "the running preview server refused a connection on port " .. port)
  vim.cmd.MarkdownPreviewToggle()
  wait(30000, function() return vim.fn["mkdp#rpc#get_server_status"]() == -1 end,
    "MarkdownPreviewToggle did not stop the server")
  wait(30000, function() return not accepts() end,
    "the preview server still accepts connections after stop")
  print("PASS MarkdownPreviewToggle stops the preview server")
end, debug.traceback)

if socket then pcall(function() socket.tcp:close() end) end
if browser then pcall(function() browser:kill(9) end); pcall(function() browser:wait(10000) end) end
pcall(vim.fn["mkdp#util#stop_preview"])
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real Markdown preview integration tests passed.")
