---
name: dropthat-prefab-dump
description: Safely dump Valheim prefab / drop-table ids via DropThat without hogging the VM
metadata:
  type: reference
---

To get the current prefab / drop-table id list (e.g. after a Valheim update, to re-verify
`drop_that.drop_table.cfg`): set `WriteDropTablesToFiles = true` in the **[Debug]** section of
`/srv/valheim/config/bepinex/drop_that.cfg` and restart the server. It writes the files on
world start — **then STOP the server immediately.** With the setting left on, DropThat pegs
all game threads right after generating the files and hogs the whole VM (it starved the guest
agent and forced a hard reset on 2026-09-10, before the VM got its 4th core).

Procedure: enable → start → files appear in `BepInEx/Debug/` → **stop server / set back to
`false`**. Output files (VM 100): `/srv/valheim/data/bepinex/BepInEx/Debug/drop_that.drop_table.{prefabs,locations,dungeons}.txt`
(last capture preserved at `/srv/valheim/dropthat-prefab-dump/`). See [[valheim-server]].
