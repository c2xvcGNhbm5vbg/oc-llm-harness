-- http.lua -- A minimal HTTP/1.1 client built on the OpenComputers internet card.
--
-- IMPORTANT: the internet card's `read()` (the stream you call) returns the
-- response BODY ONLY. The status code and headers are NOT in that stream —
-- they come from the request object's separate `response()` method:
--
--     local req = internet.request(url, body, headers, method)
--     req.finishConnect()                 -- block until the response is ready
--     local status, message, headers = req.response()
--     for chunk in req do ... end        -- read the body
--
-- This module wraps that into a simple `request(url, opts)` returning
-- `{status, headers, body}` and a `post_json` helper. It sends
-- `Connection: close` so the server does not keep the socket open.

local internet = require("internet")
local json = require("json")

local http = {}

-------------------------------------------------------------------------------

-- Read the whole response stream (body only) into a single string.
local function read_all(request)
  local chunks = {}
  while true do
    local chunk, reason = request()
    if not chunk then
      if reason then
        return nil, reason
      end
      return table.concat(chunks)
    end
    table.insert(chunks, chunk)
  end
end

-- The card returns headers as { [Name] = {v1, v2, ...} }. Normalise to
-- { [name] = v1 } with lower-cased keys.
local function normalize_headers(h)
  local out = {}
  if type(h) == "table" then
    for k, v in pairs(h) do
      if type(k) == "string" then
        if type(v) == "table" then
          out[k:lower()] = v[1]
        else
          out[k:lower()] = v
        end
      end
    end
  end
  return out
end

-------------------------------------------------------------------------------

-- Perform an HTTP request.
--   url:     full URL, e.g. "http://127.0.0.1:8080/v1/chat/completions"
--   opts: {
--     method  = "GET" | "POST" | ...,
--     headers = { ["Content-Type"] = "application/json", ... },
--     body    = "raw request body string",
--     timeout = seconds (informational; the card's own timeout is server-side),
--   }
-- Returns {status, headers, body} or nil, reason.
function http.request(url, opts)
  opts = opts or {}
  local method = (opts.method or "GET"):upper()
  local headers = opts.headers or {}

  -- Always close the connection so we don't have to manage keep-alive.
  headers["Connection"] = "close"

  local request, reason = internet.request(url, opts.body, headers, method)
  if not request then
    return nil, reason
  end

  -- Ensure the response is available (blocks; errors if the connection failed).
  local ok, reason2 = pcall(request.finishConnect)
  if not ok then
    pcall(request.close)
    return nil, reason2
  end

  -- Status code + headers come from the card, not from the body stream.
  local status, _message, rawheaders
  for _ = 1, 100 do
    status, _message, rawheaders = request.response()
    if status then break end
    if os.sleep then os.sleep(0) end
  end

  -- Read the body (the stream yields body bytes only, no headers).
  local body, reason3 = read_all(request)
  pcall(request.close)
  if not body then
    return nil, reason3
  end

  return {
    status = status or 0,
    headers = normalize_headers(rawheaders),
    body = body,
  }
end

-------------------------------------------------------------------------------

-- POST a Lua table as a JSON body.
--   url, payload-table, opts (headers/timeout merged in)
function http.post_json(url, payload, opts)
  opts = opts or {}
  opts.method = "POST"
  opts.body = json.encode(payload)
  local headers = {}
  for k, v in pairs(opts.headers or {}) do headers[k] = v end
  headers["Content-Type"] = "application/json"
  opts.headers = headers
  return http.request(url, opts)
end

-------------------------------------------------------------------------------

return http
