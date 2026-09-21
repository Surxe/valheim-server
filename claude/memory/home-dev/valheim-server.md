---
name: valheim-server
description: The modded Valheim dedicated server — where it runs, how to drive it, current state
metadata:
  type: project
---

Modded Valheim dedicated server "**BaldurianQuat**", hosted on this box in **Proxmox VM 100**
as a Docker container (`lloesche/valheim-server`, container name `valheim`). Crossplay-only
(PlayFab relay, no port forwarding); friends join by code + password.

**Operate it from `/home/dev` (no SSH to the guest):**
`sudo qm guest exec 100 -- /bin/bash -lc 'docker ... '` (guest agent runs as root; JSON out —
pipe through python3 for `out-data`). World + config bind-mounted at `/srv/valheim/config`
(precious) on the VM host; game install at `/srv/valheim/data` (throwaway).

**Repo:** `/srv/dev/repos/valheim-server/valheim/` — `docker-compose.yml`, `mods.manifest`,
`stage-mods.sh` (deploy mods to the VM), `check-mod-updates.sh` (poll Thunderstore),
`hooks/sync-plugins.sh` (PRE_SERVER_RUN_HOOK so auto-updates keep mods loaded).

**State (2026-09): on Valheim 1.0 (l-1.0.7, Unity 6).** Server plugins: **ModSentry 1.0.19 +
DropThat 3.1.5 + Jotunn 2.30.2 + BetterCarts 1.1.1 + OneMapToRuleThemAll 2.8.1 + GlassPieces 1.2.8 +
ConditionalConfigSync 1.0.9 + HarpoonExtended 1.2.0**
(Jotunn/DropThat on their 1.0 builds; Jotunn no longer crashes on connect). Bumped 2026-09-12: ModSentry
1.0.17 -> 1.0.18 (Valheim 1.0 migration), OneMapToRuleThemAll 2.8.0 -> 2.8.1 (fixes .explored
file pathing on the new 1.0 save format), FavoriteItems 1.1.0 -> 1.2.0 (optional ExtraSlots
special-slot protection, off by default).
**Bumped/added 2026-09-13:** ModSentry 1.0.18 -> **1.0.19** (auto-creates the ModSentry_Required/_Optional
folders at startup). **GlassPieces RE-ENABLED at 1.2.7** as `plugin+required` — blacks7ar finally shipped a
1.0 build (v1.2.6 "updated for valheim 1.0 deepnorth" cleared the old TypeLoadException, v1.2.7 fixed a
double-entry recipe); verified to load CLEAN on 1.0 (`Loading [GlassPieces 1.2.7]`, 0 errors). Content mod
(63 build pieces + a minable resource + collector; ServerSync + registers prefabs) so it loads server-side
AND every client must match — role corrected from the old disabled line's `required`-only to plugin+required.
NB per its v1.2.7 changelog the stale `/config/bepinex/blacks7ar.GlassPieces.cfg` must be deleted on apply so
the recipe fix takes (done; it regenerates). **Unshamed 1.0.4 (Azumatt)** added as a client-side **optional**
mod (ModSentry_Optional) — re-enables Steam achievements for players on our mods (patches the client
`Achievements.CanGetAchievements` to ignore the modded/cheat flags; does NOT touch the vanilla
`s_bypassCheatChecks` bypass, so spawned items stay flagged as normal). CLIENT-SIDE ONLY (no ServerSync,
nothing server-side): its `Azumatt.Unshamed.cfg` is per-client, NOT server-synced — can't be set server-side.
Per-client config `Enable Retroactive = true` grants already-earned achievements once; documented in
`client-modpack/INSTALL.md`. Steam-only (Xbox/Game Pass have their own achievement system). See [[valheim-add-mod]].
**Bumped/added 2026-09-21:** Jotunn 2.30.0 -> **2.30.2**, GlassPieces 1.2.7 -> **1.2.8** (audio fix;
also its FIRST live apply since the 2026-09-13 re-enable was staged-but-never-restarted — loads CLEAN
now), Unshamed 1.0.4 -> **1.0.5** (guide-text/explorer fixes). **HarpoonExtended 1.2.0 (shudnal) ADDED**
as `plugin+required` — pull movable targets to you / yourself to fixed targets, configurable damage/
distances + Feather Fall; confirmed 1.0/Deep North ready (changelog "Updated for Valheim 1.0.15"). Its
HARD DEP **ConditionalConfigSync 1.0.9 (shudnal)** added too (`plugin+required`), the standalone
ServerSync replacement Harpoon 1.2.0 switched to. GOTCHA: CCS ships **TWO** DLLs — the library
`ConditionalConfigSync.dll` AND the BepInEx entrypoint `ConditionalConfigSync.Plugin.dll` (GUID
`_shudnal.ConditionalConfigSync`) — BOTH must be staged (one manifest line each) or Harpoon dies with
"missing dependencies: _shudnal.ConditionalConfigSync" (hit this on the first boot). All verify-boot CLEAN.
TOOLING FIX: Jotunn 2.30.2's Thunderstore zip stores Windows backslash paths (`plugins\Jotunn.dll`), so
`unzip` warns + exits 1 and aborted `stage-mods.sh`/`mod-fetch.sh` under `set -e`; both now tolerate rc<=1
and find the DLL by basename regardless of `/`-or-`\` separator (stage-mods also compares the sha directly,
since `sha256sum -c` escapes backslash filenames). See [[valheim-add-mod]]. **BetterCarts** (TastyChickenLegs;
quick attach/detach, multi-player push, tunable cart weight/damage) `plugin+required`, deps only
BepInEx. Bumped 1.1.0 -> **1.1.1** on 2026-09-10 (latest release) — tested to load CLEAN on 1.0
(Harmony patches bind, its server ConfigSync RPC registers, no TypeLoad/MissingMethod). Its config
(`/config/bepinex/TastyChickenLegs.BetterCarts.cfg`, NOT repo-managed) is **Synced with Server**;
tuned 2026-09-10 (Ethan): `allowPlayersToHelp = true`, `maxPlayers = 4` (mod max), `includePuller
= false`, `playerMassReduction = 0.25`.
**OneMapToRuleThemAll 2.8.1** (DrummerCraig; shared map exploration/fog-of-war + player pins,
optional client radar) added 2026-09-10 (2.8.0), bumped 2.8.0 -> 2.8.1 on 2026-09-12 (fixes
.explored file pathing on the new 1.0 save format) as `plugin+required` — server-authoritative (pushes config
to clients on connect), deps only BepInEx (not Jotunn). Unlike Huginn it loads CLEAN on 1.0:
`58 Harmony patches applied, 0 skipped`, Fog/map-persistence init OK, no TypeLoad/Method-not-found.
DLL + SHA committed; in the client docs as required. Config tuned 2026-09-10 (Ethan) in
`/config/bepinex/drummercraig.one_map_to_rule_them_all.cfg` (server-synced, NOT repo-managed):
**radar OFF for everyone** (`[Server._Global] 5. Radar = false` — one master gate kills radar for
all creatures/ore/pickables/locations; the ~150 per-creature `_Vanilla.*.Radar` toggles are then
moot), shared map + auto-pin kept ON (`SharedMap`/`AutoPin = true`), auto-pin distances tightened
to fire only when close (`4. OreAutoPin`/`6. PickableAutoPin = Closest` 6m, `2. LocationAutoPin =
Closer` 12m). NB: its `[Server._*]` cfg keys carry a literal `N. ` numeric prefix (e.g. the key IS
`5. Radar`); `[Client]` keys are plain. Same edit-while-stopped rule as BetterCarts (synced cfg).
**FarmGrid 1.0.0 re-enabled** as a client-side **optional** mod (ModSentry_Optional) — verified
2026-09-10 to load clean under Jotunn 2.30.0 (Jotunn was its only blocker; no new FarmGrid
version needed). **FirstPersonMode 1.3.12 (Azumatt)** added 2026-09-11 as a second client-side
**optional** mod (ModSentry_Optional; moves the camera into the player's head — a per-player
preference, not server-loaded). Deps only BepInEx. Load-tested server-side on 1.0 before shipping
(staged as `plugin`, restarted, log clean: `Loading [FirstPersonMode 1.3.12]` + its ConfigSync RPC
registered, no TypeLoad/Method/Field errors), then restored to `optional`-only. DLL + SHA committed,
added to the client docs + INSTALL docs. **FavoriteItems 1.2.0 (ronaldoniz)** added 2026-09-12
as a third client-side **optional** mod (ModSentry_Optional; Alt-click marks inventory stacks as
favorites — golden star, quick-stack protection via a public API). Deps only BepInEx. **Client-only
by design** — `BepInProcess("valheim.exe")`, so BepInEx SKIPS it on the dedicated server; the
server-side load-test is N/A. Built 2026-09-11 against BepInEx 5.4.2350 (the 1.0 pack); verified
on a real client by Ethan 2026-09-12. Bumped 1.1.0 -> 1.2.0 on 2026-09-12 (optional ExtraSlots
1.2.3 special-slot protection via its public API, off by default). Still **disabled** (both tested 2026-09-10 on
their current versions and NOT ok — need a real 1.0 rebuild, not just Jotunn):
**GlassPieces 1.2.5** (still TypeLoadException/VTable on 1.0; depends only on BepInEx so Jotunn
never applied) and **Huginn Map 1.0.5** (now *loads* under Jotunn but its own map-share
`Minimap.ReadExploredArray` + boat `ZoneSystem.m_activeArea` calls hit 1.0-removed game APIs, so
its headline features are broken). **Favorite_Items 0.1.5 (Valheazy) DROPPED 2026-09-12** —
abandoned (last release 2026-02-23) and throws a TypeLoadException every FixedUpdate on 1.0
(missing inventory-UI type `Element`); superseded by ronaldoniz/FavoriteItems (see above). A daily
systemd job `hs-mod-check`
emails Ethan when a disabled mod updates. Difficulty is vanilla/Normal, no world modifiers.

**"Will a disabled mod work now that its dep updated?" test recipe:** stage it as a `plugin`
(server-side) in a scratch manifest, restart, and read `BepInEx/LogOutput.log` for the LATEST
boot (log is appended across restarts — anchor on the last `Chainloader started`). A
`TypeLoadException`/"could not be instantiated" at load = hard break (needs rebuild); a clean
`Loading [..]` with no errors = loads; `Method/Field not found` warnings = it loads but uses
game APIs 1.0 changed (functionally broken). Then restore + apply via `guests/vm-apply-valheim.sh`.
This reading is now scripted — `valheim/verify-boot.sh [--wait N] [--mod Name]` slices the latest
boot for you (plugins/errors/session, exit 0 = clean) — and the whole add/bump/remove flow is the
**`/add-valheim-mod`** skill (see [[valheim-add-mod]]).

**Gotchas:** VM is **6 cores** (was 4, was 3) — headroom so a mod/world-load that pegs the game
threads can't starve the guest agent (agent went unresponsive again during a 2026-09-10 apply
restart; bumped 4->6, host has 8. Recover: `qm shutdown --forceStop 1` (graceful ACPI still
flushes the world save even with the agent down) `/ qm set --cores / qm start`, then the instant
guest-exec answers on boot, `docker compose stop` to free CPU BEFORE staging, then start).
**RAM:** alloc is **4 GiB fixed** (balloon off); host is only 7.1 GiB, so 4 GiB is the safe
ceiling — bumping toward 5.5 would risk **host** OOM (which kills the whole VM), and the guest
isn't RAM-pressured anyway (~1.7 GiB free, container ~2.2 GiB). The guest has a **1.5 GiB
swapfile** (`/swapfile`, `vm.swappiness=10`) as an OOM cushion so a transient spike past 4 GiB
degrades instead of crashing the server; it's config-as-code in `guests/cloud-init-valheim.yaml`
(a rebuild reproduces it) and was applied live to the running VM to match. Do
NOT leave DropThat `WriteDropTablesToFiles` enabled — it pegs the server on world start (use it
briefly to dump prefab ids, then off).
**Bumping a mod version:** `stage-mods` reuses a cached zip in the VM's `/srv/valheim/mod-cache/`
if present, so a stale zip of the OLD version -> `SHA MISMATCH` on the new pin. `rm` that mod's
`mod-cache/<Name>.zip` (there is no `dll/` dir in the VM; DLLs are downloaded+verified there).
**Changing a Synced-with-Server mod cfg:** edit the `.cfg` while the server is **stopped**
(`supervisorctl stop valheim-server`), else the still-running instance flushes its in-memory
(old) value back over your edit on shutdown. Full detail: [[valheim-1.0-mod-status]],
[[valheim-server-ops]]. Snapshot before mod/game changes (`qm snapshot 100 ...`).
