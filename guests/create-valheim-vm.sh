#!/bin/bash
# create-valheim-vm.sh — (re)create the Valheim VM (100) from the Debian 13 cloud image.
# Thin wrapper: sets Valheim's box-specific values + cloud-init snippet, then calls the
# GENERIC creator that lives in the home-server repo (the reusable Proxmox VM-create
# mechanism). This repo (valheim-server) owns only the Valheim-specific parameters and
# the cloud-init file; the generic mechanics stay on the host repo.
#
# Idempotent-ish: the generic creator refuses if the VMID already exists (destroy first).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# The generic creator ships with the home-server (Proxmox host) repo, a sibling checkout.
CREATE_VM="${CREATE_VM:-/srv/dev/repos/home-server/guests/create-vm.sh}"
[ -x "$CREATE_VM" ] || {
  echo "FATAL: generic creator not found/executable at $CREATE_VM"
  echo "  It lives in the home-server repo. Clone it at /srv/dev/repos/home-server"
  echo "  (or set CREATE_VM=/path/to/create-vm.sh), then re-run."
  exit 1
}

# Valheim VM parameters. CORES=4: Valheim uses ~2-3; the extra core is deliberate
# headroom so a misbehaving mod that pegs the game threads can't fully starve the QEMU
# guest agent (the only way in — no SSH). A mod peg on 3 cores locked the agent out on
# 2026-09-10. (The live VM has since been bumped further; see the valheim-server memory.
# This is the from-scratch rebuild baseline.)
VMID="${VMID:-100}" \
VM_NAME="valheim" \
MEM="4096" \
CORES="4" \
DISK_GROW="+28G" \
BRIDGE="vmbr0" \
IPCFG="ip=192.168.100.10/24,gw=192.168.100.1" \
NAMESERVER="1.1.1.1" \
STORAGE="local-lvm" \
IMG="${IMG:-/home/dev/vmimg/debian-13-genericcloud-amd64.qcow2}" \
SNIPPET_SRC="$HERE/cloud-init-valheim.yaml" \
  exec "$CREATE_VM"
