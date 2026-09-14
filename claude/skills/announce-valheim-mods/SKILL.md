---
name: announce-valheim-mods
description: >-
  Announce a Valheim mod-set change on the #valheim-server-status Discord channel: a diff of
  what was added / version-bumped / removed / had its role changed (each labelled
  required/optional), computed automatically from mods.manifest. Use ONLY once the change is
  applied AND the server is verified stable (healthy + plugins loaded clean), so you announce
  a set that's really running. Can also post the full installed-mod list.
---

# Announce a Valheim mod change on Discord

When the mod set changes (a mod added, version-bumped, disabled, or removed via
`mods.manifest`), post a **change announcement** so the channel reflects it as soon as it's
actually live — rather than waiting up to ~24h for the daily `hs-mod-list.timer` (09:10) to
post the routine full inventory.

This is **AI-orchestrated on purpose.** The diff is fully programmatic — `announce-mod-change.sh`
computes it from `mods.manifest` vs a saved baseline — but *when* to fire it is a judgement a
script can't make: only once the new mod version has been verified to actually load and run.
So do this **only after the server is verified stable from the restart** — otherwise you'd
announce a set that isn't really running (e.g. a plugin that failed to load and got rolled
back). The post reads `mods.manifest` (host source of truth), so it's independent of live
server state; the stability gate is about *truthfulness*, not a technical dependency.

## Preconditions — all must hold before you post

1. **The mod change is applied.** `mods.manifest` edited, staged to the VM, and the server
   restarted to pick it up — see [restart-valheim](../restart-valheim/SKILL.md) and
   `valheim/stage-mods.sh` / `guests/vm-apply-valheim.sh`.
2. **The server is up and healthy.** The log shows a recent
   `Session ... is active with N player(s)` (the restart-valheim health check).
3. **It's actually stable, not crash-looping.** Wait ~60–90s after "active" and confirm it's
   *still* up, and that the changed plugin(s) loaded clean on the **latest** boot — no
   `TypeLoadException` / "could not be instantiated" / `Method/Field not found` in
   `BepInEx/LogOutput.log` for the last `Chainloader started`. (Per the mod-test recipe in the
   `valheim-server` memory.) If any of these fail, **fix or roll back first — do not post.**

## Post it — the change announcement (primary)

The right post for "we changed the mods" is the **diff** — what was added / version-bumped /
removed / had its role changed since the last announcement, each labelled
required / optional / server-only. `announce-mod-change.sh` computes that diff automatically
(current `mods.manifest` vs a saved baseline in
`/var/lib/home-server/valheim-mod-announce.json`), so the only judgement left to you is the
one a script can't make: **whether the change is verified working** (the preconditions above).
That's why there is deliberately **no timer** for it — you trigger it.

**Preview the diff first** (read-only, never posts, never touches the baseline):

```
/srv/dev/repos/valheim-server/valheim/announce-mod-change.sh --dry-run
```

If that shows the change you expect, fire the oneshot unit — it loads the webhook from
`/etc/home-server/discord-server-status.env` and runs `announce-mod-change.sh --post`, so you
never handle the secret. On a confirmed post it saves the new baseline (so a re-run posts
nothing — no double-announce):

```
sudo systemctl start hs-mod-announce.service
journalctl -u hs-mod-announce.service -n 10 --no-pager
```

Success looks like `mod-announce: posted N change(s) …; baseline saved.` Other outcomes:
- `no changes since last announcement` — the baseline already matches (nothing to post; the
  change was already announced, or the manifest wasn't actually edited).
- `DISCORD_WEBHOOK_URL not set` / `would have posted …` — the webhook env isn't staged. The
  baseline is left untouched, so it'll announce once staged. Unverified/leave-for-Ethan state,
  not a failure to retry.

## Post the full inventory instead (optional)

If you'd rather post the **entire** current mod list (not just the diff) — e.g. re-baselining a
channel, or the daily-cadence style — use the full-list unit:

```
sudo systemctl start hs-mod-list.service          # runs list-installed-mods.sh --post
journalctl -u hs-mod-list.service -n 10 --no-pager
/srv/dev/repos/valheim-server/valheim/list-installed-mods.sh   # read-only preview
```

## Notes

- One webhook (`#valheim-server-status`) is shared by all the Valheim feeds; this post is a
  normal embed on that channel. The change announcer is self-deduping — it diffs against a saved
  baseline and posts nothing when there's no change — so re-running it is harmless (unlike the
  full-list post, which always posts).
- This is a Claude/host action driven by the manifest, so it also covers a change Ethan or a
  script made to `mods.manifest` — if the manifest changed and the server's stable, it's
  postable regardless of who edited it.
- Don't confuse this with `hs-mod-check-discord` (the daily *update-available* alert): that
  fires **before** a change, when Thunderstore has a newer version we haven't applied; this
  fires **after** we apply and verify one.
- **Role ping (optional):** if `MOD_ANNOUNCE_ROLE_IDS` is set in
  `/etc/home-server/discord-server-status.env` (comma-separated Discord role IDs, e.g. the
  "valheim server" role), the announcement @-pings those roles — and *only* those (never
  @everyone). Unset = no ping. It's config, not code: get an ID via Discord Developer Mode →
  right-click role → Copy Role ID, then stage it in that env file. `--dry-run` and the service
  log both say whether a ping will fire, so you can confirm before/after posting.
- If the baseline ever drifts (e.g. a change was applied but never announced, and you don't want
  to post it retroactively), reset it silently with
  `announce-mod-change.sh --baseline` (via `MOD_ANNOUNCE_STATE_FILE`-aware root run / the
  installer seeds it the same way).
