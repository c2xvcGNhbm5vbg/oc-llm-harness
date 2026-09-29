-- agent.lua -- A minimal agentic coding harness (Pi-style) for developing
-- OpenComputers programs for the GregTech New Horizons (GTNH) modpack.
--
-- "Primitives, not features": a single loop that calls the LLM, executes any
-- tool calls it returns, feeds the results back, and CONTINUES IFF the model
-- called tools. No tool calls -> the model is done -> the loop ends.
--
-- Tools (the 4 primitives):
--   read(path)                -> file contents
--   write(path, content)     -> create/overwrite a file
--   edit(path, old, new)     -> replace `old` with `new` in a file
--   bash(command)            -> run a shell command:
--                              * in-game (no __host_bash): OpenOS's sandboxed
--                                io.popen — run OC programs in-game with `lua <file>`
--                              * host-side (emulator, __host_bash present): a real
--                                host shell — run OC programs via `lua5.2 run.lua <script>`
--
-- The agent develops OC programs in a working directory and runs them (in-game
-- through the computer's own shell, host-side through the OC emulator), so it
-- can write -> run -> read the output -> fix, iteratively.
--
-- API:
--   agent.run(task, opts)   -> final text, turns
--   opts: { workdir, max_turns, max_tokens, system, out }
--
-- Uses the harness's llm/json/http modules (so it runs in-game on the OC
-- computer, and on the host for development).

local llm = require("llm")
local json = require("json")

local agent = {}

