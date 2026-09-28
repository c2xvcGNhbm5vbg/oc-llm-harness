-- debug.lua -- In-game debug/test suite for the OC LLM harness.
--
-- Run:
--     lua /home/debug.lua          full suite
--     lua /home/debug.lua quick   card probe + connectivity + one small chat
--
-- Uses the REAL internet card and the REAL LLM server from /etc/oc-llm.conf,
-- so it exercises the exact path chat.lua uses (JSON encode -> card -> parse
-- -> JSON decode -> reply), including a slow generation (the kind that broke
-- before). EVERY run writes a debug log to /home/oc-llm-debug.log (status,
-- headers, body, timing) — if something fails, `cat /home/oc-llm-debug.log`
-- and paste it back for analysis.

local component = require("component")
local config = require("config")
local llm = require("llm")
local http = require("http")

local cfg = config.load()
local base_url = cfg.base_url
local model = cfg.model

local LOG = "/home/oc-llm-debug.log"
local loglines = {}
local function log(s)
  if s == nil then s = "" end
  table.insert(loglines, s)
  print(s)
end

local function truncate(s, n)
  s = tostring(s)
  if #s <= n then return s end
  return s:sub(1, n - 3) .. "..."
end

local results = {}
local function record(name, ok, detail)
  table.insert(results, {name = name, ok = ok, detail = detail})
  if ok then
    log("  PASS  " .. name)
  else
    log("  FAIL  " .. name .. "  (" .. tostring(detail) .. ")")
  end
  return ok
end

-------------------------------------------------------------------------------
-- 1) Card probe: low-level, exercises the internet card API directly.
--    This is the layer where the "empty chunk while in flight" bug lived, so
--    it reports exactly how many empty vs data chunks the card returned.
-------------------------------------------------------------------------------

local function test_card_probe()
  local request, reason = component.internet.request(
    base_url .. "/v1/models", nil, {["Connection"] = "close"}, "GET")
  if not request then
    return record("card probe: request()", false, reason)
  end

  local okfc, fcval = pcall(request.finishConnect)
  local status, _message, _headers = request.response()

  local empty, data, total = 0, 0, 0
  while true do
    local chunk, r = request.read()
    if not chunk then
      if r then
        return record("card probe: read loop", false, "read error: " .. r)
      end
      break
    end
    total = total + 1
    if #chunk == 0 then empty = empty + 1 else data = data + 1 end
  end
  pcall(request.close)

  log(string.format("        card probe: finishConnect=%s status=%s chunks=%d (empty=%d data=%d)",
    tostring(fcval), tostring(status), total, empty, data))

  if not okfc then
    return record("card probe: finishConnect", false, "threw: " .. tostring(fcval))
  end
  return record("card probe: read loop", status ~= nil, "status=" .. tostring(status))
end

-------------------------------------------------------------------------------
-- 2) Connectivity through the http module.
-------------------------------------------------------------------------------

local function test_connectivity()
  local t0 = os.clock()
  local resp, reason = http.request(base_url .. "/v1/models", {method = "GET"})
  local dt = os.clock() - t0
  if not resp then
    return record("connectivity: /v1/models", false, reason)
  end
  log(string.format("        connectivity: HTTP %d in %.1fs", resp.status, dt))
  return record("connectivity: /v1/models", resp.status == 200, "status=" .. resp.status)
end

-------------------------------------------------------------------------------
-- 3) Small chat (fast response).
-------------------------------------------------------------------------------

local function test_small_chat()
  llm.reset()
  llm.configure({base_url = base_url, model = model, max_tokens = 1024,
    temperature = 0, system = "Reply with exactly one word."})
  local t0 = os.clock()
  local reply, reason = llm.ask("Reply with exactly: OK")
  local dt = os.clock() - t0
  if not reply then
    log("        small chat failure: " .. tostring(reason))
    return record("small chat", false, reason)
  end
  log(string.format("        small chat: '%s' in %.1fs", truncate(reply, 60), dt))
  return record("small chat", true, "reply=" .. truncate(reply, 40))
end

-------------------------------------------------------------------------------
-- 4) Slow generation (the haiku that broke before).
-------------------------------------------------------------------------------

local function test_slow_gen()
  llm.reset()
  llm.configure({base_url = base_url, model = model, max_tokens = 1024,
    temperature = 0.3, system = "You write haiku."})
  local t0 = os.clock()
  local reply, reason = llm.ask("Write a haiku about Minecraft.")
  local dt = os.clock() - t0
  if not reply then
    log("        slow gen failure: " .. tostring(reason))
    return record("slow generation (haiku)", false, reason)
  end
  log(string.format("        slow gen: '%s' in %.1fs", truncate(reply, 60), dt))
  return record("slow generation (haiku)", true, string.format("took %.1fs", dt))
end

-------------------------------------------------------------------------------
-- 5) Multi-turn history.
-------------------------------------------------------------------------------

local function test_multi_turn()
  llm.reset()
  llm.configure({base_url = base_url, model = model, max_tokens = 1024,
    temperature = 0, system = "Answer with just a number."})
  local r1, e1 = llm.ask("What is 2 plus 2? Just the number.")
  if not r1 then
    return record("multi-turn: turn 1", false, e1)
  end
  local r2, e2 = llm.ask("Now subtract 1 from that. Just the number.")
  if not r2 then
    return record("multi-turn: turn 2", false, e2)
  end
  log(string.format("        multi-turn: '%s' then '%s'", truncate(r1, 20), truncate(r2, 20)))
  return record("multi-turn", true, "two turns ok")
end

-------------------------------------------------------------------------------
-- Run
-------------------------------------------------------------------------------

local mode = select(1, ...)

log("=== OC LLM debug suite ===")
log("base_url = " .. tostring(base_url))
log("model    = " .. tostring(model))
log()

test_card_probe()
test_connectivity()
test_small_chat()
if mode ~= "quick" then
  test_slow_gen()
  test_multi_turn()
end

local pass, fail = 0, 0
for _, r in ipairs(results) do
  if r.ok then pass = pass + 1 else fail = fail + 1 end
end
log()
log(string.format("=== %d passed, %d failed ===", pass, fail))

-- Always write the log (useful even on success — it has the timing data).
local f = io.open(LOG, "w")
if f then
  f:write(table.concat(loglines, "\n") .. "\n")
  f:close()
  print("(debug log written to " .. LOG .. " — cat it and paste back if needed)")
end

os.exit(fail == 0)
