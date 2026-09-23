
## Valheim server (valheim-server repo)

Installed from `valheim-server/claude/memory/srv-dev/` (a sibling clone at
`/srv/dev/repos/valheim-server`). These notes cover the modded Valheim dedicated server on
VM 100; edit them there and run that repo's `install.sh`. One line per memory.

- [Valheim config lives in valheim-server](valheim-config-lives-in-valheim-server.md) — Valheim config/units/skills/memory live in the valheim-server repo (sibling clone), not home-server; edit there + run its install.sh
- [Valheim server](valheim-server.md) — modded Valheim dedicated server (VM 100); drive via `qm guest exec`; on 1.0 with a reduced mod set
- [DropThat prefab dump](dropthat-prefab-dump.md) — how to dump prefab/drop-table ids safely (enable → generate → STOP, or it hogs the VM)
- [Mod update: halt before docs](mod-update-halt-before-docs.md) — adding/updating mods: after server is up + verified, stop for Ethan's OK before docs or client mod docs
- [Valheim mod inventory](valheim-mod-inventory.md) — list installed mods (required/optional + version): `valheim/list-installed-mods.sh`; the 4 Discord feeds incl. `hs-mod-announce` (agent-triggered mod-change diff via the announce-valheim-mods skill)
- [Valheim add-mod tooling](valheim-add-mod.md) — add/bump/remove a mod: the `/add-valheim-mod` skill + its scripts (`mod-fetch.sh`, `verify-boot.sh`, `lib-gx.sh`)
- [Valheim status edge notifier](valheim-status-edge-notifier.md) — up/down Discord posts are EDGE-triggered on start/stop (3-min probe) + daily heartbeat; why it's not a Claude hook
- [Read logs targeted](read-logs-targeted.md) — always read logs in slices (tail/grep), never the whole file (a full read can hang the VM 100 agent)
- [Valheim VM agent](valheim-vm-agent.md) — check the VM 100 guest agent with a real exec (ping false-negatives); wait out world-load, don't retry-hammer, reboot last
- [Valheim PlayFab relay wedge](valheim-playfab-relay-wedge.md) — clients drop right after connecting (code 4098 / ZRpc timeout, NOT mods) = wedged crossplay relay; restart the server to fix
