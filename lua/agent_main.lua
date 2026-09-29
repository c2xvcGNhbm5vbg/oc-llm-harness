-- agent_main.lua -- In-game entry point for the agentic coding harness.
--
-- Deployed to /home/agent.lua by install.lua (the library itself lives at
-- /lib/agent.lua, so require("agent") resolves from /lib).
--
-- Run it from the OpenOS shell:
--
--     lua /home/agent.lua <task>
--
-- <task> is the job for the agent (e.g. "write a program that ...").
-- With no task, a default prompt is used.
--
-- The agent's file tools write to /home (the computer's home), and its bash
-- tool runs commands through the computer's shell (io.popen / sh) — on a
-- real OC computer that is OpenOS's sandboxed shell, so it can execute OC
-- programs in-game.
--
-- OpenOS (Lua 5.2 / LuaJ) only: no host-only deps.

local config = require("config")
local llm = require("llm")
local agent = require("agent")

-- Load /etc/oc-llm.conf (the LLM server address lives there, not in the repo).
local cfg = config.load()
llm.configure(cfg)

-- OC's `lua` command invokes the script as pcall(script, table.unpack(args, 2)),
-- so command-line arguments arrive as VARARGS (select(1, ...)), not via the
-- `arg` global. Read the task from the vararg; fall back to the `arg` table
-- only if some other invocation method populates it.
local n = select("#", ...)
local ARGS = {}
for i = 1, n do
  ARGS[i] = select(i, ...)
end
if n == 0 then
  local a = rawget(_G, "arg")
  if a then
    for i = 1, #a do ARGS[i] = a[i] end
  end
end

local DEFAULT_TASK = "Write a small OpenComputers Lua program that prints a greeting to the terminal, and verify it works."

local task = ARGS[1] or DEFAULT_TASK

print("[agent] task: " .. task)

local opts = {
  workdir = "/home",   -- the agent's files live on the computer's /home
  max_turns = 10,
  out = print,
}

local final, turns = agent.run(task, opts)
if final then
  print("\n[agent] done in " .. turns .. " turn(s). Final response:")
  print(final)
else
  print("\n[agent] no final response after " .. turns .. " turn(s)")
end