-------------------------------------------------------------------------------
-- Tool implementations (file ops + bash). Paths are resolved against a
-- workdir (so the agent's files live in one place); bash runs in a cwd.
-- When driven host-side (workdir + cwd set), bash is a real host shell and
-- `lua5.2 run.lua <script>` works. In-game, io.open/io.popen are OpenOS's
-- (drive-relative / sandboxed).
-------------------------------------------------------------------------------
local env = { workdir = nil, cwd = nil }

local function resolve(path)
  if not env.workdir then return path end
  if path:sub(1, 1) == "/" then return path end  -- absolute: use as-is
  return env.workdir .. "/" .. path
end

local function read_file(path)
  local p = resolve(path)
  local hr = rawget(_G, "__host_read")
  if hr then
    local data, err = hr(p)
    return data, err
  end
  local f = io.open(p, "rb")
  if not f then return nil, "no such file: " .. path end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_file(path, content)
  local p = resolve(path)
  local hw = rawget(_G, "__host_write")
  if hw then
    local ok, err = hw(p, content)
    return ok, err
  end
  local f, err = io.open(p, "wb")
  if not f then return false, err end
  f:write(content)
  f:close()
  return true
end

local function edit_file(path, old, new)
  local data, err = read_file(path)
  if not data then return false, err end
  if not data:find(old, 1, true) then
    return false, "edit: 'old' not found in " .. path
  end
  data = data:gsub(old, new, 1)
  return write_file(path, data)
end

-- Run a shell command, capture stdout+stderr. Returns (output, exit_code).
-- Uses the machine's native host shell (__host_bash) when available (so the
-- agent can run real host commands like `lua5.2 run.lua ...`); falls back to
-- io.popen (OpenOS's sandboxed shell) when not.
local function run_bash(command)
  local full = command
  if env.cwd then full = "cd " .. env.cwd .. " && " .. command end
  local bash = rawget(_G, "__host_bash")
  if bash then
    local out, code = bash(full)
    return out, code
  end
  local f, err = io.popen(full .. " 2>&1")
  if not f then return nil, 1 end
  local out = f:read("*a")
  local ok = f:close()
  local code = ok and 0 or 1
  return out, code
end

-- The 4 tools. Each takes a JSON-decoded args table, returns (output, ok, code).
local tools = {
  read = function(a)
    local data, err = read_file(a.path)
    if not data then return nil, err end
    return data
  end,
  write = function(a)
    local ok, err = write_file(a.path, a.content or "")
    if not ok then return nil, err end
    return "wrote " .. tostring(#(a.content or "")) .. " bytes to " .. a.path
  end,
  edit = function(a)
    local ok, err = edit_file(a.path, a.old, a.new)
    if not ok then return nil, err end
    return "edited " .. a.path
  end,
  bash = function(a)
    local out, code = run_bash(a.command)
    if not out then return nil, "command failed" end
    return out .. "\n[exit " .. code .. "]"
  end,
}

-- OpenAI function-calling tool schemas.
local tool_schemas = {
  { type = "function", ["function"] = { name = "read",
    description = "Read a file's contents. Args: {path}.",
    parameters = { type = "object",
      properties = { path = { type = "string" } }, required = { "path" } } } },
  { type = "function", ["function"] = { name = "write",
    description = "Create or overwrite a file. Args: {path, content}.",
    parameters = { type = "object",
      properties = { path = { type = "string" }, content = { type = "string" } },
      required = { "path", "content" } } } },
  { type = "function", ["function"] = { name = "edit",
    description = "Replace an exact string in a file. Args: {path, old, new}.",
    parameters = { type = "object",
      properties = { path = { type = "string" }, old = { type = "string" },
        new = { type = "string" } },
      required = { "path", "old", "new" } } } },
  { type = "function", ["function"] = { name = "bash",
    description = "Run a shell command. In-game this is the computer's own (OpenOS) "
      .. "shell — to run an OC program use `lua <file>`. Host-side (emulator) it is a "
      .. "real host shell — to run an OC program use `lua5.2 run.lua <script>`. "
      .. "Args: {command}.",
    parameters = { type = "object",
      properties = { command = { type = "string" } }, required = { "command" } } } },
}

-------------------------------------------------------------------------------
-- System prompt: focused on developing OC programs for GTNH.
-------------------------------------------------------------------------------
local DEFAULT_SYSTEM = [[
You are a coding agent that develops OpenComputers (OC) Lua programs for the
GregTech New Horizons (GTNH) Minecraft modpack (Minecraft 1.7.10, OC 1.8.10).

Environment:
- OC computers run Lua 5.2 (jnlua/LuaJ) with OpenOS. Key globals: component,
  computer, filesystem, internet, event, shell, io, term, bit32, unicode, os.
- The internet card: local req = internet.request(url, body, headers, method);
  req.response() -> status, message, headers; req.read() -> chunk (nil at EOF).
- The filesystem: io.open(path, mode), f:read/write/close; filesystem.list(path).
- OC's `lua` command runs a LOCAL file; args are positional (shell.parse strips
  `--` flags, so use positional keywords, not `--flags`).

How to run an OC program (you have a bash tool):
- In-game (on the computer): `lua <file>` — e.g. you write "oc-hello.lua" to
  /home, then run `lua /home/oc-hello.lua`. This uses the computer's own shell.
- Host-side (emulator): `lua5.2 run.lua <script>` — e.g.
  `lua5.2 run.lua <workdir>/oc-hello.lua` (where <workdir> is the directory your
  file tools write to). This boots real OpenOS and runs the script.
Use whichever matches your environment to test what you write.

GTNH example projects to model your work after (crop breeding bot, autoPump,
FoxHUD, autoStock, NIDAS): they poll machines via component APIs, read/write
item stacks, and act on state.

Workflow: plan -> write the program (write/edit) -> run it (bash) -> read the
output -> fix if needed. Keep programs small and focused. When the task is
done, reply with a short summary and STOP (no tool calls).
]]

-------------------------------------------------------------------------------
-- The agent loop.
-------------------------------------------------------------------------------
function agent.run(task, opts)
  opts = opts or {}
  local max_turns = opts.max_turns or 12
  local out = opts.out or function(s) print(s) end
  env.workdir = opts.workdir
  env.cwd = opts.cwd

  llm.reset()
  llm.system(opts.system or DEFAULT_SYSTEM)

  local turns = 0
  while turns < max_turns do
    turns = turns + 1
    -- First turn: send the task (user message). Subsequent turns: continue the
    -- conversation (no new user message — the history carries it).
    local message, reason
    if turns == 1 then
      message, reason = llm.raw_ask(task, { max_tokens = opts.max_tokens, tools = tool_schemas })
    else
      message, reason = llm.raw_step({ max_tokens = opts.max_tokens, tools = tool_schemas })
    end
    if not message then
      out("[agent] LLM error: " .. tostring(reason))
      return nil, turns
    end

    -- Print the model's text (if any).
    if message.content and message.content ~= "" then
      out(message.content)
    end

    -- No tool calls -> the model is done.
    if not message.tool_calls or #message.tool_calls == 0 then
      return message.content, turns
    end

    -- Execute each tool call, feed results back as tool messages.
    for _, tc in ipairs(message.tool_calls) do
      local fn = tc["function"]
      local name = fn and fn.name
      local args = {}
      local dok = pcall(function()
        local ok, decoded = pcall(json.decode, (fn and fn.arguments) or "{}")
        if ok and type(decoded) == "table" then args = decoded end
      end)
      out("[tool] " .. tostring(name) .. " " .. (fn and fn.arguments or ""))
      local result
      if tools[name] then
        local ok2, val = pcall(tools[name], args)
        result = ok2 and tostring(val) or tostring(select(2, pcall(tools[name], args)))
      else
        result = "unknown tool: " .. tostring(name)
      end
      out("[tool result] " .. result:sub(1, 400))
      -- Append the tool result so the model sees it (with tool_call_id for the API).
      table.insert(llm.history(), {
        role = "tool",
        tool_call_id = tc.id,
        name = name,
        content = result,
      })
    end
  end
  out("[agent] max turns reached")
  return nil, turns
end

-------------------------------------------------------------------------------
return agent
