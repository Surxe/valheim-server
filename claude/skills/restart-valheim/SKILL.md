---
name: restart-valheim
description: >-
  Restart the Valheim dedicated server (VM 100). Use when asked to restart/reboot the
  Valheim server or reload its mods, or when the status feed reports it FROZEN. Picks
  between an in-place world restart via the guest agent (fast; the PRE_SERVER_RUN_HOOK
  re-syncs staged mods, so this is also how a mod/config change is applied) and a full
  container restart (for a wedged supervisord or an env change). Not for restarting the
  whole VM.
---

# Restart the Valheim server

## Step 0: world restart or container restart?

Pick one before running anything. If the request already makes it obvious, say which one
you're doing and why. If not, ask Ethan with your recommendation.

| | World restart (in place) | Container restart |
|---|---|---|
| What restarts | just the `valheim-server` process, via supervisord | the whole `valheim` container (supervisord, updater, backup, server) |
| Time to back up | ~40-60s | several minutes: the container start runs a steamcmd update check (and downloads any game update) before the server launches |
| Use for | mod/config change, routine restart, a crashed or misbehaving game | the status feed says **FROZEN**, `supervisorctl` hangs or times out, or a `docker-compose.yml` / env change |

Quick test that decides it: run
`timeout 20 docker exec valheim supervisorctl status`
(inside the VM, see the commands below). Exit 3 is normal (`valheim-bootstrap` shows
EXITED). Only a hang (exit 124) matters: then supervisord is wedged, a world restart will
hang too, and you need a container restart.

## World restart

```
sudo qm guest exec 100 --timeout 75 -- /bin/bash -lc 'timeout 60 docker exec valheim supervisorctl restart valheim-server; echo rc=$?'
```

`rc=124` means supervisord didn't answer, so switch to a container restart.

## Container restart

```
sudo qm guest exec 100 --timeout 200 -- /bin/bash -lc 'timeout 180 docker restart valheim; echo rc=$?'
```

`docker restart` can take longer than its timeout to return while the old container is
torn down; check `docker ps` before retrying. Don't fire it twice. A second restart only
restarts the update download.

## Confirm it's back

Get the new join code (it can rotate on every restart) once it's back up:

```
sudo qm guest exec 100 -- /bin/bash -lc "docker exec valheim grep 'is active with' /opt/valheim/bepinex/BepInEx/LogOutput.log | tail -1"
```

The log file isn't rotated until the new server starts writing, so check the date on that
line. A line from before the restart is stale, so keep waiting.

Notes:
- `qm guest exec` returns JSON. Pipe it through `python3 -c 'import sys,json;print(json.load(sys.stdin)["out-data"])'` to read the output.
- Healthy = today's "Session ... is active with N player(s)".
- To restart the VM use `qm reboot 100`. That isn't covered by this skill.
- **If this restart was to apply a mod add/update/removal:** once it's back up and verified
  stable, announce the new mod list on Discord. See the `announce-valheim-mods` skill.
