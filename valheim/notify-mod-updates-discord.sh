#!/usr/bin/env bash
# notify-mod-updates-discord.sh — run the Valheim mod-update check and post a summary to
# a Discord webhook when the set of update candidates CHANGES (so it never re-nags about
# the same update). Driven by systemd/hs-mod-check-discord.{service,timer} on the host.
#
# Sibling of notify-mod-updates.sh (email): same check + same "only on change" dedupe,
# different channel. The two are independent — enable either, both, or neither by staging
# (or not) their env files. Both call the read-only check-mod-updates.sh.
#
# The webhook URL is a secret and is NOT in the repo. The service pulls it from
#   /etc/home-server/discord-server-status.env   (root:root 0600, see *.env.example) —
# the #valheim-server-status channel webhook, shared with hs-valheim-status + hs-mod-list.
# via EnvironmentFile, so it arrives here as an env var:
#   DISCORD_WEBHOOK_URL
#
# State (last-notified signature + history CSV) lives OUTSIDE the repo so the timer,
# running as root, never writes into the working tree:
#   /var/lib/hs-mod-notify-discord/
#
# Exit codes: 0 = ok (posted or nothing to do); 1 = wanted to post but webhook unconfigured
# or the POST failed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${MOD_NOTIFY_DISCORD_STATE_DIR:-/var/lib/hs-mod-notify-discord}"
mkdir -p "$STATE_DIR"
# Keep this channel's history separate from the email job's so neither clobbers the other.
export MOD_UPDATE_LOG="${STATE_DIR}/mod-update-history.csv"

# Capture the checker's JSON to a temp file (NOT a pipe — a pipe would collide with the
# python heredoc's stdin).
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
"${HERE}/check-mod-updates.sh" --json > "$TMP"

python3 - "$TMP" "$STATE_DIR" <<'PY'
import sys, os, json, urllib.request, urllib.error

data = json.load(open(sys.argv[1]))
state_dir = sys.argv[2]
mods = data.get("mods", [])

# Candidates = any mod whose latest > what we run (status starts with NEWER).
candidates = [m for m in mods if (m.get("status") or "").startswith("NEWER")]
# Signature keyed by name -> latest version; post only when this set changes.
sig = {m["name"]: m["latest"] for m in candidates}

statefile = os.path.join(state_dir, "last-notified.json")
try:
    prev = json.load(open(statefile))
except Exception:
    prev = {}

def save():
    json.dump(sig, open(statefile, "w"), indent=2)

if sig == prev:
    print("mod-notify-discord: no change in update candidates (%d) — no post." % len(sig))
    sys.exit(0)

if not sig:
    save()
    print("mod-notify-discord: update candidates cleared — state updated, no post.")
    sys.exit(0)

WEBHOOK = os.environ.get("DISCORD_WEBHOOK_URL")
if not WEBHOOK:
    print("mod-notify-discord: DISCORD_WEBHOOK_URL not set "
          "(stage /etc/home-server/discord-server-status.env).", file=sys.stderr)
    print("mod-notify-discord: would have posted about: %s" % sig, file=sys.stderr)
    sys.exit(1)

# Thunderstore package page (masked link works in embed field/description text).
def ts_page(m):
    return "https://thunderstore.io/c/valheim/p/%s/%s/" % (m["namespace"], m["name"])

lines = ["**Not installed yet** — a newer version exists on Thunderstore; the server is "
         "unchanged until someone applies it.", ""]
for m in candidates:
    tag = "  `post-1.0`" if "*" in (m.get("status") or "") else ""
    dis = "  *(disabled — waiting on this)*" if m.get("disabled") else ""
    lines.append("• **[%s/%s](%s)** — running `%s`, available `%s` (published %s)%s%s"
                 % (m["namespace"], m["name"], ts_page(m), m["pinned"], m["latest"],
                    m.get("date_updated"), tag, dis))

ready = [m for m in candidates if m.get("disabled") and "*" in (m.get("status") or "")]
if ready:
    lines.append("")
    lines.append("__Re-enable candidates__ — a mod disabled for 1.0 shipped a post-1.0 build:")
    for m in ready:
        lines.append("• [%s](%s) %s" % (m["name"], ts_page(m), m["latest"]))
    if any(m["name"].lower().startswith("jotunn") for m in ready):
        lines.append("Jotunn is ready → the whole Jotunn stack (Jotunn/Huginn/FarmGrid) can likely come back.")

desc = "\n".join(lines)
if len(desc) > 3900:            # Discord embed description hard-limit is 4096
    desc = desc[:3900] + "\n… (truncated — run check-mod-updates.sh for the full list)"

payload = {
    "username": "home-server",
    "embeds": [{
        "title": "Valheim: %d mod update(s) available to install (not yet applied)" % len(candidates),
        "description": desc,
        "color": 0xE67E22,
        "footer": {"text": "checked %s UTC" % data.get("checked_at", "?")},
    }],
}
req = urllib.request.Request(
    WEBHOOK, data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json",
             "User-Agent": "home-server-mod-notify-discord/1.0"})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        r.read()
except urllib.error.HTTPError as e:
    body = e.read()[:200].decode("utf-8", "replace")
    print("mod-notify-discord: webhook POST failed: HTTP %s %s" % (e.code, body), file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print("mod-notify-discord: webhook POST failed: %s" % e, file=sys.stderr)
    sys.exit(1)

save()
print("mod-notify-discord: posted %d update(s): %s" % (len(candidates), list(sig)))
PY
