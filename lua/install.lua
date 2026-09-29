-- install.lua -- In-computer installer for the OC LLM harness.
--
-- Run it on the OpenComputers computer (it needs an internet card).
--
-- Bootstrap (install.lua must be on the computer first — the `lua` command runs
-- a LOCAL file, it does not download one). Grab it with the built-in wget:
--
--     wget -f https://raw.githubusercontent.com/<owner>/<repo>/main/lua/install.lua /home/install.lua
--
-- Then run the installer, pointing it at the repo's raw file base:
--
--     lua /home/install.lua https://raw.githubusercontent.com/<owner>/<repo>/main
--
-- ("main" is the branch; use "master" if that's your default branch.)
--
-- It downloads the library modules into /lib/, the chat program into /home/,
-- and writes a default /etc/oc-llm.conf (where you set the address of your
-- local LLM server). It is idempotent: re-running it refreshes the files.
--
-- The LLM server address is NOT stored in the repo — it lives in the on-computer
-- /etc/oc-llm.conf, so the repo stays free of any private network details.
--
-- Check which version you have (positional keyword — OC's `lua` command strips
-- `--`-prefixed tokens, so flags like `--version` never reach the script):
--
--     lua /home/install.lua version

local component = require("component")
local fs = require("filesystem")
local internet = require("internet")

-- Bump this on every change to install.lua so you can tell which copy you have.
local VERSION = "1.4.1"

-- The `lua` command invokes a script as `pcall(script, table.unpack(args, 2))`,
-- so command-line arguments arrive as VARARGS (select(1, ...)), not via the
-- `arg` global. Read the URL from the vararg; fall back to the `arg` table
-- only if some other invocation method populates it.
-- NOTE: OC's `lua` command runs `shell.parse(...)`, which STRIPS any `--`-prefixed
-- token into an options table and discards it — only positional args reach the
-- script via `table.unpack(args, 2)`. So we use positional keywords, NOT `--` flags:
--
--     lua /home/install.lua <raw_base_url> [debug]
--     lua /home/install.lua version
--
-- "debug" (anywhere) also installs /home/debug.lua; "version" prints the version
-- and exits.
local n = select("#", ...)
local ARGS = {}
for i = 1, n do
  ARGS[i] = select(i, ...)
end
-- Fallback to the `arg` table if some other invocation method populates it.
if n == 0 then
  local a = rawget(_G, "arg")
  if a then
    for i = 1, #a do ARGS[i] = a[i] end
  end
end

-- "version": print which copy of install.lua you have and exit.
for i = 1, #ARGS do
  if ARGS[i] == "version" then
    print("install.lua version " .. VERSION)
    return
  end
end

-- "debug" (anywhere): also install the in-game test suite.
local DEBUG = false
for i = 1, #ARGS do
  if ARGS[i] == "debug" then
    DEBUG = true
  end
end

-- The first non-keyword arg is the base URL.
local BASE = nil
for i = 1, #ARGS do
  if ARGS[i] ~= "version" and ARGS[i] ~= "debug" then
    BASE = ARGS[i]
    break
  end
end

if not BASE then
  print("Usage: lua /home/install.lua <raw_base_url> [debug]")
  print("  e.g. lua /home/install.lua https://raw.githubusercontent.com/<owner>/<repo>/main")
  print("  debug: also install /home/debug.lua (in-game test suite)")
  print("  version: print the version of this installer and exit")
  print("(First get install.lua via: wget -f <.../lua/install.lua> /home/install.lua)")
  return
end
-- Normalise: strip a trailing slash.
BASE = BASE:gsub("/$", "")

if not component.isAvailable("internet") then
  print("This installer needs an internet card installed.")
  return
end

-------------------------------------------------------------------------------
-- Download a URL to a file. Returns true, or false, reason.
-------------------------------------------------------------------------------

local function download(url, path)
  local request, reason = internet.request(url, nil,
    {["user-agent"] = "OC-LLM-Installer/1.0", ["Connection"] = "close"})
  if not request then
    return false, reason
  end

  -- Real card API (see http.lua): finishConnect, then read the body-only
  -- stream (the status is only set once the body has fully arrived), then
  -- poll response() for the status. We buffer the body and only write it to
  -- disk on a 200 — a 404/403 body is NOT the file. (The previous version
  -- wrote the body unconditionally, so a failed fetch left a bogus "ok" file
  -- in place of the real one — the stale-file bug.)
  pcall(request.finishConnect)

  local body = {}
  local bytes = 0
  local ok, reason3 = pcall(function()
    for chunk in request do
      if chunk and #chunk > 0 then
        body[#body + 1] = chunk
        bytes = bytes + #chunk
      end
    end
  end)
  if not ok then
    pcall(request.close)
    return false, "download failed: " .. tostring(reason3)
  end

  -- Poll for the status (the card sets it once the body has fully arrived),
  -- then close. Same sequence as http.lua:request.
  local status
  for _ = 1, 500 do
    status = request.response()
    if status then break end
    if os.sleep then os.sleep(0) end
  end
  pcall(request.close)
  if status ~= 200 then
    return false, "HTTP " .. tostring(status)
  end
  if bytes == 0 then
    return false, "empty response body"
  end

  local f, reason2 = io.open(path, "wb")
  if not f then
    return false, "cannot open " .. path .. " for writing: " .. reason2
  end
  local ok2, reason4 = pcall(function()
    for _, chunk in ipairs(body) do
      if not f:write(chunk) then
        error("write failed (drive full?)")
      end
    end
  end)
  f:close()
  if not ok2 then
    return false, "write failed: " .. tostring(reason4)
  end
  return true, bytes
end

-------------------------------------------------------------------------------
-- Ensure a directory exists (creates it if missing).
-------------------------------------------------------------------------------

local function ensure_dir(dir)
  if not fs.exists(dir) then
    fs.makeDirectory(dir)
  end
end

-------------------------------------------------------------------------------
-- The files to install: {repo-path, destination-path}
-------------------------------------------------------------------------------

local LIB = "/lib"
local HOME = "/home"
local ETC = "/etc"
local OCDATA = "/lib/ocdocs"

local files = {
  { "lua/json.lua",   LIB .. "/json.lua" },
  { "lua/http.lua",   LIB .. "/http.lua" },
  { "lua/llm.lua",    LIB .. "/llm.lua" },
  { "lua/config.lua", LIB .. "/config.lua" },
  { "lua/agent.lua",     LIB .. "/agent.lua" },
  { "lua/agent_main.lua", HOME .. "/agent.lua" },
  { "lua/chat.lua",   HOME .. "/chat.lua" },
  { "docs/oc/README.md",      OCDATA .. "/README.md" },
  { "docs/oc/core-api.md",   OCDATA .. "/core-api.md" },
  { "docs/oc/robot.md",      OCDATA .. "/robot.md" },
  { "docs/oc/gtnh-extras.md", OCDATA .. "/gtnh-extras.md" },
}
if DEBUG then
  table.insert(files, { "lua/debug.lua", HOME .. "/debug.lua" })
end

print("Installing OC LLM harness (install.lua " .. VERSION .. ") from " .. BASE .. " ...")
ensure_dir(LIB)
ensure_dir(HOME)
ensure_dir(ETC)
ensure_dir(OCDATA)

local all_ok = true
for _, f in ipairs(files) do
  local url = BASE .. "/" .. f[1]
  -- Remove any stale copy first, so a re-download can't leave a partial/old file
  -- behind (the config file is NOT in this list, so it is never touched).
  if fs.exists(f[2]) then
    fs.remove(f[2])
  end
  local ok, reason = download(url, f[2])
  if ok then
    print("  ok   " .. f[2] .. " (" .. tostring(reason) .. " bytes)")
  else
    print("  FAIL " .. f[2] .. "  (" .. tostring(reason) .. ")")
    all_ok = false
  end
end

-------------------------------------------------------------------------------
-- Write a default config (only if one does not already exist).
--
-- NOTE: base_url here is a placeholder. Edit this file to point at YOUR LLM
-- server (the address of the machine running the model).
-------------------------------------------------------------------------------

local CONF = ETC .. "/oc-llm.conf"
if not fs.exists(CONF) then
  local f, reason = io.open(CONF, "w")
  if f then
    f:write(table.concat({
      "# OC LLM harness configuration",
      "# Set base_url to the address of your LLM server (OpenAI-compatible API).",
      "base_url = http://127.0.0.1:8080",
      "model = qwen3.8-paro-int5-swift",
      "max_tokens = 1024",
      "temperature = 0.7",
      "timeout = 120",
      "system = You are a helpful assistant living inside a Minecraft OpenComputers computer. Be concise.",
      "",
    }, "\n"))
    f:close()
    print("  ok   " .. CONF .. " (default — EDIT base_url to your LLM server)")
  else
    print("  FAIL " .. CONF .. "  (" .. reason .. ")")
    all_ok = false
  end
else
  print("  skip " .. CONF .. " (already exists)")
end

-------------------------------------------------------------------------------

if all_ok then
  print("\nDone. Start chatting with:  lua /home/chat.lua")
  if DEBUG then
    print("Debug suite installed — run it with:  lua /home/debug.lua")
  end
else
  print("\nFinished with errors (see above).")
end
