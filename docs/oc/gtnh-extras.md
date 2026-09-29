# GTNH-fork-specific components (not in upstream OC)

Everything new is items (cards/upgrades) plus drivers for other mods' blocks.
No new blocks/tile-entities were added by the fork.

## New card
### tps_card (oc:tpsCard) — server TPS / perf diagnostics
OP right-click while sneaking binds a player (needed for the coordinate method).
- getTickTimeInDim(dimension) / getOverallTickTime()
- getAllDims() / getAllTickTimes() / getNameForDim(dimension)
- convertTickTimeIntoTps(time) (ms -> TPS, capped at 20)
- getOverallTileEntitiesLoaded() / getOverallChunksLoaded() / getOverallEntitiesLoaded() / getOverallDimsLoaded()
- getEntitiesListForDim(dimension) / getTileEntitiesListForDim(dimension)
- getChunksLoadedForDim(dimension)
- getCoordinatesForEntityClassInDim(className, dimension) (requires bound player)

## New upgrades (robots / drones / microcontrollers)
### me_upgrade1/2/3 (oc:me_upgrade1/2/3) — AE2 network access (range-gated by tier)
- sendItems([amount]) / requestItems(database, entry[, amount])
- sendFluids([amount]) / requestFluids(database, entry[, amount])
- isLinked()

### beekeeperUpgrade (oc:beekeeperUpgrade) — Forestry + GenIndustry apiaries
- swapQueen(side) / swapDrone(side)
- getBeeProgress(side) / canWork(side)
- analyze(honeyslot)
- addIndustrialUpgrade(side) / getIndustrialUpgrade(side, slot) / removeIndustrialUpgrade(side, slot)

### configuratorUpgrade (oc:configuratorUpgrade) — EnderIO conduit control
All methods no-op with "EnderIO not loaded" if EnderIO is absent.
- getConduitConfiguration(side, conduitDirection)
- setItemConduitColor / setItemConduitOutputPriority / setItemConduitFilter / setItemConduitConnectionMode
- setItemConduitExtractionRedstoneColor / setItemConduitExtractionRedstoneMode
- setEnderLiquidConduitFilter / setEnderLiquidConduitColor / setLiquidConduitConnectionMode
- setLiquidConduitExtractionRedstoneColor / setLiquidConduitExtractionRedstoneMode
- setRedstoneConduitSignalColor / setRedstoneConduitSignalStrength
- replaceConduitFilter(side, dir, input) (robot only)

### rtgUpgrade (oc:rtgUpgrade) — passive power source, no API methods
Efficiency from config power.ritegEfficiency (default 0.6).

## New drivers (other mods' machines)
### crop — IC2 crops
getSize, getGrowth, getGain, getResistance, getNutrientStorage, getHydrationStorage,
getWeedExStorage, getHumidity, getNutrients, getAirQuality, getName, getRootsLength,
getTier, maxSize, canGrow, getOptimalHavestSize
(ConverterBaseSeed: a scanned IC2 BaseSeed -> crop table {name, tier, growth, gain, resistance})

### ic2_teleporter — IC2 teleporter
- setCoords(X, Y, Z)

### essentia_exportbus / essentia_importbus — TE essentia buses
Export: getExportConfiguration, setExportConfiguration, getExportSlotSize, getVoidAllowed, setVoidAllowed
Import: getImportConfiguration, setImportConfiguration, getImportSlotSize
Shared: getSlotSize, getPartConfig, setPartConfig

### extreme_autocrafter — Avaritia Addons (ghost slots 0-80)
- setGhostItem(slot, database, database_slot) / getGhostItem(slot)

## Modified existing components
### Transposer (new fluid-container methods)
- getContainerCapacityInSlot(side, slot) / getContainerLevelInSlot(side, slot) / getFluidInContainerInSlot(side, slot)
- transferFluidFromTankToContainer(...) / transferFluidFromContainerToTank(...) / transferFluidBetweenContainers(...) (return boolean, amount)

### Geolyzer
- scanUndergroundFluids() -> GregTech underground oil info {type, quantity}
- Scans of GT machines now include facing + sensorInformation

### GregTech
- Energy driver: getStoredEUString() / getEUCapacityString() (EU as unsigned string for very large values)
- DataStick converter parses GT "Recipe Generator" NBT: output, time, eu, inputItems, inputFluids

## Notes
- ae2fc (AE2 Fluid Craft): AE network fluid queries respect that mod's display blacklist.
- NEI: drag-and-drop items from NEI into the OC Database GUI (client QoL).
- EnderIO version constraint widened to @[2.2,).
- Upgrade slot availability: me/beekeeper upgrades -> robot + drone;
  configurator -> microcontroller; RTG -> robot / drone / microcontroller.
