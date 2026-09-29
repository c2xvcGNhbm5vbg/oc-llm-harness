-- llm.lua -- A small OpenAI-compatible chat client for the OpenComputers Lua runtime.
--
-- Talks to any OpenAI-compatible /v1/chat/completions endpoint (the local vLLM
-- on this box, or the real OpenAI API, etc.) over the internet card.
--
-- The local model is a *thinking* model: it emits a `reasoning` field and a
-- `content` field. With a small token budget all output can go into `reasoning`
-- and `content` comes back nil, so this client (a) budgets tokens generously
-- and (b) falls back to the tail of `reasoning` when `content` is empty.
--
-- API:
--   llm.configure(cfg-table)        -- override defaults (see below)
--   llm.reset()                    -- clear conversation history
--   llm.ask(user_text, opts)       -> reply string, or nil, reason
--   llm.system(text)               -- set the system prompt
--   llm.history()                  -> the message table (for inspection)
--
-- Default config (override with llm.configure):
--   base_url   = "http://127.0.0.1:8080"   -- the LLM host (set this to the
--                                          -- actual address of your LLM server)
--   model      = "qwen3.8-paro-int5-swift"
--   max_tokens = 1024
--   temperature = 0.7
--   system     = "You are a helpful assistant living inside a Minecraft OpenComputers computer. Be concise."
--   timeout    = 120   (seconds)

local http = require("http")
local json = require("json")

local llm = {}

local defaults = {
  -- Placeholder: override in /etc/oc-llm.conf (or llm.configure) with the
  -- address of your LLM server.
  base_url = "http://127.0.0.1:8080",
  model = "qwen3.8-paro-int5-swift",
  max_tokens = 1024,
  temperature = 0.7,
  system = "You are a helpful assistant living inside a Minecraft "
    .. "OpenComputers computer. Be concise and direct.",
  timeout = 120,
}

local cfg = {}
for k, v in pairs(defaults) do cfg[k] = v end

local history = {}   -- list of {role=, content=}

-------------------------------------------------------------------------------

function llm.configure(c)
  for k, v in pairs(c or {}) do
    cfg[k] = v
  end
  return cfg
end

function llm.system(text)
  cfg.system = text
  -- Keep the system prompt as the first message.
  if #history > 0 and history[1].role == "system" then
    history[1].content = text
  else
    table.insert(history, 1, {role = "system", content = text})
  end
end

function llm.reset()
  history = {}
end

function llm.history()
  return history
end

-------------------------------------------------------------------------------

-- Build the request message list: system prompt + stored history.
-- The system prompt is NOT stored in `history`; it is always prepended here, so
-- there is no risk of a duplicate.
local function build_messages()
  local messages = {}
  if cfg.system then
    table.insert(messages, {role = "system", content = cfg.system})
  end
  for i = 1, #history do
    table.insert(messages, history[i])
  end
  return messages
end

-- Trim a long string for display (OC screens are small).
local function truncate(s, n)
  s = tostring(s)
  if #s <= n then return s end
  return s:sub(1, n - 3) .. "..."
end

-------------------------------------------------------------------------------

