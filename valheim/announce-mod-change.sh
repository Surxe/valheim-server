#!/usr/bin/env bash
# announce-mod-change.sh — post a CHANGELOG of the running Valheim mod set to Discord:
# what was added / version-bumped / removed / had its role changed since the last
# announcement, each labelled required / optional / server-only.
#
# This is the "we changed the mods and it's verified live" announcement — distinct from:
#   * list-installed-mods.sh --post   (hs-mod-list) — the FULL current inventory, daily.
#   * notify-mod-updates-discord.sh   (hs-mod-check-discord) — an update is AVAILABLE on
#     Thunderstore but NOT applied yet (the opposite direction in time).
# This one fires AFTER a change is applied and verified working, and states exactly
# what changed.
#
# ── AI-orchestrated by design ────────────────────────────────────────────────
# The DIFF is fully programmatic (this script computes it from mods.manifest vs a saved
# baseline), but WHEN to run it is a human/agent decision: only once the new mod
# version has been verified to actually load & run (see the announce-valheim-mods skill
# and the mod-test recipe in the valheim-server memory). A pure git/manifest hook can't
# know a mod "works", so there is deliberately NO timer for this — you trigger it.
#
# ── How the diff works ───────────────────────────────────────────────────────
# Source of truth = valheim/mods.manifest (ENABLED, non-commented lines = what's live,
# same as list-installed-mods.sh). We compare that against a BASELINE snapshot of the
# last-announced set (name -> version + role) kept OUTSIDE the repo so root can write it:
#   /var/lib/home-server/valheim-mod-announce.json   (override: MOD_ANNOUNCE_STATE_FILE)
# On a successful post we save the new baseline, so re-running without a further change
# posts nothing (no double-announce). install.sh seeds the baseline to the current set
# on first install so we never announce the whole existing set as "added".
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   ./announce-mod-change.sh            # post the diff (needs DISCORD_WEBHOOK_URL), save baseline
#   ./announce-mod-change.sh --post     # same as above (explicit)
#   ./announce-mod-change.sh --dry-run  # print the diff, never post, never save baseline
#   ./announce-mod-change.sh --baseline # set baseline = current set, no post (silent reset/seed)
#
# The webhook URL is a secret and is NOT in the repo. Trigger via the systemd oneshot
#   sudo systemctl start hs-mod-announce.service
# which loads it from /etc/home-server/discord-server-status.env (#valheim-server-status,
# the same webhook all the other Valheim feeds use), so you never handle the secret.
#
# ROLE PING (optional): set MOD_ANNOUNCE_ROLE_IDS in that same env file to a comma-separated
# list of numeric Discord role IDs (e.g. the "valheim server" role) to @-ping them on each
# announcement. Unset = no ping. Only these exact roles are pinged (never @everyone). The ID
# is not a secret but is server-specific, so it lives in the env file, not the repo. Get it in
# Discord: enable Developer Mode, then right-click the role → Copy Role ID.
# Run directly (webhook unset) and it takes the "would have posted" branch — exit 0, no
# save — which is how you preview safely from a plain sudo shell.
#
# Exit codes: 0 = ok (posted / would-have-posted / nothing to do / baseline saved);
#             1 = the POST itself failed (webhook set but Discord rejected it).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${MODS_MANIFEST:-${HERE}/mods.manifest}"
STATE_FILE="${MOD_ANNOUNCE_STATE_FILE:-/var/lib/home-server/valheim-mod-announce.json}"

MODE="post"
case "${1:-}" in
  --post|"") MODE="post";;
  --dry-run) MODE="dry-run";;
  --baseline) MODE="baseline";;
  *) echo "unknown arg: $1 (use --post | --dry-run | --baseline)" >&2; exit 2;;
