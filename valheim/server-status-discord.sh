#!/usr/bin/env bash
# server-status-discord.sh — post Valheim server status (up/down + players, WITH NAMES)
# AND the Proxmox HOST's health to a Discord webhook. Two modes:
#
#   --edge       (frequent poll, every few min via hs-valheim-status-edge.timer)
#                Post ONLY on a CHANGE: (a) Valheim up/down flipped (the "someone ran
#                start/stop" notifier), and/or (b) host health crossed the CRIT boundary
#                (entered CRIT, or recovered out of it). Quiet otherwise. Watches real
#                state, so it doesn't care who cycled the server (Claude, cron, the mod
#                PRE_SERVER_RUN_HOOK, or Ethan by hand).
#   --heartbeat  (default; daily via hs-valheim-status.timer)
#                Post current status unconditionally — a liveness "yes, still here" that
#                carries BOTH the Valheim status and a host-health snapshot, and re-baselines
#                the edge state for both.
#
# WHY host health is folded in HERE rather than its own timer: it reuses the exact edge
# (alert-on-change) + heartbeat (daily liveness) machinery and the one #valheim-server-status
# webhook, so there's a single feed to watch. Health facts come from host/hs-health.sh
# (`--line` => "LEVEL | metrics — issues", exit 0/1/2); see the `host-health` memory.
# Only the CRIT boundary is edge-alerted — WARN would flap near thresholds, so WARN shows
# up in the daily heartbeat only.
#
# WHY edge instead of a Claude Code hook: a Claude hook only fires for a start/stop typed
# in a Claude session, fires the instant the command returns (before the ~40-60s the
# server needs to be healthy), and can't see restarts done by cron/systemd/the auto-update
# hook. Watching real state here covers every case and only announces UP once it's truly up.
# See the `valheim-status-edge-notifier` memory.
#
# Runs on the Proxmox HOST as root, reaching the guest over the QEMU agent (no SSH). This
# crossplay server answers neither an external A2S query nor the lloesche STATUS_HTTP
# endpoint, so count + names come from the server's own log (pure parsing):
#   * count = latest "Connections N ZDOS:.." line (logged ~every 10 min; the post shows
#     its "as of" time so staleness is visible).
#   * names = replay of "Got character ZDOID from <name> : <peerid>:.." (join) minus
#     "Destroying abandoned non persistent zdo <peerid> .. owner <peerid>" (leave), reset
#     whenever a "Connections 0" proves the server was empty.
# Edge polls do a CHEAP probe first (qm status + one `docker inspect`, no log parse) and
# only do the expensive name-gather when they're actually about to post, so polling every
# few minutes stays light on the guest agent. The health probe on the edge path runs
# --no-guest for the same reason (no second guest-agent call every few minutes).
#
# The webhook URL is a secret, NOT in the repo. The services pull it from
#   /etc/home-server/discord-server-status.env   (root:root 0600, see *.env.example)
# via EnvironmentFile:
#   DISCORD_WEBHOOK_URL              (required to post)
#   VALHEIM_VMID (default 100)   VALHEIM_CONTAINER (default valheim)   [optional overrides]
#   VALHEIM_STATUS_STATE_FILE (default /var/lib/home-server/valheim-status.state)
#   HOST_HEALTH_STATE_FILE    (default /var/lib/home-server/host-health.state)
#   HS_HEALTH                 (default <repo>/host/hs-health.sh)
#
# Exit codes: 0 = ok (posted, skipped-no-change, initialized baseline, or webhook
#             unconfigured -> logged and skipped);   1 = a webhook POST itself failed.
set -euo pipefail

: "${VALHEIM_VMID:=100}"
: "${VALHEIM_CONTAINER:=valheim}"
: "${VALHEIM_STATUS_STATE_FILE:=/var/lib/home-server/valheim-status.state}"
: "${HOST_HEALTH_STATE_FILE:=/var/lib/home-server/host-health.state}"

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
: "${HS_HEALTH:=$HERE/../host/hs-health.sh}"

