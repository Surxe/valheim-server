#!/usr/bin/env bash
# systemd/install.sh — install the valheim-server systemd units (symlink-into-repo, so
# editing a unit here IS editing the live unit), reload, and start the timers.
# Idempotent; run as root. Called by ../install.sh. Secrets are NOT installed here.
#
# These units live in the valheim-server repo but run ON the Proxmox host: they drive the
# Valheim VM (100) over the guest agent, poll Thunderstore, post the Discord feeds, and
# dump the guest. Host-generic units (wifi, flash restic, todo) stay in the home-server repo.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UNIT_DIR=/etc/systemd/system
[ "$(id -u)" -eq 0 ] || { echo "systemd/install.sh: run as root"; exit 1; }

say() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

# All repo-maintained unit files (link them so the repo is the source of truth).
UNITS=(
  hs-mod-check.service          hs-mod-check.timer
  hs-mod-check-discord.service  hs-mod-check-discord.timer
  hs-mod-list.service           hs-mod-list.timer
  hs-mod-announce.service        # agent-triggered, no timer (post a mod-set change diff)
  hs-valheim-status.service         hs-valheim-status.timer
  hs-valheim-status-edge.service    hs-valheim-status-edge.timer
  hs-vzdump-valheim.service     hs-vzdump-valheim.timer
)
# Timer(s) this installer activates. (`enable --now` on a *timer* only starts its
# schedule; it does not run the job immediately.) The vzdump backup timer's enable-state
# is left to the operator so this installer never silently flips backup behaviour.
TIMERS=(hs-mod-check.timer hs-mod-check-discord.timer hs-mod-list.timer \
        hs-valheim-status.timer hs-valheim-status-edge.timer)

say "linking units into $UNIT_DIR"
for u in "${UNITS[@]}"; do
  if [ -f "$REPO/systemd/$u" ]; then
    ln -sfn "$REPO/systemd/$u" "$UNIT_DIR/$u"
    echo "  linked $u"
  else
    echo "  skip (missing in repo): $u"
  fi
done
chmod +x "$REPO/valheim/notify-mod-updates.sh" "$REPO/valheim/notify-mod-updates-discord.sh" \
         "$REPO/valheim/check-mod-updates.sh" "$REPO/valheim/server-status-discord.sh" \
         "$REPO/valheim/list-installed-mods.sh" "$REPO/valheim/announce-mod-change.sh" \
         "$REPO/backups/vzdump-valheim.sh" 2>/dev/null || true

# Seed the mod-change announcer's baseline to the CURRENT set on first install, so the
# first real announcement diffs against today's set instead of posting every installed
# mod as "added". Only if missing — never clobber a baseline (which would drop a pending,
# not-yet-announced change). State path unchanged (/var/lib/home-server) so a migrated box
# keeps its existing baseline.
ANNOUNCE_STATE=/var/lib/home-server/valheim-mod-announce.json
if [ ! -f "$ANNOUNCE_STATE" ]; then
  install -d -m 755 /var/lib/home-server
  MOD_ANNOUNCE_STATE_FILE="$ANNOUNCE_STATE" "$REPO/valheim/announce-mod-change.sh" --baseline \
    && echo "  seeded mod-announce baseline: $ANNOUNCE_STATE"
else
  echo "  ok: mod-announce baseline present ($ANNOUNCE_STATE)"
fi

say "reload + enable timers"
systemctl daemon-reload
for t in "${TIMERS[@]}"; do
  systemctl enable --now "$t" && echo "  enabled --now $t"
done
# Backup timer reported, not changed (never silently flip backup behaviour):
for t in hs-vzdump-valheim.timer; do
  echo "  $t: $(systemctl is-enabled "$t" 2>/dev/null || echo 'not-enabled')  (enable with: systemctl enable --now $t)"
done

say "checks"
ENVF=/etc/home-server/mod-notify.env
if [ ! -f "$ENVF" ]; then
  echo "  TODO: mod-update emails need SMTP creds. Do:"
  echo "      install -d -m 700 /etc/home-server"
  echo "      cp $REPO/valheim/mod-notify.env.example $ENVF && chmod 600 $ENVF"
  echo "      # then edit $ENVF and set SMTP_PASS (Gmail app password)"
  echo "  Test:  systemctl start hs-mod-check.service && journalctl -u hs-mod-check.service -n 20"
else
  echo "  ok: $ENVF present"
fi
# Discord webhook (one #valheim-server-status channel for all the feeds:
# hs-valheim-status, hs-mod-list, hs-mod-check-discord, hs-mod-announce). Optional
# EnvironmentFile — each unit logs "not set" and exits 0 until staged.
SENVF=/etc/home-server/discord-server-status.env
if [ ! -f "$SENVF" ]; then
  echo "  TODO: the Discord feeds (up/down + players, installed mods, mod-update alerts, mod-change announcements) need a webhook. Do:"
  echo "      install -d -m 700 /etc/home-server"
  echo "      cp $REPO/valheim/discord-server-status.env.example $SENVF && chmod 600 $SENVF"
  echo "      # then edit $SENVF and set DISCORD_WEBHOOK_URL"
  echo "  Test:  systemctl start hs-valheim-status.service && journalctl -u hs-valheim-status.service -n 20"
else
  echo "  ok: $SENVF present"
fi
echo "  next mod-check run: $(systemctl show -p NextElapseUSecRealtime --value hs-mod-check.timer 2>/dev/null || echo '(unknown)')"
echo "systemd units installed."
