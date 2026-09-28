-- probe.lua -- Diagnostic: how does OC's `lua` command pass command-line args?
--
-- Run:  lua /home/probe.lua TESTARG
--
-- The `lua` command invokes a script as `pcall(script, table.unpack(args, 2))`,
-- so command-line arguments arrive as VARARGS. A chunk loaded via `load` is
-- vararg, so `...` is valid at top level. This reports what the vararg and the
-- `arg` global each carry.

print("== probe ==")

-- 1) The vararg (valid at top level of a vararg chunk).
local vfirst = select(1, ...)
local vcount = select("#", ...)
print("vararg #   = " .. tostring(vcount))
print("vararg[1] = " .. tostring(vfirst))

-- 2) The `arg` global (usually empty when invoked via the `lua` command).
local a = rawget(_G, "arg")
print("type(arg)  = " .. tostring(a))
if a ~= nil then
  print("arg[0]  = " .. tostring(a[0]))
  print("arg[1]  = " .. tostring(a[1]))
end

print("== end probe ==")
