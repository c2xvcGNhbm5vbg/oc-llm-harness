-- json.lua -- A small, dependency-free JSON encoder/decoder for OpenComputers Lua.
--
-- Written for the OpenComputers (OC) Lua 5.2 runtime (LuaJ). It intentionally
-- avoids the `utf8` library so it also works on plain Lua 5.2/5.3 hosts used for
-- testing. It handles strings (with \uXXXX escapes and UTF-8), numbers,
-- booleans, nil, and nested tables (arrays and objects).
--
-- API:
--   json.encode(value)            -> string   (raises on circular refs)
--   json.decode(str)             -> value    (raises on malformed input)
--   json.encode_pretty(value)    -> string   (indented, for debugging)

local json = {}

-------------------------------------------------------------------------------
-- Encoding
-------------------------------------------------------------------------------

local function encode_number(n)
  if n ~= n then return "null" end                 -- NaN
  if n == math.huge or n == -math.huge then
    return "null"                                 -- Infinity (not valid JSON)
  end
  -- Whole numbers print without a fractional part.
  if n == math.floor(n) and math.abs(n) < 1e15 then
    return string.format("%d", n)
  end
  return string.format("%.17g", n)
end

local function encode_string(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\"", "\\\"")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  -- Remaining control characters (0x00-0x1F) become \u00XX.
  s = s:gsub("[%c]", function(c)
    return string.format("\\u%04x", c:byte())
  end)
  return "\"" .. s .. "\""
end

local function encode_value(v, pretty, depth, visited)
  local t = type(v)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "number" then
    return encode_number(v)
  elseif t == "string" then
    return encode_string(v)
  elseif t == "table" then
    if visited[v] then
      error("json.encode: circular reference detected", 0)
    end
    visited[v] = true

    local is_array = true
    local n = 0
    for k in pairs(v) do
      if type(k) ~= "number" then is_array = false break end
      n = n + 1
    end
    -- A table is an array only if its keys are 1..n.
    for i = 1, n do
      if v[i] == nil then is_array = false break end
    end

    local indent = pretty and string.rep("  ", depth) or ""
    local inner_indent = pretty and string.rep("  ", depth + 1) or ""
    local parts

    if is_array then
      parts = {}
      for i = 1, n do
        parts[i] = (pretty and inner_indent or "") ..
          encode_value(v[i], pretty, depth + 1, visited)
      end
      if #parts == 0 then
        visited[v] = nil
        return "[]"
      end
      local sep = pretty and ",\n" or ","
      local open, close = (pretty and "[\n" or "["), (pretty and ("\n" .. indent .. "]") or "]")
      visited[v] = nil
      return open .. table.concat(parts, sep) .. close
    else
      parts = {}
      for k, val in pairs(v) do
        if val ~= nil then
          table.insert(parts, (pretty and inner_indent or "") ..
            encode_string(tostring(k)) ..
            (pretty and ": " or ":") .. encode_value(val, pretty, depth + 1, visited))
        end
      end
      if #parts == 0 then
        visited[v] = nil
        return "{}"
      end
      local sep = pretty and ",\n" or ","
      local open, close = (pretty and "{\n" or "{"), (pretty and ("\n" .. indent .. "}") or "}")
      visited[v] = nil
      return open .. table.concat(parts, sep) .. close
    end
  end
  error("json.encode: unsupported type: " .. t, 0)
end

function json.encode(value)
  return encode_value(value, false, 0, {})
end

function json.encode_pretty(value)
  return encode_value(value, true, 0, {})
end

-------------------------------------------------------------------------------
-- Decoding
-------------------------------------------------------------------------------

-- Convert a Unicode code point to a UTF-8 byte sequence (no utf8 dependency).
local function codepoint_to_utf8(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x10000),
      0x80 + (math.floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40))
  else
    return string.char(0xF0 + math.floor(cp / 0x100000),
      0x80 + (math.floor(cp / 0x10000) % 0x40),
      0x80 + (math.floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40))
  end
end

