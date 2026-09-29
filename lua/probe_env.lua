-- probe_env.lua -- In-game diagnostic for the OC LLM harness.
--
-- Run it on the computer:
--     wget -f <raw_base>/lua/probe_env.lua /home/probe_env.lua
--     lua /home/probe_env.lua
--
-- It reports, to the terminal, the exact state the agent sees: which llm.lua
-- require() actually resolves to, whether that copy has raw_ask/raw_step, and
-- the size of every llm.lua/agent.lua on disk. Paste/screenshot the output.

local lines = {}
local function say(s) lines[#lines + 1] = s end

say("=== OC LLM harness env probe ===")

-- 1. How require() resolves modules.
say("package.path = " .. tostring(package.path))

-- 2. Walk the search path and list every llm.lua / agent.lua it would find,
--    in RESOLUTION ORDER, with sizes. The FIRST match is what require loads.
local function size(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local n = #f:read("*a")
  f:close()
  return n
end
local templates = {}
for t in (package.path):gmatch("[^;]+") do templates[#templates + 1] = t end
for _, name in ipairs({ "llm", "agent" }) do
  local found = false
  for _, t in ipairs(templates) do
    local p = t:gsub("?", name)
    local n = size(p)
    if n then
      say(string.format("  %-8s -> %s  (%d bytes)", name, p, n))
      found = true
      break
    end
  end
  if not found then say(string.format("  %-8s -> NOT FOUND on package.path", name)) end
end

-- 3. Also list the two canonical locations explicitly (they may differ from
--    what package.path resolves, e.g. a stray /home/llm.lua).
for _, p in ipairs({ "/lib/llm.lua", "/home/llm.lua", "/lib/agent.lua", "/home/agent.lua" }) do
  local n = size(p)
  say(string.format("  on disk  %s  =  %s", p, n and (n .. " bytes") or "absent"))
end

-- 4. What require() actually gives us.
local ok, llm = pcall(require, "llm")
if ok then
  local extra = ""
  if llm.VERSION then extra = " VERSION=" .. tostring(llm.VERSION) end
  say("require('llm') ok; raw_ask=" .. type(llm.raw_ask)
     .. " raw_step=" .. type(llm.raw_step) .. extra)
else
  say("require('llm') FAILED: " .. tostring(llm))
end
local ok2, agent = pcall(require, "agent")
if ok2 then
  say("require('agent') ok")
else
  say("require('agent') FAILED: " .. tostring(agent))
end

say("=== end probe ===")
local report = table.concat(lines, "\n")
print(report)
-- Also write to disk so it can be read back cleanly (the terminal grid can
-- mangle long output).
local f = io.open("/home/probe_env_report.txt", "w")
if f then f:write(report .. "\n") f:close() end