-- Ask the model a question. Appends the user message and the assistant reply to
-- the history. Returns the reply string, or nil and a reason string.
--   opts: {
--     max_tokens  = number,
--     temperature = number,
--     no_think    = boolean,   -- send "no_think" to skip reasoning (if supported)
--   }
function llm.ask(user_text, opts)
  opts = opts or {}

  local messages = build_messages()
  table.insert(messages, {role = "user", content = user_text})

  local payload = {
    model = cfg.model,
    messages = messages,
    max_tokens = opts.max_tokens or cfg.max_tokens,
    temperature = opts.temperature or cfg.temperature,
  }

  -- Optional: ask the thinking model to skip reasoning (Qwen honors "no_think").
  if opts.no_think then
    messages[#messages].content = messages[#messages].content .. " no_think"
  end

  local resp, reason = http.post_json(cfg.base_url .. "/v1/chat/completions", payload, {
    timeout = cfg.timeout,
  })
  if not resp then
    return nil, "request failed: " .. reason
  end

  if resp.status < 200 or resp.status >= 300 then
    return nil, "HTTP " .. resp.status .. ": " .. truncate(resp.body, 300)
  end

  local parsed, reason2 = json.decode(resp.body)
  if not parsed then
    return nil, "bad JSON from model: " .. reason2 .. " body: " .. truncate(resp.body, 200)
  end

  local choices = parsed.choices
  if not choices or #choices == 0 then
    return nil, "no choices in response: " .. truncate(resp.body, 300)
  end

  local message = choices[1].message or {}
  local content = message.content
  local reasoning = message.reasoning

  -- The thinking model may put everything in `reasoning` and leave `content` nil.
  if (not content or content == "") and reasoning and reasoning ~= "" then
    -- Use the tail of the reasoning as a best-effort answer.
    local r = tostring(reasoning)
    content = r:sub(-300)
  end

  if not content or content == "" then
    return nil, "model returned empty content (finish_reason="
      .. tostring(choices[1].finish_reason) .. ")"
  end

  -- Record the exchange in history.
  table.insert(history, {role = "user", content = user_text})
  table.insert(history, {role = "assistant", content = content})

  return content
end

-------------------------------------------------------------------------------
-- raw_ask: like ask, but returns the FULL assistant message (incl. tool_calls)
-- so an agent loop can inspect tool calls. Returns (message, nil) or (nil, reason).
-- message = { content = <string>, tool_calls = <table|nil>, reasoning = <string|nil> }.
function llm.raw_ask(user_text, opts)
  opts = opts or {}
  local messages = build_messages()
  table.insert(messages, {role = "user", content = user_text})

  local payload = {
    model = cfg.model,
    messages = messages,
    max_tokens = opts.max_tokens or cfg.max_tokens,
    temperature = opts.temperature or cfg.temperature,
  }
  if opts.tools then payload.tools = opts.tools end
  if opts.no_think then
    messages[#messages].content = messages[#messages].content .. " no_think"
  end

  local resp, reason = http.post_json(cfg.base_url .. "/v1/chat/completions", payload, {
    timeout = cfg.timeout,
  })
  if not resp then
    return nil, "request failed: " .. reason
  end
  if resp.status < 200 or resp.status >= 300 then
    return nil, "HTTP " .. resp.status .. ": " .. truncate(resp.body, 300)
  end
  local parsed, reason2 = json.decode(resp.body)
  if not parsed then
    return nil, "bad JSON from model: " .. reason2 .. " body: " .. truncate(resp.body, 200)
  end
  local choices = parsed.choices
  if not choices or #choices == 0 then
    return nil, "no choices in response: " .. truncate(resp.body, 300)
  end
  local message = choices[1].message or {}
  local content = message.content
  local reasoning = message.reasoning
  if (not content or content == "") and reasoning and reasoning ~= "" then
    content = tostring(reasoning):sub(-300)
  end
  -- Record the exchange (store the full message so tool_calls are kept in history).
  table.insert(history, {role = "user", content = user_text})
  local stored = {role = "assistant", content = content}
  if message.tool_calls then stored.tool_calls = message.tool_calls end
  table.insert(history, stored)
  return message
end

-------------------------------------------------------------------------------
-- raw_step: send the CURRENT history (no new user message) and append the
-- assistant response. Used by the agent loop for turns after the first.
function llm.raw_step(opts)
  opts = opts or {}
  local messages = build_messages()
  local payload = {
    model = cfg.model,
    messages = messages,
    max_tokens = opts.max_tokens or cfg.max_tokens,
    temperature = opts.temperature or cfg.temperature,
  }
  if opts.tools then payload.tools = opts.tools end
  if opts.no_think then
    messages[#messages].content = messages[#messages].content .. " no_think"
  end
  local resp, reason = http.post_json(cfg.base_url .. "/v1/chat/completions", payload, {
    timeout = cfg.timeout,
  })
  if not resp then return nil, "request failed: " .. reason end
  if resp.status < 200 or resp.status >= 300 then
    return nil, "HTTP " .. resp.status .. ": " .. truncate(resp.body, 300)
  end
  local parsed, reason2 = json.decode(resp.body)
  if not parsed then
    return nil, "bad JSON from model: " .. reason2 .. " body: " .. truncate(resp.body, 200)
  end
  local choices = parsed.choices
  if not choices or #choices == 0 then
    return nil, "no choices in response: " .. truncate(resp.body, 300)
  end
  local message = choices[1].message or {}
  local content = message.content
  local reasoning = message.reasoning
  if (not content or content == "") and reasoning and reasoning ~= "" then
    content = tostring(reasoning):sub(-300)
  end
  local stored = {role = "assistant", content = content}
  if message.tool_calls then stored.tool_calls = message.tool_calls end
  table.insert(history, stored)
  return message
end

-------------------------------------------------------------------------------

return llm
