#!/usr/bin/env bash
# install.sh — top-level installer for the valheim-server subsystem. Orchestrates the
# per-area installers (systemd units, agent context). Each sub-installer is idempotent
# and self-contained, so this is safe to re-run. Run as root.
#
# What this deploys: the Valheim systemd units (mod-update checks, Discord feeds, guest
# dump) that run on the Proxmox host and drive the Valheim VM (100) over the guest agent,
# plus the Valheim agent context (skills + memory) for Claude and the DeepSeek Harness.
#
# Relationship to home-server: this repo is a sibling clone at /srv/dev/repos/valheim-server.
# The host's own install.sh runs this as a final step, so a whole-box install still deploys
# Valheim. The VM itself is (re)created with guests/create-valheim-vm.sh (see docs/02).
#
# Secrets are never installed by these scripts — only their locations under /etc/home-server/
# and /etc/valheim/ (see each *.env.example).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "run as root:  sudo $0"; exit 1; }

echo "== valheim-server install =="

# Installers to run, in order. Add more here as areas get their own installer.
INSTALLERS=(
  "$REPO/systemd/install.sh"   # Valheim host systemd units (root)
  "$REPO/claude/install.sh"    # dev's Valheim agent context: skills + memory -> ~/.agents + ~/.dsh (writes as dev)
)

for inst in "${INSTALLERS[@]}"; do
  if [ -x "$inst" ]; then
    echo ">> $inst"
    "$inst"
  elif [ -f "$inst" ]; then
    echo ">> bash $inst"
    bash "$inst"
  else
    echo "!! missing installer: $inst" >&2
    exit 1
  fi
done

echo
echo "== valheim-server install complete =="
