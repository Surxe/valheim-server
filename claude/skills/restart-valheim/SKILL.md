---
name: restart-valheim
description: >-
  Restart the Valheim dedicated server (VM 100). Use when asked to restart/reboot the
  Valheim server or reload its mods. In-place server restart via the guest agent — the
  PRE_SERVER_RUN_HOOK re-syncs staged mods, so this is also how a mod/config change is
  applied. Not for restarting the whole VM.
---

# Restart the Valheim server

In-place restart of the game server (fast; re-syncs staged mods via the hook):

```
sudo qm guest exec 100 -- /bin/bash -lc 'docker exec valheim supervisorctl restart valheim-server'
```

Then get the new join code (it rotates on every restart) once it's back up:

```
sudo qm guest exec 100 -- /bin/bash -lc "grep 'is active with' /opt/valheim/bepinex/BepInEx/LogOutput.log | tail -1"
```

Notes:
- `qm guest exec` returns JSON — pipe through `python3 -c 'import sys,json;print(json.load(sys.stdin)["out-data"])'` to read output.
- Give it ~40–60s to come back (world load + PlayFab). Healthy = "Session ... is active with N player(s)".
- If the whole container needs a restart (env change) use `docker restart valheim`; to restart the VM use `qm reboot 100` — not this skill.
- **If this restart was to apply a mod add/update/removal:** once it's back up and verified
  stable, announce the new mod list on Discord — see the `announce-valheim-mods` skill.