MODE=heartbeat
case "${1:-}" in
  --edge)              MODE=edge ;;
  --heartbeat|""|-h)   MODE=heartbeat ;;
  *) echo "server-status-discord.sh: unknown arg: $1 (use --edge or --heartbeat)" >&2; exit 2 ;;
esac

export VALHEIM_VMID VALHEIM_CONTAINER VALHEIM_STATUS_STATE_FILE
export HOST_HEALTH_STATE_FILE HS_HEALTH
export VALHEIM_STATUS_MODE="$MODE"

python3 - <<'PY'
import os, re, json, subprocess, urllib.request, urllib.error

VMID       = os.environ.get("VALHEIM_VMID", "100")
CONTAINER  = os.environ.get("VALHEIM_CONTAINER", "valheim")
WEBHOOK    = os.environ.get("DISCORD_WEBHOOK_URL")
MODE       = os.environ.get("VALHEIM_STATUS_MODE", "heartbeat")
STATE_FILE = os.environ.get("VALHEIM_STATUS_STATE_FILE",
                            "/var/lib/home-server/valheim-status.state")
HEALTH_STATE_FILE = os.environ.get("HOST_HEALTH_STATE_FILE",
                                   "/var/lib/home-server/host-health.state")
HS_HEALTH  = os.environ.get("HS_HEALTH", "")

def run(cmd, timeout):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None
    except Exception:
        return None

def guest_out(cmd, timeout):
    """Run a shell command inside the guest via the QEMU agent; return its stdout ('' on fail)."""
    r = run(["qm", "guest", "exec", VMID, "--", "/bin/bash", "-lc", cmd], timeout)
    if r and r.returncode == 0:
        try:
            return json.loads(r.stdout).get("out-data", "") or ""
        except Exception:
            return ""
    return ""

# --- cheap probe: coarse up/down/unknown WITHOUT the expensive log parse ----------------
def cheap_state():
    """Return one of 'up' | 'down' | 'unknown' using only quick calls."""
    r = run(["qm", "status", VMID], 30)
    vm_state = "unknown"
    if r and r.returncode == 0:
        parts = r.stdout.split()          # "status: running"
        if len(parts) >= 2:
            vm_state = parts[1].strip()
    if vm_state != "running":
        # A confidently-off VM (stopped/paused/…) is DOWN; a failed qm call is unknown.
        return "down" if vm_state != "unknown" else "unknown"
    cs = guest_out('docker inspect -f "{{.State.Running}}" %s 2>/dev/null || echo error'
                   % CONTAINER, 30).strip()
    if cs == "true":
        return "up"
    if cs == "false":
        return "down"
    return "unknown"                       # guest agent didn't answer / docker error

def read_file(p):
    try:
        with open(p) as f:
            return f.read().strip() or None
    except Exception:
        return None

def write_file(p, s):
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(s + "\n")
    except Exception as e:
        print("status: WARN could not write state file %s: %s" % (p, e))

def read_last():   return read_file(STATE_FILE)
def write_state(s): write_file(STATE_FILE, s)

# --- host health (delegated to host/hs-health.sh --line) --------------------------------
LVLNAME = {0: "ok", 1: "warn", 2: "crit"}
def host_health(no_guest=True):
    """Run hs-health.sh --line; return (level 0/1/2, text). (-1, '') if unavailable."""
    if not HS_HEALTH or not os.path.exists(HS_HEALTH):
        print("host-health: hs-health.sh not found at %r — skipping" % HS_HEALTH)
        return (-1, "")
    cmd = [HS_HEALTH, "--line", "--no-color"] + (["--no-guest"] if no_guest else [])
    r = run(cmd, 60)
    if r is None:
        print("host-health: hs-health.sh timed out — skipping")
        return (-1, "")
    lines = [l for l in (r.stdout or "").splitlines() if l.strip()]
    text = lines[-1] if lines else ""
    lvl = r.returncode if r.returncode in (0, 1, 2) else -1
    return (lvl, text)

