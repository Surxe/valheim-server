#!/usr/bin/env bash
# list-installed-mods.sh — list the mods currently installed on the Valheim server,
# grouped by ModSentry role (required / optional / server-only) with each mod's version.
#
# Source of truth is valheim/mods.manifest (what stage-mods.sh deploys; the repo==live
# invariant means the manifest IS what's installed). ENABLED = non-commented data lines;
# commented-out mods (disabled, waiting on a 1.0 build) are excluded. Read-only.
#
# Usage:
#   ./list-installed-mods.sh          # print a human table to stdout (manual use)
#   ./list-installed-mods.sh --post   # post the list to a Discord webhook
#
# --post reads the webhook from the environment (DISCORD_WEBHOOK_URL); the systemd unit
# hs-mod-list.service loads it from /etc/home-server/discord-server-status.env — the SAME
# webhook the status heartbeat uses (#valheim-server-status). Without it, --post logs
# and exits 0.
#
# Driven daily by systemd/hs-mod-list.{service,timer}.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${MODS_MANIFEST:-${HERE}/mods.manifest}"

MODE="table"
case "${1:-}" in --post) MODE="post";; "") ;; *) echo "unknown arg: $1" >&2; exit 2;; esac
[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

python3 - "$MODE" "$MANIFEST" <<'PY'
import sys, os, json, urllib.request, urllib.error

mode, manifest = sys.argv[1], sys.argv[2]

# Parse ENABLED manifest lines: "name | version | dll | sha256 | role | url".
# Skip comments (disabled mods) and any prose/non-data comment lines.
required, optional, server_only = [], [], []
with open(manifest) as f:
    for raw in f:
        line = raw.strip()
        if line.startswith("#") or not line:
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 6:
            continue
        name, version, role = parts[0], parts[1], parts[4].lower()
        roles = role.split("+")
        entry = (name, version)
        if "required" in roles:
            required.append(entry)
        elif "optional" in roles:
            optional.append(entry)
        else:                       # "plugin" with no client policy -> server-only
            server_only.append(entry)

total = len(required) + len(optional) + len(server_only)

def block(entries):
    return "\n".join("• %s  `%s`" % (n, v) for n, v in entries) or "_(none)_"

if mode == "table":
    def tbl(entries):
        return "\n".join("  - %-14s %s" % (n, v) for n, v in entries) or "  (none)"
    print("Valheim installed mods  (source: valheim/mods.manifest)  —  %d total\n" % total)
    print("Required (%d):"    % len(required));    print(tbl(required))
    print("Optional (%d):"    % len(optional));    print(tbl(optional))
    if server_only:
        print("Server-only (%d):" % len(server_only)); print(tbl(server_only))
    print("\n(BepInEx pack is provided by the lloesche image, not listed here.)")
    sys.exit(0)

# --- post mode ---
WEBHOOK = os.environ.get("DISCORD_WEBHOOK_URL")
if not WEBHOOK:
    print("mod-list: DISCORD_WEBHOOK_URL not set "
          "(stage /etc/home-server/discord-server-status.env) — would have posted %d mods "
          "(req=%d opt=%d)." % (total, len(required), len(optional)))
    sys.exit(0)

fields = [
    {"name": "Required (%d)" % len(required), "value": block(required), "inline": False},
    {"name": "Optional (%d)" % len(optional), "value": block(optional), "inline": False},
]
if server_only:
    fields.append({"name": "Server-only (%d)" % len(server_only),
                   "value": block(server_only), "inline": False})

payload = {
    "username": "home-server",
    "embeds": [{
        "title": "Valheim installed mods (%d)" % total,
        "color": 0x3498DB,
        "fields": fields,
    }],
}
req = urllib.request.Request(
    WEBHOOK, data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json",
             "User-Agent": "home-server-mod-list/1.0"})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        r.read()
except urllib.error.HTTPError as e:
    body = e.read()[:200].decode("utf-8", "replace")
    print("mod-list: webhook POST failed: HTTP %s %s" % (e.code, body), file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print("mod-list: webhook POST failed: %s" % e, file=sys.stderr)
    sys.exit(1)

print("mod-list: posted %d mods (req=%d opt=%d server-only=%d)."
      % (total, len(required), len(optional), len(server_only)))
PY
