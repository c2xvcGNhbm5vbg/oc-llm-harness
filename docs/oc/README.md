# OC Skills Index (GTNH-OpenComputers fork)

Read a skill BEFORE writing code that uses it.

| Skill | What it covers |
|---|---|
| core-api.md | Core globals: computer, component, event, shell, io, term, filesystem, os, bit32, unicode |
| robot.md | robot component API (~55 methods): movement, block sensing/interaction, items, fluids |
| gtnh-extras.md | GTNH-fork-only: tps_card, me/beekeeper/configurator/RTG upgrades, IC2/TE/Avaritia drivers, Transposer/Geolyzer/GT additions |

Key fork deltas (read before assuming upstream OC behavior):
- No computer.run() and no computer.sleep(). Sleep = os.sleep; run a program
  with shell.execute() / process / thread.
- Robot rotation is turnLeft/turnRight/turnAround. There is no rotate, no
  moveHead, no getPosition/setPosition.
- No filesystem.move — use filesystem.rename.
- term has no setSize/locate/getSize/isColor. Size = getViewport (returns
  w, h, dx, dy, x, y); locate = setCursor/getCursor.
- The ROM has no doc/ man pages. These files are the reference.
