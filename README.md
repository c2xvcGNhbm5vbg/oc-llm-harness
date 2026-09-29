# OC LLM Harness

Chat with an LLM from inside a **Minecraft OpenComputers computer** — over the
computer's **internet card**, talking to any OpenAI-compatible `/v1/chat/completions`
endpoint (a local vLLM server, the real OpenAI API, etc.).

Beyond a chat REPL, it includes an **agentic coding harness**: a Pi-style loop with
4 tools (`read`/`write`/`edit`/`bash`) that lets the LLM develop and run
OpenComputers programs — in-game on the computer, or host-side through the OC
emulator.

This is a small, dependency-free set of Lua modules for the OpenComputers Lua
runtime (Lua 5.2 / LuaJ), plus an installer that the computer itself runs to pull
these files from GitHub over its internet card.

## Intended use: local inference servers only

This harness is designed to talk to a **local / self-hosted** LLM server on your
own network — e.g. a local vLLM, llama.cpp, or Ollama instance exposing an
OpenAI-compatible `/v1/chat/completions` API.

It is **not** intended for public LLM provider APIs, and there are **no plans to
support any real provider** (OpenAI, Anthropic, etc.). There is no API-key
handling and no cloud endpoint support — the model is expected to be reachable
from the computer over the internet card (typically on your LAN).

## What's here

| File | Purpose |
|------|---------|
| `lua/json.lua` | A small JSON encoder/decoder (OC ships none). |
| `lua/http.lua` | A minimal HTTP/1.1 client built on the internet card. |
| `lua/llm.lua` | An OpenAI-compatible chat client (history, thinking-model handling). |
| `lua/config.lua` | Loads `/etc/oc-llm.conf` (a simple `key = value` file). |
| `lua/chat.lua` | The interactive chat REPL you run in-game. |
| `lua/agent.lua` | The agentic coding harness (a library: `agent.run(task, opts)`). |
| `lua/agent_main.lua` | The in-game entry point, deployed to `/home/agent.lua`. |
| `lua/debug.lua` | In-game test/debug suite (installed with the `debug` keyword). |
| `lua/install.lua` | In-computer installer: pulls the above from GitHub. |
| `tests/` | A unit test (`test.lua`) and a real end-to-end test (`e2e.lua`). |

## How it works

```
+----------------------+        internet card        +----------------------+
|  OpenComputers      |  =======================>  |  LLM server          |
|  computer (Minecraft)|  (HTTPS/HTTP over LAN)   |  /v1/chat/completions |
+----------------------+  <=======================  +----------------------+
        chat.lua -> llm.lua -> http.lua -> component.internet
```

