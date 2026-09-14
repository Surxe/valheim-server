#!/bin/bash
# vm-apply-valheim.sh — deploy this repo's Valheim config INTO the Valheim VM and apply it.
# Run on the Proxmox HOST. Uses the QEMU guest agent (no SSH into the VM needed).
#
#   1. push valheim/{docker-compose.yml,mods.manifest,stage-mods.sh,drop_that.drop_table.cfg}
#      into the VM at /srv/valheim/
#   2. run stage-mods.sh in the VM (verifies DLL hashes, lays plugins + ModSentry policy,
#      mirrors the runtime plugin cache) — DLLs are downloaded+verified in the VM if absent
#   3. docker compose restart (BepInEx reloads; the crossplay join code rotates)
#
# Does NOT manage secrets/values: /etc/valheim/valheim.env is set by hand on the VM.
set -euo pipefail
VMID="${VMID:-100}"
VDIR="$(cd "$(dirname "$0")/../valheim" && pwd)"

# gx / gx_push: drive the guest over the QEMU agent (shared with verify-boot.sh etc.)
# shellcheck source=../valheim/lib-gx.sh
source "$VDIR/lib-gx.sh"

# Liveness via a trivial exec, NOT `qm agent ping` — ping false-negatives on this box (reports
# "not running" while guest-exec works), and we don't want to refuse a deploy the agent can do.
gx_ready || { echo "FATAL: VM $VMID guest agent not answering a trivial exec (ping is unreliable here)"; exit 1; }

for f in docker-compose.yml mods.manifest stage-mods.sh drop_that.drop_table.cfg drummercraig.one_map_to_rule_them_all.cfg OneMapToRuleThemAll.catalog.txt; do
  gx_push "$VDIR/$f" "/srv/valheim/$f"
done
gx bash -c "chmod +x /srv/valheim/stage-mods.sh" >/dev/null

echo "== staging mods in VM =="
GX_TIMEOUT=180 gx bash -lc "cd /srv/valheim && ./stage-mods.sh"

echo "== restarting container =="
GX_TIMEOUT=120 gx bash -lc "cd /srv/valheim && docker compose restart"
echo "done. verify once world-load settles (~1 min): sudo $(dirname "$0")/../valheim/verify-boot.sh --wait 60"
