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
--
-- The card's read() returns an EMPTY chunk (not nil) while the response is
-- still in flight, and only sets the status/headers once the stream is ready.
-- So an empty chunk means "not ready yet" — we must yield (os.sleep) and
-- re-read, exactly like the OC internet.lua wrapper. A nil return is the true
-- EOF. This is what makes slow responses work: we keep reading (and yielding)
-- until the full body has arrived, by which point the status is set.
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
    if #chunk == 0 then
      -- No data yet (response in flight) — yield and re-read.
      if os.sleep then os.sleep(0) end
    else
      table.insert(chunks, chunk)
    end
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

  -- Best-effort: surface a hard connection error if the card reports one.
  -- (The card's finishConnect may return false while the response is still
  --  in flight; that is NOT an error, so we don't fail on a false return.)
  pcall(request.finishConnect)

  -- Read the body FIRST. This is the operation that blocks until the full
  -- response has arrived, so by the time it returns the card has also set the
  -- status/headers. (Reading the body before the status is what makes slow
  -- responses work — a short reply's status is ready immediately, but a long
  -- one's status is only set once the body is fully received.)
  local body, reason3 = read_all(request)
  if not body then
    pcall(request.close)
    return nil, reason3
  end

  -- Now the status + headers are available. Poll a generous number of times
  -- (yielding between attempts) in case the card sets them a tick later.
  local status, _message, rawheaders
  for _ = 1, 500 do
    status, _message, rawheaders = request.response()
    if status then break end
    if os.sleep then os.sleep(0) end
  end

  pcall(request.close)

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
