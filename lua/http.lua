-- http.lua -- A minimal HTTP/1.1 client built on the OpenComputers internet card.
--
-- The internet card's `internet.request` returns a stream object you call to read
-- chunks until nil (EOF). This module wraps that into a simple
-- `request(url, {method=, headers=, body=, timeout=})` that returns
-- `{status, headers, body}` and a `post_json` helper.
--
-- It sends `Connection: close` so the server does not keep the socket open, and
-- it buffers the full response before splitting headers from the body, so it is
-- robust to the stream being delivered in arbitrary-sized chunks.

local internet = require("internet")
local json = require("json")

local http = {}

-------------------------------------------------------------------------------

-- Read the whole response stream into a single string.
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

-- Split a raw HTTP response into (status, headers-table, body).
local function parse_response(raw)
  -- Headers end at the first blank line: "\r\n\r\n" or "\n\n".
  local sep_len
  local sep_pos = raw:find("\r\n\r\n", 1, true)
  if sep_pos then
    sep_len = 4
  else
    sep_pos = raw:find("\n\n", 1, true)
    if not sep_pos then
      return nil, "no header/body separator found in response"
    end
    sep_len = 2
  end
  local head = raw:sub(1, sep_pos - 1)
  local body = raw:sub(sep_pos + sep_len)

  local lines = {}
  for line in head:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  if #lines == 0 then
    return nil, "empty status line"
  end

  local status = lines[1]:match("HTTP/%d+%.%d+ (%d+)")
  if not status then
    return nil, "unrecognized status line: " .. lines[1]
  end

  local headers = {}
  for i = 2, #lines do
    local key, value = lines[i]:match("^(%S+):%s*(.*)$")
    if key then
      headers[key:lower()] = value
    end
  end

  return {status = tonumber(status), headers = headers, body = body}
end

-------------------------------------------------------------------------------

-- Perform an HTTP request.
--   url:     full URL, e.g. "http://127.0.0.1:8080/v1/chat/completions"
--   opts: {
--     method  = "GET" | "POST" | ...,
--     headers = { ["Content-Type"] = "application/json", ... },
--     body    = "raw request body string",
--     timeout = seconds (default 0 = no timeout),
--   }
-- Returns {status, headers, body} or nil, reason.
function http.request(url, opts)
  opts = opts or {}
  local method = (opts.method or "GET"):upper()
  local headers = opts.headers or {}

  -- Always close the connection so we don't have to manage keep-alive.
  headers["Connection"] = "close"

  if opts.timeout and opts.timeout > 0 then
    headers["X-Timeout"] = tostring(opts.timeout) -- informational; OC timeout is server-side
  end

  local request, reason = internet.request(url, opts.body, headers, method)
  if not request then
    return nil, reason
  end

  local raw, reason2 = read_all(request)
  if not raw then
    return nil, reason2
  end

  local parsed, reason3 = parse_response(raw)
  if not parsed then
    return nil, reason3
  end
  return parsed
end

-------------------------------------------------------------------------------

-- POST a Lua table as a JSON body.
--   url, payload-table, opts (headers/timeout merged in)
function http.post_json(url, payload, opts)
  opts = opts or {}
  opts.method = "POST"
  opts.body = json.encode(payload)
  local headers = opts.headers and {} or {}
  for k, v in pairs(opts.headers or {}) do headers[k] = v end
  headers["Content-Type"] = "application/json"
  opts.headers = headers
  return http.request(url, opts)
end

-------------------------------------------------------------------------------

return http
