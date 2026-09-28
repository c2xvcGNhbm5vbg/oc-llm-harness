-- config.lua -- Load the harness configuration from a file on the computer's disk.
--
-- Reads /etc/oc-llm.conf (a simple key = value format) and returns a table.
-- Missing file -> empty table (callers fall back to defaults).
--
-- Recognised keys:
--   base_url, model, max_tokens, temperature, system, timeout

local config = {}

local CONFPATH = "/etc/oc-llm.conf"

local function parse_line(line)
  -- "key = value" (whitespace trimmed).
  local key, value = line:match("^%s*(%S+)%s*=%s*(.-)%s*$")
  if key then
    -- Strip surrounding quotes if present.
    value = value:gsub('^"(.*)"$', "%1")
    -- Numeric coercion.
    local num = tonumber(value)
    if num then value = num end
    return key, value
  end
  return nil
end

function config.load(path)
  path = path or CONFPATH
  local out = {}
  local file = io.open(path, "r")
  if not file then
    return out
  end
  for line in file:lines() do
    if not line:match("^%s*#") then  -- skip comments
      local key, value = parse_line(line)
      if key then out[key] = value end
    end
  end
  file:close()
  return out
end

return config
