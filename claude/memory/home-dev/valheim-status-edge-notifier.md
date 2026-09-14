---
name: valheim-status-edge-notifier
description: Valheim up/down Discord notifier is EDGE-triggered (posts on start/stop) + a daily heartbeat — how it works and why it's not a Claude hook
metadata:
  type: project
---

The Valheim server-status Discord feed announces **start/stop by watching the server's real
state**, not by hooking any command. `valheim/server-status-discord.sh` has two modes:

- **`--edge`** — driven by **`hs-valheim-status-edge.timer`** every **3 min** (`OnCalendar=*:0/3`).
  Does a **cheap probe** (`qm status` + one `docker inspect -f {{.State.Running}}`, no log
  parse) and posts **only when up/down changed** vs the state file. The expensive player-name
  log parse runs **only when it's actually about to post**, so 3-min polling stays light on the
  guest agent (the agent-overload gotcha in [[valheim-server]]).
- **`--heartbeat`** (default, no arg) — driven by **`hs-valheim-status.timer`** **daily** at
  09:07. Posts current status unconditionally (liveness) and re-baselines the edge state.
  (Was hourly for both; hourly heartbeats were pure noise once edge existed.)

**State file:** `/var/lib/home-server/valheim-status.state` (persists across reboots; holds
`up`/`down`). Override with `VALHEIM_STATUS_STATE_FILE`. Edge behaviour:
- first run / missing state → **initialize baseline silently, no post** (so a deploy or a wiped
  state file doesn't spam a phantom "UP");
- `unknown` (guest agent didn't answer) → **no post, keep last baseline** (won't flap on a
  transient hiccup — only confident up↔down transitions post);
- unchanged → no post.

**Host health is folded into this same script/units** (2026-09): each run also consults
`host/hs-health.sh --line --no-guest` (see [[host-health]]). `--heartbeat` appends a
host-health snapshot as a **second embed** to the daily post; `--edge` posts a host-health
alert **only when health crosses the CRIT boundary** (enter CRIT / recover) — WARN is
heartbeat-only to avoid 3-min flap near thresholds. It's a **separate edge state** from
Valheim up/down: `/var/lib/home-server/host-health.state` (`ok`/`warn`/`crit`), independent
of `valheim-status.state`, so the two concerns post independently. `--no-guest` on the health
probe keeps the frequent path from making a second guest-agent call. Rationale for folding it
in here (vs its own `hs-health.timer`): one feed, one webhook, reuse the edge+heartbeat machinery.

All Discord feeds still share the one **#valheim-server-status** webhook
(`/etc/home-server/discord-server-status.env`, root-only). Both status units use it via
`EnvironmentFile=-` (optional: logs "not set" and exits 0 until staged). Units are linked by
`systemd/install.sh` (in its `UNITS`+`TIMERS`), which `enable --now`s both timers.

**Why NOT a Claude Code `settings.json` hook for start/stop** (this was considered and
rejected 2026-09-10): a Claude hook fires only for a start/stop typed **in a Claude session**,
fires the instant the Bash tool returns — **before** the ~40–60s the server needs to be healthy
— and never sees restarts done by cron/systemd, Ethan by hand, or the mod
`PRE_SERVER_RUN_HOOK` auto-restart. The start/stop command is also a nested
`qm guest exec … 'docker … supervisorctl …'` string with no stable signature to match.
Watching real state (this notifier) covers **every** cause and only says UP once it's truly up.
So: **don't add that hook.** If start/stop announcements ever look wrong, fix them here.

**Testing without spamming the channel:** run the script directly with the webhook unset (it's
only in the root-only env file, so a plain `sudo` run doesn't have it) — it takes the "would
have posted …" branch, exercising probe + gating + state writes but not hitting Discord. Point
`VALHEIM_STATUS_STATE_FILE` at a scratch path and pre-seed it (`echo down > …`) to simulate a
transition. See [[valheim-mod-inventory]] (the shared webhook + the other two feeds) and
[[valheim-server]].
