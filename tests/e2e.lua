-- e2e.lua -- Real end-to-end test: llm.ask() -> http -> REAL TCP socket -> local vLLM.
--
-- Run with:  lua5.3 e2e.lua
--
-- Unlike test.lua (which mocks the internet card), this wires the
-- `internet.request` stub to a real TCP socket (via luasocket), so the ENTIRE
-- path is exercised: JSON encode -> HTTP request build -> network -> HTTP parse
-- -> JSON decode -> reply. It hits the actual local vLLM on 127.0.0.1:8080.

package.path = table.concat({
  "../lua/?.lua",
  "lua/?.lua",
  package.path,
}, ";")

local socket = require("socket")

-------------------------------------------------------------------------------
-- A real-socket implementation of the OC internet card's request().
--
-- The OC internet card returns a callable stream: call it to read the next
-- chunk, get nil at EOF. We emulate that over a real TCP connection.
-------------------------------------------------------------------------------

local function build_request(method, url, body, headers)
  -- Parse host:port from the URL.
  local host, port = url:match("^https?://([^/:]+):(%d+)")
  if not host then
    host, port = url:match("^https?://([^/:]+)")
    port = nil
  end
  if not host then
    return nil, "cannot parse url: " .. url
  end
  port = port and tonumber(port) or 80

  local conn, reason = socket.connect(host, port)
  if not conn then
    return nil, "connect failed: " .. reason
  end

  -- Build the request line + headers.
  local path = url:match("^https?://[^/]*(/.*)$") or "/"
  local lines = { method .. " " .. path .. " HTTP/1.1" }
  local host_header = host .. (port and (":" .. port) or "")
  lines[#lines + 1] = "Host: " .. host_header
  lines[#lines + 1] = "Connection: close"
  for k, v in pairs(headers) do
    lines[#lines + 1] = k .. ": " .. v
  end
  lines[#lines + 1] = "Content-Length: " .. tostring(#(body or ""))
  lines[#lines + 1] = ""
  lines[#lines + 1] = ""
  local req = table.concat(lines, "\r\n") .. (body or "")

  local ok, reason2 = conn:send(req)
  if not ok then
    conn:close()
    return nil, "send failed: " .. reason2
  end

  -- Read the whole response. With Connection: close, receive("*a") blocks until
  -- the server closes the socket and returns everything that was sent.
  local raw, err = conn:receive("*a")
  conn:close()
  if not raw then
    return nil, "read failed: " .. tostring(err)
  end

  -- Parse the raw HTTP response into status / headers / body (the card delivers
  -- status+headers via response() and the body via the stream).
  local sep_pos = raw:find("\r\n\r\n", 1, true)
  local sep_len = 4
  if not sep_pos then
    sep_pos = raw:find("\n\n", 1, true)
    sep_len = 2
  end
  local head = raw:sub(1, sep_pos - 1)
  local body = raw:sub(sep_pos + sep_len)
  local status = head:match("^HTTP/%d+%.%d+ (%d+)")
  local headers = {}
  for line in head:gmatch("[^\r\n]+") do
    local k, v = line:match("^(%S+):%s*(.*)$")
    if k then headers[k:lower()] = v end
  end

  -- Wrap as an OC-style request (real card API: finishConnect + response + stream).
  local pos = 1
  local request = {}
  function request.finishConnect() end
  function request.response() return tonumber(status), "OK", headers end
  function request.read()
    if pos > #body then
      return nil
    end
    local chunk = body:sub(pos, pos + 9)
    pos = pos + 10
    return chunk
  end
  function request.close() end
  return setmetatable(request, {__call = function() return request.read() end})
end

-- The OC internet card API surface.
local internet = {
  request = function(url, data, headers, method)
    return build_request(method, url, data, headers)
  end,
}

-- Provide the stubs the modules expect.
_G.component = {isAvailable = function() return true end, internet = internet}
package.loaded["internet"] = internet
package.loaded["shell"] = {prompt = function() return "/quit" end}
package.loaded["term"] = {setPalette = function() end}
_G.checkArg = function() end

-------------------------------------------------------------------------------
-- The test
-------------------------------------------------------------------------------

local llm = require("llm")

local base = os.getenv("LLM_BASE_URL") or "http://127.0.0.1:8080"
local model = os.getenv("LLM_MODEL") or "qwen3.8-27b-vllm"

print("=== E2E test: " .. base .. " model=" .. model .. " ===")

llm.configure({
  base_url = base,
  model = model,
  max_tokens = 600,
  temperature = 0,
  system = "You are a helpful assistant. Keep answers to one short sentence.",
  timeout = 120,
})

local t0 = os.clock()
local reply, reason = llm.ask("What is 2 plus 2? Answer with just the number.")
local dt = os.clock() - t0

print(string.format("\n[elapsed %.1fs]", dt))
if reply then
  print("REPLY: " .. reply)
else
  print("FAILED: " .. reason)
end

-- A second turn to exercise history.
local reply2, reason2 = llm.ask("Now subtract 1 from that number. Just the number.")
print("REPLY2: " .. tostring(reply2) .. (reason2 and (" (err: " .. reason2 .. ")") or ""))

local success = (reply ~= nil)
print("\n" .. (success and "E2E: PASS" or "E2E: FAIL"))
os.exit(success and 0 or 1)