# --- full Valheim status (expensive: player count + NAMES from the log) -----------------
def full_status():
    """Return (headline, color, detail, players_txt, state_key, server_name)."""
    r = run(["qm", "status", VMID], 30)
    vm_state = "unknown"
    if r and r.returncode == 0:
        parts = r.stdout.split()
        if len(parts) >= 2:
            vm_state = parts[1].strip()

    server_name = None
    container_running = None
    players = None
    players_asof = None
    player_names = []
    if vm_state == "running":
        guest_cmd = (
            'sn=$(docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" %s 2>/dev/null '
            '| sed -n "s/^SERVER_NAME=//p"); echo "SERVER_NAME=$sn"; '
            'cs=$(docker inspect -f "{{.State.Running}}" %s 2>/dev/null || echo error); '
            'echo "CONTAINER=$cs"; '
            'docker logs %s 2>&1 | grep -E "Got character ZDOID from |'
            'Destroying abandoned non persistent zdo [0-9]+:[0-9]+ owner [0-9]+|'
            'Connections [0-9]+ ZDOS" | tail -4000'
            % (CONTAINER, CONTAINER, CONTAINER)
        )
        out = guest_out(guest_cmd, 90)
        online = {}          # peerid -> name
        for line in out.splitlines():
            if line.startswith("SERVER_NAME="):
                server_name = line.split("=", 1)[1].strip() or None
                continue
            if line.startswith("CONTAINER="):
                container_running = (line.split("=", 1)[1].strip() == "true")
                continue
            m = re.search(r"Got character ZDOID from (.+?) : (\d+):\d+", line)
            if m and m.group(2) != "0":
                online[m.group(2)] = m.group(1); continue
            m = re.search(r"Destroying abandoned non persistent zdo (\d+):\d+ owner \1\b", line)
            if m:
                online.pop(m.group(1), None); continue
            m = re.search(r"Connections (\d+) ZDOS", line)
            if m:
                players = int(m.group(1))
                t = re.search(r"(\d\d/\d\d/\d{4} \d\d:\d\d:\d\d):\s+Connections", line)
                if t:
                    players_asof = t.group(1)
                if players == 0:
                    online.clear()
        seen = set()
        for nm in online.values():
            if nm not in seen:
                seen.add(nm); player_names.append(nm)

    if vm_state != "running":
        headline, color = "\U0001F534 DOWN", 0xE74C3C          # red
        detail = "VM %s is %s" % (VMID, vm_state)
        players_txt, state_key = "\u2014", "down"
    elif container_running is False:
        headline, color = "\U0001F534 DOWN", 0xE74C3C
        detail = "VM up, but the `%s` container is not running" % CONTAINER
        players_txt, state_key = "\u2014", "down"
    elif container_running is None:
        headline, color = "\U0001F7E0 UNKNOWN", 0xF39C12       # orange
        detail = "VM up, but the guest agent did not answer"
        players_txt, state_key = "?", "unknown"
    else:
        headline, color = "\U0001F7E2 UP", 0x2ECC71            # green
        detail = "VM + container running"
        state_key = "up"
        if players is None:
            players_txt = "? (awaiting first server report)"
        elif players == 0:
            players_txt = "0"
        else:
            if player_names:
                names = ", ".join(player_names)
                if len(player_names) != players:
                    names += " (names may be incomplete)"
            else:
                names = "names unavailable"
            players_txt = "%d — %s" % (players, names)
            if players_asof:
                players_txt += "  (as of %s)" % players_asof

    return headline, color, detail, players_txt, state_key, server_name

# --- embeds + posting -------------------------------------------------------------------
def valheim_embed(headline, color, detail, players_txt, server_name):
    return {
        "title": "Valheim — %s" % (server_name or "server"),
        "color": color,
        "fields": [
            {"name": "Status",         "value": "%s — %s" % (headline, detail), "inline": False},
            {"name": "Players online", "value": players_txt,                    "inline": True},
        ],
    }

