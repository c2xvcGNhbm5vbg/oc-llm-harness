# robot component API (GTNH-OpenComputers fork)

The `robot` module is a Lua module mounted on the robot (symlinked into
/lib/robot and /bin/*). It wraps a small set of native Scala component
methods. ~55 methods in four capability families.
Conventions: side args are 0-5 (bottom/top/back/front/right/left); sneaky =
boolean (silent, no animation); count = nil = all. Almost every action comes
in front/up/down variants.

## General
- name() -> string
- level() -> number (XP level; 0 if no experience upgrade)
- getLightColor() / setLightColor(value) (0xRRGGBB)
- durability() -> number, reason? (equipped tool)

## Movement (7)
- forward() / back() / up() / down()
- turnLeft() / turnRight() / turnAround()
[FORK] No rotate / moveHead / getPosition / setPosition. Rotation =
turnLeft / turnRight / turnAround.

## Block sensing & interaction (9)
- detect() / detectUp() / detectDown()
- swing([side], [sneaky]) / swingUp / swingDown (break/interact)
- use([side], [sneaky], [duration]) / useUp / useDown
[FORK] No getBlock* / setBlock* / weld / screwdriver / extend / attack /
interact / dig / throw / eject / empty / sense / getItem* / useItem.
Sensing = detect*; interaction = swing* / use*.

## Item manipulation (~20)
- inventorySize()
- select(...) / count(...) / space(...) / compareTo(...) / transferTo(...)
- compare([fuzzy]) / compareUp / compareDown
- drop([count]) / dropUp / dropDown
- place([side], [sneaky]) / placeUp / placeDown
- suck([count]) / suckUp / suckDown

## Fluids (~15, only with tank upgrades)
- tankCount() / selectTank(tank)
- tankLevel(...) / tankSpace(...)
- compareFluidTo(...) / transferFluidTo(...)
- compareFluid() / compareFluidUp / compareFluidDown
- drain([count]) / drainUp / drainDown
- fill([count]) / fillUp / fillDown
