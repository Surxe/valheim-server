---
name: valheim-add-mod
description: Adding/bumping/removing a Valheim mod — the /add-valheim-mod skill and its scripts
metadata:
  type: reference
---

To add, version-bump, or remove a Valheim server mod, use the **`/add-valheim-mod`** skill
(the full flow). The scripts it drives (in `valheim/`, run from the host as root):

- `mod-fetch.sh <thunderstore-url | Author Package [version]>` — vet + stage: downloads the
  pinned/latest version, drops the DLL in `dll/`, prints SHA-256 + deps + CHANGELOG, and emits a
  paste-ready `mods.manifest` line (you fill in the role).
- `verify-boot.sh [--wait N] [--mod Name] [--plugins|--errors]` — inspect the LATEST BepInEx boot
  (plugins loaded / load errors / session active); exit 0 = clean. The load-test + post-restart gate.
- `lib-gx.sh` — sourced helper (`gx`, `gx_push`, `gx_ready`) for driving VM 100 over the guest
  agent; shared by `verify-boot.sh` and `guests/vm-apply-valheim.sh`. `gx_ready` is the liveness
  probe (a real exec, not `qm agent ping`) — see [[valheim-vm-agent]].

See [[valheim-server]] for server/VM detail and the mod-status history, and [[valheim-mod-inventory]].