def health_embed(lvl, text):
    if lvl >= 2:
        title, color = "\U0001F534 host health: CRIT", 0xE74C3C
    elif lvl == 1:
        title, color = "\U0001F7E0 host health: WARN", 0xF39C12
    else:
        title, color = "\U0001F7E2 host health: OK", 0x2ECC71
    return {
        "title": title,
        "color": color,
        "fields": [{"name": "home-server", "value": (text or "(no data)")[:1000], "inline": False}],
    }

def post_embeds(embeds, tag):
    """POST one Discord message carrying `embeds`. Returns 0 ok / 1 POST failed."""
    if not embeds:
        return 0
    if not WEBHOOK:
        titles = " + ".join(e.get("title", "?") for e in embeds)
        print("status[%s]: DISCORD_WEBHOOK_URL not set "
              "(stage /etc/home-server/discord-server-status.env) — would have posted: %s"
              % (tag, titles))
        return 0
    payload = {"username": "home-server", "embeds": embeds}
    req = urllib.request.Request(
        WEBHOOK, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json",
                 "User-Agent": "home-server-status/2.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        body = e.read()[:200].decode("utf-8", "replace")
        print("status[%s]: webhook POST failed: HTTP %s %s" % (tag, e.code, body))
        return 1
    except Exception as e:
        print("status[%s]: webhook POST failed: %s" % (tag, e))
        return 1
    print("status[%s]: posted -> %s" % (tag, " + ".join(e.get("title", "?") for e in embeds)))
    return 0

# --- edge sub-checks --------------------------------------------------------------------
def valheim_edge():
    """Post only when Valheim up/down changed vs the state file. Returns rc (0/1)."""
    state = cheap_state()
    last  = read_last()
    if state == "unknown":
        print("valheim-status[edge]: state unknown (agent didn't answer) — no post "
              "(last known: %s)" % (last or "none"))
        return 0
    if last is None:
        write_state(state)
        print("valheim-status[edge]: initialized baseline to '%s' (no post)" % state)
        return 0
    if state == last:
        print("valheim-status[edge]: no change (%s) — no post" % state)
        return 0
    # Real transition -> gather full detail and announce.
    headline, color, detail, players_txt, state_key, server_name = full_status()
    rc = post_embeds([valheim_embed(headline, color, detail, players_txt, server_name)], "edge")
    if rc == 0:
        write_state(state if state_key == "unknown" else state_key)
    return rc

def health_edge():
    """Post only when host health crosses the CRIT boundary (enter CRIT / recover). rc (0/1)."""
    lvl, text = host_health(no_guest=True)
    if lvl < 0:
        return 0
    cur  = LVLNAME[lvl]
    last = read_file(HEALTH_STATE_FILE)          # 'ok'|'warn'|'crit'|None
    rc = 0
    if last is None:
        print("host-health[edge]: initialized baseline to '%s' (no post)" % cur)
    elif lvl == 2 and last != "crit":
        rc = post_embeds([health_embed(lvl, text)], "health-edge")
    elif last == "crit" and lvl != 2:
        rc = post_embeds([health_embed(lvl, text)], "health-recover")
    else:
        print("host-health[edge]: %s (crit-boundary unchanged) — no post" % cur)
    write_file(HEALTH_STATE_FILE, cur)           # persist current level each run
    return rc

# --- decide, per mode -------------------------------------------------------------------
if MODE == "edge":
    v_rc = valheim_edge()
    h_rc = health_edge()
    raise SystemExit(v_rc or h_rc)

# heartbeat (default): always post Valheim status + host-health snapshot; re-baseline both.
headline, color, detail, players_txt, state_key, server_name = full_status()
lvl, htext = host_health(no_guest=True)
embeds = [valheim_embed(headline, color, detail, players_txt, server_name)]
if lvl >= 0:
    embeds.append(health_embed(lvl, htext))
rc = post_embeds(embeds, "heartbeat")
if rc == 0 and state_key in ("up", "down"):
    write_state(state_key)
if lvl >= 0:
    write_file(HEALTH_STATE_FILE, LVLNAME[lvl])   # re-baseline the health edge too
raise SystemExit(rc)
PY
