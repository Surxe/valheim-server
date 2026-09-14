---
name: read-logs-targeted
description: Always read logs in targeted slices (tail/grep), never whole
metadata:
  type: feedback
---

Read logs in targeted sections — `tail`, `grep`, a line-range — never the whole file.

**Why:** an unbounded read (e.g. `docker logs valheim` over the guest agent) can hang the VM
100 agent and wastes context. **How to apply:** bound every log read (`--tail N`, grep to the
lines you need). See [[valheim-add-mod]] (`verify-boot.sh`), [[valheim-vm-agent]], [[valheim-server]].
