#!/usr/bin/env bash
# notify-mod-updates.sh — run the Valheim mod-update check and email the configured
# recipient (MAIL_TO) when the set of update candidates CHANGES (so it never re-nags).
# Driven by systemd/hs-mod-check.{service,timer} on the Proxmox host.
#
# Credentials are NOT in the repo: the service pulls them from
#   /etc/home-server/mod-notify.env   (root:root 0600, see valheim/mod-notify.env.example)
# via EnvironmentFile, so they arrive here as env vars:
#   SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS MAIL_FROM MAIL_TO
# Gmail needs an APP PASSWORD (not the account password).
#
# State (history + last-notified signature) lives OUTSIDE the repo so the timer,
# running as root, never writes into the working tree:
#   /var/lib/hs-mod-notify/
#
# Exit codes: 0 = ok (emailed or nothing to do); 1 = wanted to email but SMTP unconfigured.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${MOD_NOTIFY_STATE_DIR:-/var/lib/hs-mod-notify}"
mkdir -p "$STATE_DIR"
export MOD_UPDATE_LOG="${STATE_DIR}/mod-update-history.csv"

: "${SMTP_HOST:=smtp.gmail.com}"
: "${SMTP_PORT:=587}"
export SMTP_HOST SMTP_PORT

# Capture the checker's JSON to a temp file (NOT a pipe — a pipe would collide with the
# python heredoc's stdin).
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
"${HERE}/check-mod-updates.sh" --json > "$TMP"

python3 - "$TMP" "$STATE_DIR" <<'PY'
import sys, os, json, smtplib, ssl
from email.message import EmailMessage

data = json.load(open(sys.argv[1]))
state_dir = sys.argv[2]
mods = data.get("mods", [])

# Candidates = any mod whose latest > what we run (status starts with NEWER).
candidates = [m for m in mods if (m.get("status") or "").startswith("NEWER")]
# Signature keyed by name -> latest version; email only when this set changes.
sig = {m["name"]: m["latest"] for m in candidates}

statefile = os.path.join(state_dir, "last-notified.json")
try:
    prev = json.load(open(statefile))
except Exception:
    prev = {}

def save():
    json.dump(sig, open(statefile, "w"), indent=2)

if sig == prev:
    print("mod-notify: no change in update candidates (%d) — no email." % len(sig))
    sys.exit(0)

if not sig:
    save()
    print("mod-notify: update candidates cleared — state updated, no email.")
    sys.exit(0)

FROM = os.environ.get("MAIL_FROM"); TO = os.environ.get("MAIL_TO")
USER = os.environ.get("SMTP_USER"); PW = os.environ.get("SMTP_PASS")
HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com"); PORT = int(os.environ.get("SMTP_PORT", "587"))
missing = [k for k in ("MAIL_FROM", "MAIL_TO", "SMTP_USER", "SMTP_PASS") if not os.environ.get(k)]
if missing:
    print("mod-notify: SMTP not configured (missing %s in /etc/home-server/mod-notify.env)."
          % ", ".join(missing), file=sys.stderr)
    print("mod-notify: would have emailed about: %s" % sig, file=sys.stderr)
    sys.exit(1)

lines = ["The Valheim mod-update check found new versions available:", ""]
for m in candidates:
    tag = " [post-1.0]" if "*" in (m.get("status") or "") else ""
    dis = "  (disabled — waiting on this)" if m.get("disabled") else ""
    lines.append("  - %s/%s: %s -> %s (published %s)%s%s"
                 % (m["namespace"], m["name"], m["pinned"], m["latest"], m.get("date_updated"), tag, dis))

ready = [m for m in candidates if m.get("disabled") and "*" in (m.get("status") or "")]
if ready:
    lines += ["", "RE-ENABLE CANDIDATES — a mod we disabled for 1.0 shipped a post-1.0 build:"]
    for m in ready:
        lines.append("  * %s %s" % (m["name"], m["latest"]))
    if any(m["name"].lower().startswith("jotunn") for m in ready):
        lines.append("  Jotunn is ready -> the whole Jotunn stack (Jotunn/Huginn/FarmGrid) can likely come back.")

lines += ["",
          "Checked at %s (UTC)." % data.get("checked_at", "?"),
          "Detail: run  valheim/check-mod-updates.sh  on the host.",
          "To adopt: bump version+SHA in valheim/mods.manifest (un-comment if disabled),",
          "run stage-mods.sh, update the client docs, restart the server."]

msg = EmailMessage()
msg["Subject"] = "[home-server] Valheim mod update(s) available (%d)" % len(candidates)
msg["From"] = FROM
msg["To"] = TO
msg.set_content("\n".join(lines))

ctx = ssl.create_default_context()
with smtplib.SMTP(HOST, PORT, timeout=30) as s:
    s.ehlo(); s.starttls(context=ctx); s.ehlo()
    s.login(USER, PW)
    s.send_message(msg)

save()
print("mod-notify: emailed %s about %d update(s): %s" % (TO, len(candidates), list(sig)))
PY
