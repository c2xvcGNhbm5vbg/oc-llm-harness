-- probe.lua -- Diagnostic: how does OC's `lua` command pass command-line args?
--
-- Run:  lua /home/probe.lua TESTARG
--
-- It reports which mechanism carries the argument: the `arg` table, or the
-- vararg `...`. This tells us exactly how install.lua should read its URL.

print("== probe ==")

-- 1) The `arg` global.
local a = rawget(_G, "arg")
print("type(arg)  = " .. tostring(a))
if a ~= nil then
  print("arg[0]  = " .. tostring(a[0]))
  print("arg[1]  = " .. tostring(a[1]))
  print("arg[2]  = " .. tostring(a[2]))
end

-- 2) The vararg (only valid if the loaded chunk is vararg).
local n = 0
local first
local okv, v = pcall(function()
  first = select(1, ...)
  n = select("#", ...)
end)
print("vararg ok  = " .. tostring(okv))
if okv then
  print("vararg #   = " .. tostring(n))
  print("vararg[1] = " .. tostring(first))
end

print("== end probe ==")
