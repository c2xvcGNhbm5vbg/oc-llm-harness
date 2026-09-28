-- chat.lua -- Interactive LLM chat for an OpenComputers computer.
--
-- Run it from the OpenOS shell:
--     lua chat
-- or, once installed on the path, just:
--     chat
--
-- It loads /etc/oc-llm.conf, talks to the configured LLM over the internet card,
-- and gives you a small REPL:
--
--     > <your message>          send it to the model
--     > /reset                 clear the conversation history
--     > /model <name>          switch model
--     > /system <text>         change the system prompt
--     > /tokens <n>            set max_tokens
--     > /config [key value]    show/set a config value
--     > /help                 show this help
--     > /quit                exit
--
-- The model is a thinking model, so responses can take a while; a "thinking..."
-- indicator is shown while the request is in flight.

local config = require("config")
local llm = require("llm")
local shell = require("shell")

local term = require("term")

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

local cfg = config.load()
llm.configure(cfg)

local function banner()
  term.setPalette(0)
  print()
  print("=== OpenComputers LLM Chat ===")
  print("model: " .. tostring(cfg.model or "default"))
  print("type /help for commands, /quit to exit")
  print()
end

local function help()
  print("Commands:")
  print("  /reset            clear conversation history")
  print("  /model <name>   switch model")
  print("  /system <text>  change the system prompt")
  print("  /tokens <n>     set max_tokens")
  print("  /temp <n>       set temperature")
  print("  /config [k v]   show config / set a value")
  print("  /history        show the stored conversation")
  print("  /help           this help")
  print("  /quit          exit")
end

-------------------------------------------------------------------------------
-- Command handling
-------------------------------------------------------------------------------

local function handle_command(line)
  local cmd, arg = line:match("^/(%S+)(%s+.*$)?")
  if not cmd then return false end
  arg = arg and arg:gsub("^%s+", ""):gsub("%s+$", "")

  if cmd == "quit" or cmd == "exit" then
    return true
  elseif cmd == "help" then
    help()
  elseif cmd == "reset" then
    llm.reset()
    print("history cleared")
  elseif cmd == "model" and arg then
    llm.configure({model = arg})
    print("model = " .. arg)
  elseif cmd == "system" and arg then
    llm.system(arg)
    print("system prompt updated")
  elseif cmd == "tokens" and arg then
    llm.configure({max_tokens = tonumber(arg) or 1024})
    print("max_tokens = " .. arg)
  elseif cmd == "temp" and arg then
    llm.configure({temperature = tonumber(arg) or 0.7})
    print("temperature = " .. arg)
  elseif cmd == "config" then
    local k, v = arg and arg:match("^(%S+)%s+(.+)$")
    if k and v then
      local num = tonumber(v)
      llm.configure({[k] = num or v})
      print(k .. " = " .. v)
    else
      -- show a few values
      local c = llm.configure()
      print("base_url    = " .. tostring(c.base_url))
      print("model       = " .. tostring(c.model))
      print("max_tokens  = " .. tostring(c.max_tokens))
      print("temperature = " .. tostring(c.temperature))
      print("timeout     = " .. tostring(c.timeout))
    end
  elseif cmd == "history" then
    local h = llm.history()
    if #h == 0 then
      print("(empty)")
    else
      for i, m in ipairs(h) do
        print(m.role .. ": " .. m.content)
      end
    end
  else
    print("unknown command: /" .. cmd .. "  (try /help)")
  end
  return false
end

-------------------------------------------------------------------------------
-- Main loop
-------------------------------------------------------------------------------

banner()

while true do
  local line = shell.prompt("> ", "")
  line = line:gsub("%s+$", "")
  if line == "" then
    -- empty line: just re-prompt
  elseif line:sub(1, 1) == "/" then
    if handle_command(line) then
      break
    end
  else
    -- Show a plain thinking indicator, then ask. (OC's terminal is line-based;
    -- in-place line edits are not reliable, so we just print a marker.)
    print("thinking...")
    local reply, reason = llm.ask(line)
    if reply then
      print(reply)
    else
      print("error: " .. reason)
    end
  end
end

print("bye")
