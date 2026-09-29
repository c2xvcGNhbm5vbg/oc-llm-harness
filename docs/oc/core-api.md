# Core OC globals (GTNH-OpenComputers fork, OpenOS 1.8.x)

Sourced from the fork's actual Lua/Scala source (the ROM has no man pages).
Fork deltas are marked [FORK].

## computer
- realTime() -> number (seconds, wall clock)
- uptime() -> number (seconds since boot)
- address() -> string|nil (network node id)
- freeMemory() / totalMemory() -> number (bytes)
- pushSignal(name, ...) -> boolean
- tmpAddress() -> string|nil
- users() / addUser(name) / removeUser(name)
- energy() / maxEnergy() -> number (FE)
- getArchitectures() / getArchitecture() / setArchitecture(name)
- beep([freq[, dur]] | pattern)
- getDeviceInfo() / getProgramLocations()
- isRobot() -> boolean
- getBootAddress() / setBootAddress(addr)
- pullSignal(timeout) -> ... (yield until signal/timeout)
- shutdown(reboot) (true = reboot)
[FORK] No computer.run() and no computer.sleep(). Sleep = os.sleep; run a
program with shell.execute() / process / thread.

## component
- list(filter, exact) -> iterable (addr -> type)
- type(address) -> string|nil, reason
- slot(address) -> number|nil, reason
- methods(address) -> table (name -> {direct, getter, setter})
- invoke(address, method, ...) -> ...
- doc(address, method) -> string|nil
- proxy(address) -> proxy|nil, reason (cached method+field access — the
  ergonomic way to talk to any component)
- fields(address) -> table (getter/setter only)

## event
- register(key, callback, [interval], [times], [handlers]) -> id
- pull([timeout] | [name, ...]) -> ...
- pullFiltered([timeout] | [filter], [filter2])
- push = computer.pushSignal
- listen(name, callback)
- pullMultiple([timeout], [names...])
- cancel(id) / ignore(name, callback)
- timer(interval, callback, [times])

## shell
- resolve(path, [ext]) -> string|nil, reason
- parse(...) -> args, options (splits -x / --key=val)
- execute(command, [env], ...) -> ... (runs via $SHELL)
- getWorkingDirectory() / setWorkingDirectory(dir)
- getShell()
- getAlias / setAlias / getPath / setPath

## io
- open(path, [mode]) -> file|nil, reason (modes r/w/a + b)
- read(...) / write(...) (default stdin/stdout)
- lines([filename], ...)
- popen(prog, [mode], [env]) -> pipe
- input / output / error([file])
- tmpfile() / type(obj) / close / flush / dup(fd)
File object methods: read([n | *n | *l | *a]), write(...), close(), lines(...),
flush(), setvbuf(mode, size)

## term
- write(value, [wrap])
- read([history], [dobreak], [hint], [pwchar], [filter])
- pull([timeout], ...)
- clear()
- getCursor() / setCursor(x, y)
- getViewport() / setViewport(w, h, [dx, dy, x, y])
- bind(gpu, [window])
- scroll(lines)
- getGlobalArea() / clearLine() / setCursorBlink / getCursorBlink
[FORK] No setSize/locate/getSize/isColor. Size = getViewport (returns
w, h, dx, dy, x, y); locate = setCursor/getCursor.

## filesystem
- list(path)
- get(path) -> fsProxy, path|nil, reason
- size(path) / isDirectory(path) / exists(path)
- open(path, [mode])
- copy(from, to) / remove(path) / rename(old, new)
- mount(fs, path) / umount(fsOrPath)
- makeDirectory(path) / lastModified(path) / link(t, p)
- isLink(path) / mounts() / realPath / path / name / concat / canonical / proxy
[FORK] No filesystem.move — use rename. os.remove / os.rename are aliased to
filesystem.remove / rename.

## os
- getenv([var]) / setenv(var, value)
- sleep([timeout]) (yield)
- exit([code]) (raises {reason = "terminated", code})
- tmpname()
- remove / rename / execute(command) (= filesystem.* / shell.execute)
- clock() / date([fmt, t]) / time([t]) / difftime(t2, t1)

## bit32
band, bor, bxor, bnot, btest, arshift, lshift, rshift, lrotate, rrotate,
extract, replace (all take/return 32-bit integers)

## unicode
char(...), len(s), sub(s, i, [j]), lower(s) / upper(s), reverse(s),
isWide(s), charWidth(s), wlen(s), wtrunc(s, n)
