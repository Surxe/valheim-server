---
name: valheim-mod-inventory
description: List the currently installed Valheim mods (required/optional + version) — the manual command
metadata:
  type: reference
---

To see what mods are installed on the Valheim server right now, grouped by ModSentry role
(required / optional / server-only) with each mod's version, run on the host:

```
/srv/dev/repos/valheim-server/valheim/list-installed-mods.sh
```

It prints a table (read-only). Source of truth is `valheim/mods.manifest` — the enabled
(non-commented) lines are what `stage-mods.sh` deploys, so under the repo==live invariant
they ARE what's installed; commented-out mods (disabled, waiting on a 1.0 build) are excluded.
The BepInEx pack is provided by the lloesche image and isn't listed.

Add `--post` to send the list to Discord (`list-installed-mods.sh --post`, needs
`DISCORD_WEBHOOK_URL`). That's what the daily systemd timer **`hs-mod-list.timer`** (09:10)
does automatically, posting to the **#valheim-server-status** channel webhook
(`/etc/home-server/discord-server-status.env`). That one webhook is shared by all four
Valheim Discord feeds:
- `hs-valheim-status` — up/down, EDGE-triggered on start/stop via `hs-valheim-status-edge.timer`
  + a daily heartbeat (see [[valheim-status-edge-notifier]]);
- `hs-mod-list` — this daily FULL inventory;
- `hs-mod-check-discord` — a mod version-update is *available* on Thunderstore but NOT applied
  yet (fires **before** a change);
- `hs-mod-announce` — a "we changed the running set" **diff** announcement (added / bumped /
  removed / role-changed, each labelled required/optional), fired **after** a change is applied
  and verified. It's **agent-triggered, no timer** (`sudo systemctl start hs-mod-announce.service`
  → `valheim/announce-mod-change.sh --post`); the WHEN is the judgement a script can't make.
  Run by the **`announce-valheim-mods` skill**. Preview with `announce-mod-change.sh --dry-run`;
  it diffs `mods.manifest` against a baseline at `/var/lib/home-server/valheim-mod-announce.json`
  (seeded by `systemd/install.sh`, saved on each post, resettable with `--baseline`).
  **Role ping:** set `MOD_ANNOUNCE_ROLE_IDS` (comma-separated Discord role IDs) in the same
  env file to @-ping role(s) — e.g. the "valheim server" role — on each announcement; only
  those roles ping (never @everyone), unset = no ping. It's server-specific config (get the ID
  via Discord Developer Mode → Copy Role ID), so it lives in the env file, not the repo.

See [[valheim-server]].