The computer's **internet card** makes the HTTP request to your LLM server. Your
server must be reachable from the computer and (importantly) the computer's
internet-card filtering rules must **allow** the LLM server's address — see
[Internet card filtering](#internet-card-filtering) below.

## Install (in-game)

1. Make sure the computer has an **internet card** installed.

2. **Bootstrap:** `install.lua` has to be on the computer first (the `lua` command
   runs a *local* file — it doesn't download one). Grab it with the built-in
   `wget`:

   ```
   wget -f https://raw.githubusercontent.com/c2xvcGNhbm5vbg/oc-llm-harness/main/lua/install.lua /home/install.lua
   ```

3. **Run the installer**, pointing it at this repo's raw file base:

   ```
   lua /home/install.lua https://raw.githubusercontent.com/c2xvcGNhbm5vbg/oc-llm-harness/main
   ```

   It downloads the remaining modules into `/lib/` (including the agentic
   harness, `agent.lua`), the chat program and the agent entry point into
   `/home/` (`chat.lua`, `agent.lua`), and writes a default
   `/etc/oc-llm.conf`.

   The installer is **versioned** — as of this README it is `install.lua 1.3.0`,
   which is the first version that deploys the agentic harness. Check the copy
   you have with the `version` keyword below; if it prints an older version,
   re-`wget` it.

   (How it works: `lua <file>` reads a *local* file named `<file>` and runs it,
   passing everything after the filename as arguments. So `lua /home/install.lua
   <url>` runs the local `install.lua`, which then uses the internet card to
   fetch the other files from `<url>`.)

   **Keywords** (positional — see the note below on why they're *not* `--` flags):

   ```
   lua /home/install.lua <url> debug    also install /home/debug.lua (test suite)
   lua /home/install.lua version        print which version of install.lua you have
   ```

   > **CDN caching:** `raw.githubusercontent.com` is served through a CDN that
   > caches files for a while after a push. If you just got a stale copy (check
   > with `lua /home/install.lua version`), wait a few minutes and re-`wget`.
   > Query-string cache-busting (`?nc=1`) does **not** work on that CDN.

4. **Edit `/etc/oc-llm.conf`** and set `base_url` to the address of your LLM
   server (the machine running the model), e.g. `http://<llm-host>:8080`.

5. Start chatting:

   ```
   lua /home/chat.lua
   ```

## The chat REPL

```
> <your message>          send it to the model
> /reset                 clear the conversation history
> /model <name>          switch model
> /system <text>         change the system prompt
> /tokens <n>            set max_tokens
> /temp <n>             set temperature
> /config [key value]   show/set a config value
> /history               show the stored conversation
> /help                 show help
> /quit                exit
```

## The in-game debug suite

`debug.lua` exercises the **real** internet card and **real** LLM server (from
`/etc/oc-llm.conf`) so you can catch problems in-game. Install it with the
`debug` keyword, then run it:

```
lua /home/install.lua <url> debug     install the suite
lua /home/debug.lua                  full suite (card probe, connectivity, small chat, slow generation, multi-turn)
lua /home/debug.lua quick            fast subset (card probe + connectivity + one chat)
```

Every run — pass or fail — writes **`/home/oc-llm-debug.log`** with the base_url,
model, per-test status, chunk counts, replies, and timing. If something fails,
`cat /home/oc-llm-debug.log` and share the output.

## The agentic coding harness

The chat REPL talks to the model one message at a time. The **agentic harness**
goes further: it gives the model a set of tools and lets it *act* — develop an
OpenComputers program, run it, read the output, and fix it — until it says it's
done.

### What it is

`lua/agent.lua` is a **library** exposing `agent.run(task, opts)` → *final text,
turns*. It runs a **Pi-style loop**:

1. Send the task (or the running conversation) to the model, with the tool
   schemas.
2. If the model returns **tool calls**, execute each one, feed the results back
   as `tool` messages, and **continue**.
3. If the model returns **no tool calls**, it is done — **stop**.

So the loop **continues iff the model called tools**; the model's plain text
(with no tool calls) is the final answer.

The **4 tools** (the "primitives, not features" set):

| Tool | What it does |
|------|--------------|
| `read(path)` | Read a file's contents. |
| `write(path, content)` | Create or overwrite a file. |
| `edit(path, old, new)` | Replace an exact string in a file. |
| `bash(command)` | Run a shell command (see the two paths below). |

File paths are resolved against a **workdir** (the agent's files live in one
place); `bash` runs in a **cwd**.

### How to install it

`install.lua` **1.3.0** is the first version that deploys the harness. Running
the installer (the steps above) now pulls:

- `lua/agent.lua` → `/lib/agent.lua` (the library — `require("agent")` resolves
  from `/lib`), and
- `lua/agent_main.lua` → `/home/agent.lua` (the in-game entry point).

If your `lua /home/install.lua version` prints something older than `1.3.0`,
re-`wget` the installer.

### How to run it in-game

On the OpenComputers computer, from the OpenOS shell:

```
lua /home/agent.lua <task>
```

For example:

```
lua /home/agent.lua Write a crop-breeding bot
```

The entry point (`/home/agent.lua`) loads `/etc/oc-llm.conf` (the same config
the chat REPL uses), then calls `agent.run` with:

- `workdir = /home` — the agent's files live on the computer's `/home`,
- `max_turns = 10`,
- `out = print` — progress (the model's text, each tool call, each result) prints
  to the terminal.

With no task, a default prompt is used. The final response is printed at the end.

### The in-game `bash` path

In-game, the `bash` tool runs commands through the computer's own shell —
**OpenOS's `io.popen`** (OpenOS ships it via `pipe`/`sh`). That shell is
sandboxed to the computer's drive, so the agent can **execute OpenComputers
programs in-game** the same way you would:

```
lua <file>
```

i.e. it writes a program to `/home`, then `bash`s `lua /home/<file>` to run it,
reads the output, and iterates.

### The host-side development path

The same `agent.lua` also runs **host-side** for development, without Minecraft.
There, the `__host_*` globals (emulator-only — they do **not** exist in-game)
take over:

- `__host_bash` — a real host shell, so the agent can run host commands such as
  `lua5.2 run.lua <script>` to boot the **OC emulator** and run what it wrote;
- `__host_write` / `__host_read` — host filesystem access for the file tools.

So host-side the agent develops OC programs and runs them through the emulator
(`lua5.2 run.lua <script>`), while in-game it runs them through the computer's
own shell (`lua <file>` via `io.popen`). The module picks whichever path is
available: it uses `__host_bash` when present and falls back to `io.popen`
otherwise.

## Configuration

`/etc/oc-llm.conf` (on the computer):

```
# Set base_url to the address of your LLM server (OpenAI-compatible API).
base_url = http://127.0.0.1:8080
model = qwen3.8-27b-vllm
max_tokens = 1024
temperature = 0.7
timeout = 120
system = You are a helpful assistant living inside a Minecraft OpenComputers computer. Be concise.
```

## Internet card filtering

OpenComputers internet cards have **filtering rules** (see the mod's
`application.conf`, `internet.filteringRules`). By default **all private addresses
are denied**, so a computer cannot talk to a server on your LAN unless you allow
it. On a dedicated server, edit the mod config to allow your LLM server, e.g.:

```
internet {
  filteringRules: [
    "removeme",
    "allow ip:<llm-server-ip>",     # allow the LLM server
    "deny private",
    "deny bogon",
    "allow default"
  ]
}
```

(First matching rule wins; put your `allow` before `deny private`.)

## Testing

```
lua5.3 tests/test.lua    # unit tests (mocked internet card)
lua5.3 tests/e2e.lua    # real end-to-end against a local LLM (set LLM_BASE_URL)
```

## Notes

- The installer's keywords (`debug`, `version`) are **positional, not `--`
  flags**: OC's `lua` command runs `shell.parse(...)`, which strips any
  `--`-prefixed token into an options table and discards it — so `--debug`
  would never reach the script.
- The LLM is a **thinking model**: it emits `reasoning` and `content`. With a
  small token budget all output can land in `reasoning` and `content` comes back
  `nil`, so `llm.lua` budgets tokens generously and falls back to the tail of
  `reasoning` when `content` is empty.
- This repo intentionally contains **no private network addresses** — the LLM
  server address lives only in the on-computer `/etc/oc-llm.conf`.