esac
[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

python3 - "$MODE" "$MANIFEST" "$STATE_FILE" <<'PY'
import sys, os, json, datetime, re, urllib.request, urllib.error

mode, manifest, state_file = sys.argv[1], sys.argv[2], sys.argv[3]

def ts_page(url):
    # manifest url is a download link:
    #   https://thunderstore.io/package/download/<NS>/<NAME>/<VER>/
    # turn it into the Valheim package page:
    #   https://thunderstore.io/c/valheim/p/<NS>/<NAME>/
    m = re.search(r"thunderstore\.io/package/download/([^/]+)/([^/]+)/", url or "")
    return "https://thunderstore.io/c/valheim/p/%s/%s/" % (m.group(1), m.group(2)) if m else None

def role_label(role_field):
    roles = role_field.lower().split("+")
    if "required" in roles:
        return "required"
    if "optional" in roles:
        return "optional"
    return "server-only"   # a bare "plugin" with no client policy

# Current enabled set: name -> {"version":..., "role":...}
current = {}
with open(manifest) as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 6:
            continue
        name, version, role = parts[0], parts[1], role_label(parts[4])
        # Persist the Thunderstore page URL into the baseline too, so a later REMOVAL
        # (which only has the old baseline to go on) can still be hyperlinked.
        current[name] = {"version": version, "role": role, "url": ts_page(parts[5])}

# Baseline (last announced). Missing/corrupt -> {} (treated as first announcement).
try:
    prev = json.load(open(state_file))
    if not isinstance(prev, dict):
        prev = {}
except Exception:
    prev = {}

def save_baseline():
    os.makedirs(os.path.dirname(state_file) or ".", exist_ok=True)
    tmp = state_file + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(current, fh, indent=2, sort_keys=True)
    os.replace(tmp, state_file)

# --- baseline mode: just record current, no diff, no post ---
if mode == "baseline":
    save_baseline()
    print("mod-announce: baseline set to current set (%d mods) — no post." % len(current))
    sys.exit(0)

# --- compute the diff ---
added   = [(n, current[n]) for n in current if n not in prev]
removed = [(n, prev[n])    for n in prev    if n not in current]
updated, role_changed = [], []
for n in current:
    if n not in prev:
        continue
    old, new = prev[n], current[n]
    old_ver = old.get("version") if isinstance(old, dict) else old   # tolerate old flat format
    old_role = old.get("role", "?") if isinstance(old, dict) else "?"
    if old_ver != new["version"]:
        updated.append((n, old_ver, new["version"], new["role"]))
    elif old_role != new["role"]:
        role_changed.append((n, new["version"], old_role, new["role"]))

n_changes = len(added) + len(removed) + len(updated) + len(role_changed)

# Totals for the footer.
def count(label):
    return sum(1 for v in current.values() if v["role"] == label)
req, opt, srv = count("required"), count("optional"), count("server-only")
footer = "%d mods now installed — required=%d, optional=%d, server-only=%d" % (
    len(current), req, opt, srv)

# Removed entries come from the OLD baseline; tolerate a legacy flat "name: version".
def rv(d): return d["version"] if isinstance(d, dict) else d
def rr(d): return d.get("role", "?") if isinstance(d, dict) else "?"
def ru(d): return d.get("url") if isinstance(d, dict) else None

# Bold mod name, hyperlinked to its Thunderstore page when we have the URL. A legacy
# baseline (pre-URL) yields no link — just the bold name — which self-heals on next save.
def name_md(name, url):
    return "[**%s**](%s)" % (name, url) if url else "**%s**" % name

# --- render a human summary (used by dry-run and printed alongside a post) ---
def human():
    out = []
    if added:
        out.append("Added:");   out += ["  + %s %s [%s]" % (n, d["version"], d["role"]) for n, d in added]
    if updated:
        out.append("Updated:"); out += ["  ~ %s %s -> %s [%s]" % (n, ov, nv, r) for n, ov, nv, r in updated]
    if role_changed:
        out.append("Role changed:"); out += ["  * %s %s: %s -> %s" % (n, v, o, r) for n, v, o, r in role_changed]
    if removed:
        out.append("Removed:"); out += ["  - %s %s [%s]" % (n, rv(d), rr(d)) for n, d in removed]
    return "\n".join(out)

if n_changes == 0:
    print("mod-announce: no changes since last announcement (%d mods) — nothing to post." % len(current))
    sys.exit(0)

# Optional role ping (comma-separated numeric role IDs in MOD_ANNOUNCE_ROLE_IDS, staged in
# the same env file as the webhook). Unset = no ping. Computed here so dry-run reports it too.
role_ids = [r.strip() for r in os.environ.get("MOD_ANNOUNCE_ROLE_IDS", "").split(",")
            if r.strip()]
ping_note = ("will ping role(s): %s" % ", ".join(role_ids)) if role_ids else \
            "no role ping (MOD_ANNOUNCE_ROLE_IDS unset)"

if mode == "dry-run":
    print("mod-announce: %d change(s) since last announcement:\n%s\n(%s)\n(%s)"
          % (n_changes, human(), footer, ping_note))
    print("mod-announce: DRY RUN — not posting, baseline unchanged.")
    sys.exit(0)

# --- build the Discord embed ---
def field(title, lines):
    val = "\n".join(lines) if lines else "_(none)_"
    if len(val) > 1000:                       # Discord field-value cap is 1024
        val = val[:1000] + "\n… (truncated)"
    return {"name": title, "value": val, "inline": False}

fields = []
if added:
    fields.append(field("Added (%d)" % len(added),
        ["• %s `%s` — _%s_" % (name_md(n, d.get("url")), d["version"], d["role"]) for n, d in added]))
if updated:
    fields.append(field("Updated (%d)" % len(updated),
        ["• %s `%s` → `%s` — _%s_" % (name_md(n, current[n].get("url")), ov, nv, r) for n, ov, nv, r in updated]))
if role_changed:
    fields.append(field("Role changed (%d)" % len(role_changed),
        ["• %s `%s` — _%s_ → _%s_" % (name_md(n, current[n].get("url")), v, o, r) for n, v, o, r in role_changed]))
if removed:
    fields.append(field("Removed (%d)" % len(removed),
        ["• %s `%s` — _was %s_" % (name_md(n, ru(d)), rv(d), rr(d)) for n, d in removed]))

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
payload = {
    "username": "home-server",
    "embeds": [{
        "title": "Valheim mod set updated — %d change(s)" % n_changes,
        "description": "The running mod set changed and has been verified live on the server. "
                       "Client-**required** mods must be installed to join; **optional** mods "
                       "are per-player; **server-only** mods need nothing on your end.",
        "color": 0x2ECC71,
        "fields": fields,
        "footer": {"text": footer},
    }],
}

# Attach the role ping (computed above). A role only NOTIFIES from a mention in `content`
# (not in an embed), so we put "<@&ID>" there. allowed_mentions restricts the ping to exactly
# these role IDs — parse:[] blocks @everyone/@here and any stray mention — and lets a webhook
# ping a role even if it isn't marked "mentionable" server-side.
if role_ids:
    payload["content"] = " ".join("<@&%s>" % r for r in role_ids)
    payload["allowed_mentions"] = {"parse": [], "roles": role_ids}

WEBHOOK = os.environ.get("DISCORD_WEBHOOK_URL")
if not WEBHOOK:
    print("mod-announce: DISCORD_WEBHOOK_URL not set "
          "(stage /etc/home-server/discord-server-status.env, or run via "
          "`systemctl start hs-mod-announce.service`).")
    print("mod-announce: would have posted %d change(s) [%s]:\n%s" % (n_changes, ping_note, human()))
    print("mod-announce: baseline left unchanged (nothing was announced).")
    sys.exit(0)

req_obj = urllib.request.Request(
    WEBHOOK, data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json",
             "User-Agent": "home-server-mod-announce/1.0"})
try:
    with urllib.request.urlopen(req_obj, timeout=30) as r:
        r.read()
except urllib.error.HTTPError as e:
    body = e.read()[:200].decode("utf-8", "replace")
    print("mod-announce: webhook POST failed: HTTP %s %s" % (e.code, body), file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print("mod-announce: webhook POST failed: %s" % e, file=sys.stderr)
    sys.exit(1)

save_baseline()   # only after a confirmed post, so a failed post re-announces next time
print("mod-announce: posted %d change(s) (added=%d updated=%d role=%d removed=%d); %s; baseline saved."
      % (n_changes, len(added), len(updated), len(role_changed), len(removed), ping_note))
PY
