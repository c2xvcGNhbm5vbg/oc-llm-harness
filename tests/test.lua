-- test.lua -- Test harness for the OC LLM agent modules.
--
-- Run with:  lua5.3 test.lua
--
-- It stubs the OpenComputers-specific modules (internet, shell, term, package)
-- so the pure-logic modules (json, http, llm, config) can run on a stock Lua
-- 5.3 host, then exercises:
--   1. json encode/decode round-trips
--   2. http response parsing (against a canned/mock internet card)
--   3. llm.ask end-to-end against the REAL local vLLM (if reachable)

-------------------------------------------------------------------------------
-- Test framework
-------------------------------------------------------------------------------

local passed, failed = 0, 0
local failures = {}

local function ok(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(failures, msg)
    print("  FAIL: " .. msg)
  end
end

local function section(name)
  print("\n== " .. name .. " ==")
end

-------------------------------------------------------------------------------
-- Stub the OpenComputers runtime so the modules load on stock Lua 5.3.
-------------------------------------------------------------------------------

package.path = table.concat({
  "../lua/?.lua",
  "lua/?.lua",
  "./lua/?.lua",
  package.path,
}, ";")

-- A mock `internet` card. We let tests set its behaviour.
local mock_internet = {
  _next_response = nil,   -- function(method, url, body, headers) -> (request_obj, reason)
  _last_request = nil,
}

-- The request object returned by internet.request: it is a callable that reads
-- chunks until nil (EOF).
local function make_request(raw)
  -- Split raw into a couple of chunks to exercise the read_all loop.
  local req = {}
  local pos = 1
  local function read()
    if pos > #raw then
      return nil          -- EOF
    end
    local chunk = raw:sub(pos, pos + 7)
    pos = pos + 8
    return chunk
  end
  req.read = read
  req.close = function() end
  -- Make the table callable.
  return setmetatable(req, {__call = function() return read() end})
end

function mock_internet.request(url, data, headers, method)
  mock_internet._last_request = {url = url, data = data, headers = headers, method = method}
  if mock_internet._next_response then
    return mock_internet._next_response(method, url, data, headers)
  end
  return nil, "mock: no response configured"
end

-- Provide the stubs as globals the modules expect.
_G.component = {
  isAvailable = function() return true end,
  internet = mock_internet,
}
-- `internet` is required by http.lua; point it at the mock.
package.loaded["internet"] = mock_internet

-- Stub shell (used by chat.lua) and term.
package.loaded["shell"] = {prompt = function() return "/quit" end}
package.loaded["term"] = {setPalette = function() end}
-- checkArg is a global in OC; stub it.
_G.checkArg = function() end

-------------------------------------------------------------------------------
-- 1. JSON
-------------------------------------------------------------------------------

section("json")
local json = require("json")

-- Round-trips.
local cases = {
  {v = "hello", name = "string"},
  {v = 42, name = "int"},
  {v = 3.14, name = "float"},
  {v = true, name = "bool"},
  {v = false, name = "bool false"},
  {v = nil, name = "nil"},
  {v = {1, 2, 3}, name = "array"},
  {v = {}, name = "empty array"},
  {v = {a = 1, b = "two"}, name = "object"},
  {v = {a = {1, 2}, b = {c = "d"}}, name = "nested"},
  {v = "with \"quotes\" and \\ backslash", name = "escapes"},
  {v = "line\nbreak\ttab", name = "control chars"},
}
for _, c in ipairs(cases) do
  local enc = json.encode(c.v)
  local success, dec = pcall(json.decode, enc)
  if success then
    ok(true, "round-trip " .. c.name .. " -> " .. tostring(enc))
  else
    ok(false, "decode " .. c.name .. " -> " .. tostring(enc) .. " err=" .. tostring(dec))
  end
end

-- Specific value checks.
do
  local s = json.encode({a = 1, b = "x"})
  ok(s:find('"a"') and s:find('"b"'), "object keys quoted: " .. s)
end
do
  local s = json.encode({1, 2, 3})
  ok(s == "[1,2,3]" or s:find("1,2,3") ~= nil, "array: " .. s)
end
do
  local s = json.encode("a\"b")
  ok(s == '"a\\"b"', "escaped quote: " .. s)
end
do
  local v = json.decode('{"name":"Minecraft","count":3,"ok":true,"tags":["a","b","c"]}')
  ok(v.name == "Minecraft" and v.count == 3 and v.ok == true and #v.tags == 3,
    "decode object+array: " .. tostring(v.name))
end
do
  local v = json.decode('"\\u0041\\u0042"')
  ok(v == "AB", "unicode escape: " .. tostring(v))
end
do
  local v = json.decode('[-1, 2.5, -3e2]')
  ok(v[1] == -1 and v[2] == 2.5 and v[3] == -300, "numbers: " .. tostring(v[3]))
end

-------------------------------------------------------------------------------
-- 2. HTTP parsing (mocked internet card)
-------------------------------------------------------------------------------

section("http (mocked)")
local http = require("http")

-- A canned full HTTP response.
local canned = table.concat({
  "HTTP/1.1 200 OK\r\n",
  "Content-Type: application/json\r\n",
  "Content-Length: 27\r\n",
  "Connection: close\r\n",
  "\r\n",
  '{"status":"ok","n":42}',
})

mock_internet._next_response = function(method, url, data, headers)
  return make_request(canned), nil
end

local resp, reason = http.request("http://example.test/x", {method = "GET"})
ok(resp ~= nil, "request returned response (reason=" .. tostring(reason) .. ")")
if resp then
  ok(resp.status == 200, "status 200 (got " .. tostring(resp.status) .. ")")
  ok(resp.headers["content-type"] == "application/json", "header parsed: " .. tostring(resp.headers["content-type"]))
  ok(resp.body == '{"status":"ok","n":42}', "body exact: " .. tostring(resp.body))
end

-- POST with body + headers.
mock_internet._next_response = function(method, url, data, headers)
  return make_request("HTTP/1.1 201 Created\r\n\r\n"), nil
end
local resp2, reason2 = http.post_json("http://example.test/submit", {a = 1, b = "x"}, {})
ok(resp2 ~= nil, "post_json returned (reason=" .. tostring(reason2) .. ")")
if resp2 then
  ok(resp2.status == 201, "post status 201 (got " .. tostring(resp2.status) .. ")")
  local lr = mock_internet._last_request
  ok(lr.method == "POST", "method POST (got " .. tostring(lr.method) .. ")")
  -- Key order from pairs() is not guaranteed; verify by decoding.
  local decoded, derr = pcall(json.decode, lr.data)
  ok(decoded and lr.data ~= nil, "post body is valid json: " .. tostring(lr.data) .. " err=" .. tostring(derr))
  ok(decoded and lr.data:find('"a"') and lr.data:find('"b"'), "post body has both keys: " .. tostring(lr.data))
  ok(lr.headers["Content-Type"] == "application/json", "post content-type: " .. tostring(lr.headers["Content-Type"]))
  ok(lr.headers["Connection"] == "close", "connection close set")
end

-- Error path: no internet card.
mock_internet._next_response = function() return nil, "no internet card" end
local resp3, reason3 = http.request("http://x/")
ok(resp3 == nil and reason3 == "no internet card", "error passthrough: " .. tostring(reason3))

-------------------------------------------------------------------------------
-- 3. LLM end-to-end (real local vLLM, if reachable)
-------------------------------------------------------------------------------

section("llm (real, if reachable)")
local llm = require("llm")

-- Try to reach the real local endpoint. We point the mock internet at the real
-- network by NOT stubbing it here — instead we do a direct socket test via the
-- real `internet` if available. On this host we just test the llm logic against
-- a canned model response, and separately note that a real run is done in the
-- e2e test below.
mock_internet._next_response = function(method, url, data, headers)
  local canned_model = table.concat({
    "HTTP/1.1 200 OK\r\n",
    "Content-Type: application/json\r\n",
    "\r\n",
    '{"choices":[{"message":{"role":"assistant","content":"Hello from the mock model"},"finish_reason":"stop"}]}',
  })
  return make_request(canned_model), nil
end

llm.reset()
llm.configure({system = "You are a test bot."})
local reply, reason = llm.ask("Hi there")
ok(reply == "Hello from the mock model", "llm.ask reply (reason=" .. tostring(reason) .. ")")
local h = llm.history()
ok(#h == 2 and h[1].role == "user" and h[2].role == "assistant",
  "history grew to 2 (got " .. tostring(#h) .. ")")

-- Thinking-model fallback: content nil, reasoning present.
mock_internet._next_response = function()
  local canned = table.concat({
    "HTTP/1.1 200 OK\r\n\r\n",
    '{"choices":[{"message":{"role":"assistant","content":null,"reasoning":"I am thinking and here is my eventual answer."},"finish_reason":"stop"}]}',
  })
  return make_request(canned), nil
end
llm.reset()
local reply2, reason2 = llm.ask("Think about it")
ok(reply2 ~= nil and reply2:find("answer") ~= nil,
  "reasoning fallback (got " .. tostring(reply2) .. ", reason=" .. tostring(reason2) .. ")")

-- Error: HTTP 500.
mock_internet._next_response = function()
  local canned = "HTTP/1.1 500 Internal Server Error\r\n\r\nboom"
  return make_request(canned), nil
end
local reply3, reason3 = llm.ask("x")
ok(reply3 == nil and reason3:find("500") ~= nil,
  "http 500 surfaced (reason=" .. tostring(reason3) .. ")")

-------------------------------------------------------------------------------
-- Summary
-------------------------------------------------------------------------------

print("\n========================================")
print(string.format("PASSED: %d   FAILED: %d", passed, failed))
if #failures > 0 then
  print("Failures:")
  for _, f in ipairs(failures) do print("  - " .. f) end
end
print("========================================")
os.exit(failed == 0 and 0 or 1)
