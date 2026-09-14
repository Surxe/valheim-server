---
name: valheim-playfab-relay-wedge
description: Clients drop right after connecting (not a mod issue) — the PlayFab crossplay relay wedged; restart the server to fix
metadata:
  type: feedback
---

Symptom: clients handshake and pass the mod check, then get dropped within seconds, over and
over. In `LogOutput.log` / container stdout: `PlayFab network error ... code '4098': the
operation was called with an invalid handle`, `Failed to send, suspend TX ... while trying to
reconnect`, `ZRpc timeout detected`, `ZPlayFabSocket::Dispose ... CLOSED`.

**Not a mod problem** — ModSentry logs `Client plugin inventory accepted` on each attempt. Rule
mods out first: a real mismatch is an inventory *reject* with no handshake.

**Why:** the server's PlayFab crossplay relay socket got a stale/invalid handle and never cleanly
reconnects. Often kicked off by a brief **wifi uplink** blip (`home-server-wifi.service`) the
session can't recover from — check host uplink, but it usually tests clean by the time you look.

**How to apply:** restart the game server via [[restart-valheim]] (`supervisorctl restart
valheim-server`) — tears down the stale socket, registers a fresh PlayFab session, clients stick.
Join code is tied to the world (751937), does **not** rotate on restart. See [[valheim-server]].
