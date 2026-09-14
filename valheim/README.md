# Valheim server — how it's configured from this repo

The Valheim server runs as a Docker container (`lloesche/valheim-server`) **inside VM 100**
(`valheim`), not on the Proxmox host. This repo is the source of truth for its config; the
files are deployed **into the VM**, because the VM is a separate guest with no repo checkout.

## Deploy model (repo → VM) — differs from the host

The host uses symlink-into-repo (see the home-server repo's `docs/04-repo-and-bootstrap.md`). The VM **cannot**
symlink into the host's repo, so config is **pushed into the VM** over the QEMU guest agent
(`qm guest exec` — no SSH needed). Live layout in the VM:

```
/srv/valheim/docker-compose.yml     <- valheim/docker-compose.yml
/srv/valheim/mods.manifest          <- valheim/mods.manifest
/srv/valheim/stage-mods.sh          <- valheim/stage-mods.sh
/srv/valheim/drop_that.drop_table.cfg <- valheim/drop_that.drop_table.cfg
/srv/valheim/drummercraig.one_map_to_rule_them_all.cfg <- valheim/drummercraig.one_map_to_rule_them_all.cfg
/srv/valheim/OneMapToRuleThemAll.catalog.txt <- valheim/OneMapToRuleThemAll.catalog.txt (staged into BepInEx/OneMapToRuleThemAll/)
/srv/valheim/config/                <- bind-mounted to the container /config (world + BepInEx)
/srv/valheim/data/                  <- bind-mounted to /opt/valheim (game + runtime BepInEx)
/etc/valheim/valheim.env            <- Ethan's values (see valheim.env.example); NOT in repo
```

## Applying a mod/config change

1. Edit the files here (`mods.manifest`, `dll/`, `drop_that.drop_table.cfg`,
   `drummercraig.one_map_to_rule_them_all.cfg`, `OneMapToRuleThemAll.catalog.txt`, `docker-compose.yml`).
2. From the Proxmox host: **`guests/vm-apply-valheim.sh`** — pushes the files into the VM,
   runs `stage-mods.sh`, and restarts the container. (Or do those three steps by hand.)
3. A restart rotates the crossplay join code — see `client-modpack/INSTALL.md`.
4. **Once verified stable**, announce the change on Discord: `announce-mod-change.sh --dry-run`
   to preview the diff, then `sudo systemctl start hs-mod-announce.service` to post it
   (added/bumped/removed, req/opt). Agent-triggered on purpose — see the `announce-valheim-mods`
   skill; the daily `hs-mod-list` full-inventory post is separate.

`stage-mods.sh` reads `mods.manifest`, verifies each DLL's SHA-256 (using `dll/` if present,
else downloading the pinned Thunderstore zip), and lays out the plugins + ModSentry policy.

## Layout facts that WILL trip you up (learned the hard way)

- **BepInEx config is a symlink.** In the container, `BepInEx/config` → `/config/bepinex`.
  So ModSentry's policy folders and mod cfgs live **directly under `/config/bepinex/`**
  (e.g. `/config/bepinex/ModSentry_Required/`), **NOT** under `/config/bepinex/config/`.
  Putting them a level too deep = ModSentry sees no policy ("server has nothing").
- **Plugins are copied, not symlinked, and lloesche syncs them ADDITIVELY.** `stage-mods.sh`
  therefore *mirrors* `/config/bepinex/plugins` into the runtime tree
  (`/srv/valheim/data/bepinex/BepInEx/plugins`) so removed mods don't linger and the tree
  is never left empty (empty tree = 0 plugins = ModSentry off).

## What loads where (mods.manifest roles)

- **`plugin`** — loaded on the server (`BepInEx/plugins/`).
- **`required` / `optional`** — client DLL hash references (`ModSentry_Required/`,
  `ModSentry_Optional/`) that ModSentry compares each client against.

Server-loaded plugins (Valheim 1.0): **ModSentry, DropThat, Jotunn, BetterCarts,
OneMapToRuleThemAll** (BetterCarts and OneMapToRuleThemAll both have server-authoritative config
sync, so they're loaded server-side and required on clients; OneMap loads clean on 1.0 — 58
Harmony patches applied, 0 skipped — unlike Huginn).
**Huginn is currently disabled** (loads on 1.0 but its map-share/boat features are broken — see `mods.manifest`), so
it is not loaded right now; the rationale below is why it must be a server `plugin` **when
re-enabled**. Two non-obvious points:

- **Jotunn** must be loaded server-side so ModSentry can reflect the Jotunn-dependent policy
  DLLs (e.g. Huginn) when building the policy.
- **Huginn** (when enabled) must be loaded server-side because it enforces **Jotunn
  NetworkCompatibility** (`EveryoneMustHaveMod`): if a client has Huginn and the server
  doesn't, Jotunn rejects the client with *"Client loaded additional mod: Huginn Map"* — a
  separate layer from ModSentry. FarmGrid is also Jotunn-based but does **not** enforce compat,
  so it stays client-side/optional.

Rule of thumb: **any Jotunn mod that enforces NetworkCompatibility must be a server `plugin`,
not just a policy reference.** (Loading a client-only map mod like Huginn on the headless
server is harmless — it logs one swallowed `ArgumentNullException` building its map UI, then
reports "Huginn active".)

## Values, secrets, backups, clients

- **Values:** `/etc/valheim/valheim.env` in the VM (server/world name + password). Template: `valheim.env.example`.
- **Secrets:** none in this repo. Restic/B2 in `/etc/home-server/backup.env` (host + VM).
- **Backups:** whole-VM vzdump runs on the host; the offsite **B2 world backup runs inside the
  VM** (`backup/valheim-b2-world.{service,timer}` + `../backups/restic-b2-world.sh`). See the home-server repo's `docs/03-backups.md`.
- **Guest creation:** `../guests/create-valheim-vm.sh` + `cloud-init-valheim.yaml`.
- **Client mods (docs):** `client-modpack/` (required/optional mod list + install guide; the server enforces the set via ModSentry).

Authoritative mod manifest: Ethan's `valheim-mods/SERVER-HANDOFF.md`.