local function decode(str)
  local pos = 1
  local len = #str

  local function fail(msg)
    error(string.format("json.decode: %s at byte %d", msg, pos), 0)
  end

  local function skip_ws()
    while pos <= len do
      local c = str:sub(pos, pos)
      if c == " " or c == "\t" or c == "\n" or c == "\r" then
        pos = pos + 1
      else
        break
      end
    end
  end

  local function decode_string()
    -- pos is at the opening quote.
    pos = pos + 1
    local buf = {}
    while true do
      local c = str:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == "\"" then
        pos = pos + 1
        return table.concat(buf)
      end
      if c == "\\" then
        local e = str:sub(pos + 1, pos + 1)
        if e == "n" then table.insert(buf, "\n"); pos = pos + 2
        elseif e == "t" then table.insert(buf, "\t"); pos = pos + 2
        elseif e == "r" then table.insert(buf, "\r"); pos = pos + 2
        elseif e == "\"" then table.insert(buf, "\""); pos = pos + 2
        elseif e == "\\" then table.insert(buf, "\\"); pos = pos + 2
        elseif e == "/" then table.insert(buf, "/"); pos = pos + 2
        elseif e == "b" then table.insert(buf, "\b"); pos = pos + 2
        elseif e == "f" then table.insert(buf, "\f"); pos = pos + 2
        elseif e == "u" then
          local hex = str:sub(pos + 2, pos + 5)
          local code = tonumber(hex, 16)
          if not code then fail("bad \\u escape") end
          -- Surrogate pair: \uDBXX\uDCXX
          if code >= 0xD800 and code <= 0xDBFF then
            local hex2 = str:sub(pos + 7, pos + 10)
            local code2 = tonumber(hex2, 16)
            if code2 and code2 >= 0xDC00 and code2 <= 0xDFFF then
              code = 0x10000 + (code - 0xD800) * 0x400 + (code2 - 0xDC00)
              pos = pos + 6
            else
              pos = pos + 6
            end
          else
            pos = pos + 6
          end
          -- Lone surrogates are invalid; substitute the replacement character.
          if code >= 0xD800 and code <= 0xDFFF then
            code = 0xFFFD
          end
          table.insert(buf, codepoint_to_utf8(code))
        else
          fail("bad escape: \\" .. e)
        end
      else
        table.insert(buf, c)
        pos = pos + 1
      end
    end
  end

  local function decode_number()
    -- Match a number starting at `pos`. (No `^` anchor: with a pos offset,
    -- `^` would mean the start of the whole string, not `pos`.) No capture
    -- groups are used, because string.match returns nil when all captures are
    -- nil (which would happen for a plain integer like "42").
    local s = str:match("[%-%+]?%d+%.?%d*[eE]?[%-%+]?%d*", pos)
    if not s or s == "" then fail("invalid number") end
    pos = pos + #s
    return tonumber(s)
  end

  local function decode_value()
    skip_ws()
    local c = str:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local obj = {}
      skip_ws()
      if str:sub(pos, pos) == "}" then
        pos = pos + 1
        return obj
      end
      while true do
        skip_ws()
        if str:sub(pos, pos) ~= "\"" then fail("expected object key string") end
        local key = decode_string()
        skip_ws()
        if str:sub(pos, pos) ~= ":" then fail("expected ':' in object") end
        pos = pos + 1
        obj[key] = decode_value()
        skip_ws()
        local d = str:sub(pos, pos)
        if d == "," then
          pos = pos + 1
        elseif d == "}" then
          pos = pos + 1
          return obj
        else
          fail("expected ',' or '}' in object")
        end
      end
    elseif c == "[" then
      pos = pos + 1
      local arr = {}
      skip_ws()
      if str:sub(pos, pos) == "]" then
        pos = pos + 1
        return arr
      end
      while true do
        table.insert(arr, decode_value())
        skip_ws()
        local d = str:sub(pos, pos)
        if d == "," then
          pos = pos + 1
        elseif d == "]" then
          pos = pos + 1
          return arr
        else
          fail("expected ',' or ']' in array")
        end
      end
    elseif c == "\"" then
      return decode_string()
    elseif c == "t" then
      if str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
      else fail("invalid literal") end
    elseif c == "f" then
      if str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
      else fail("invalid literal") end
    elseif c == "n" then
      if str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
      else fail("invalid literal") end
    else
      return decode_number()
    end
  end

  local value = decode_value()
  skip_ws()
  if pos <= len then
    fail("trailing characters after JSON value")
  end
  return value
end

function json.decode(str)
  if type(str) ~= "string" then
    error("json.decode: expected a string", 2)
  end
  return decode(str)
end

return json
