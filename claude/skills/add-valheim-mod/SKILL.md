---
name: add-valheim-mod
description: >-
  Add, version-bump, or remove a Valheim server mod (mods.manifest). Use when asked to add /
  update / remove a mod, or enable a disabled one. Orchestrates the standard flow — vet, edit,
  snapshot, load-test on 1.0, apply, verify, announce — calling the scripts that do the work.
---

# Add / bump / remove a Valheim mod

Standard flow for a `mods.manifest` change. The scripts do the mechanics; your judgement is
role, whether it loads clean, and whether to ship. Run from the Proxmox host (root/sudo).
Repo: `/srv/dev/repos/valheim-server/valheim`.

## 1. Vet + stage the DLL
```
valheim/mod-fetch.sh <thunderstore-url | Author Package [version]>
```
Resolves the version, downloads it, drops the DLL in `dll/`, prints SHA-256, **dependencies**
(flags anything beyond BepInEx — that dep must be in the set too), CHANGELOG head, and a
ready-to-paste manifest line with a `ROLE` placeholder.

## 2. Pick the role, edit the manifest
Fill `ROLE` in the `name|version|dll|sha256|ROLE|url` line and add it to `mods.manifest` with a
one-line comment (what/why, deps, load-test result). Roles:
- `plugin` — loaded on the server. Needed for server-authoritative mods (config sync, world/loot).
- `required` — every client must run it (ModSentry kicks a mismatch). Usually with `plugin`.
- `optional` — client-side, allowed but not required (e.g. a camera/UI preference). Not loaded
  server-side.  Combine with `+` (e.g. `plugin+required`).

## 3. Snapshot
```
sudo qm snapshot 100 pre_<mod>_<yyyymmdd> --description "..."
```

## 4. Load-test on 1.0 (the important gate)
A mod that throws a `TypeLoadException` on 1.0 breaks clients too, not just the server (cf.
the dropped Valheazy Favorite_Items). So confirm it loads clean **before** shipping — even a client-only mod:
temporarily give the line role `plugin` (a scratch edit), apply, then check the latest boot.
```
sudo guests/vm-apply-valheim.sh          # push + stage + restart
sudo valheim/verify-boot.sh --wait 55 --mod <DisplayName>
```
`--mod` takes the BepInEx display name as it appears in the log (may differ from the package
name). Clean = its `Loading [..]` line present, no `TypeLoad/Method/Field/Exception`. If it
fails, roll back (`qm rollback 100 <snap>`) — do not ship. Then revert the scratch role to its
real value. (`stage-mods.sh` wipes all plugin dirs each run, so a leftover test plugin can't linger.)

**Client-only mod that sets `BepInProcess("valheim.exe")`** (e.g. ronaldoniz/FavoriteItems): BepInEx
logs `Skipping [X ...] because of process filters (valheim.exe)` and never emits a `Loading [..]`
line on the server. That's EXPECTED, not a load failure — such a mod can't load server-side by
design, so the `Loading [..]` gate is N/A. Treat "Skipping ... process filters" as clean (not a
TypeLoad/Method/Field error); the real gate is a client smoke test. Keep its role `optional`
(client-side), not `plugin`.

## 5. Apply the real config + verify
```
sudo guests/vm-apply-valheim.sh
sudo valheim/verify-boot.sh --wait 55     # exit 0 = clean & session active
```

## 6. Client docs (if the mod is `required` or `optional`)
Edit the **mod table** in `client-modpack/INSTALL.md` — one row per mod (version +
Thunderstore package + ✅/➖/❌). That table is the single source of truth; the surrounding
prose doesn't name individual mods, so nothing else needs syncing (`README.md` just points at
the table). There is no modpack zip or build script — the server enforces the set via ModSentry.

## 7. Memory + announce + PR
- Update the `valheim-server` memory (state line), then install it: see
  [valheim-server-install](../valheim-server-install/SKILL.md).
- Announce the change on Discord once verified stable: see
  [announce-valheim-mods](../announce-valheim-mods/SKILL.md).
- Branch off `main`, commit, open a brief PR.

## Gotchas
- Bumping a version: clear the VM's stale cached zip or you get `SHA MISMATCH` —
  `sudo qm guest exec 100 -- bash -lc 'rm -f /srv/valheim/mod-cache/<Name>.zip'`.
- Full server/VM detail and the mod-status history live in the `valheim-server` memory.
