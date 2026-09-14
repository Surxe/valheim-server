#!/bin/bash
# restic-b2-world.sh — offsite copy of the Valheim WORLD ONLY to Backblaze B2.
# RUNS INSIDE THE VALHEIM VM (deployed to /srv/valheim/restic-b2-world.sh; the world
# dir is local to the VM). Driven by valheim/backup/valheim-b2-world.{service,timer}.
# (every other day). Separate restic repo, bucket-scoped key. keep-within 14d + prune.
set -euo pipefail

ENV_FILE=/etc/home-server/backup.env
WORLD=/srv/valheim/config

# shellcheck disable=SC1090
[ -r "$ENV_FILE" ] || { echo "FATAL: $ENV_FILE missing (B2 key / restic password not staged)"; exit 1; }
source "$ENV_FILE"
export RESTIC_PASSWORD_FILE B2_ACCOUNT_ID B2_ACCOUNT_KEY
export RESTIC_REPOSITORY="b2:${B2_BUCKET}:restic"

[ -d "$WORLD" ] || { echo "FATAL: $WORLD not present (Valheim not set up yet)"; exit 1; }

restic snapshots >/dev/null 2>&1 || restic init
restic backup --verbose --tag world "$WORLD"
restic forget --keep-within 14d --prune
restic check
