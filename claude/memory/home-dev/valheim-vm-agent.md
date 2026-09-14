---
name: valheim-vm-agent
description: VM 100 guest-agent liveness/recovery — test with a real exec (ping lies), wait out world-load, reboot last
metadata:
  type: feedback
---

Checking/reviving the VM 100 QEMU guest agent (our only channel into the guest — no SSH).

- **Test liveness with a trivial exec, never `qm agent ping`** — ping false-negatives here
  ("QEMU guest agent is not running" while `qm guest exec` works). Use `gx_ready` (in
  [[valheim-add-mod]]'s `lib-gx.sh`) or `qm guest exec 100 --timeout 15 -- /bin/true`.
- **World-load starves it.** Right after a container/VM (re)start the update-check + world-load
  peg CPU; an exec fired then can time out and *wedge* the agent (a timed-out exec leaves a
  zombie in the guest, degrading it further). So: wait ~2-3 min, gate heavy reads on `gx_ready`,
  and **don't retry-hammer**. See [[read-logs-targeted]].
- **Recover, in order:** wait it out → (if reachable) restart `qemu-guest-agent` in-guest →
  VM restart *only* as last resort. **A dead agent does not mean the game is down** — the
  container runs independently; confirm server state before any reboot. Don't reboot on a ping
  failure alone.
- **Guest-exec payloads must be pure ASCII.** A non-ASCII byte in the command you send (e.g. a
  `—` em-dash in a *comment* inside `qm guest exec … -- bash -c '…'`) makes the guest-side exec
  hang until it times out — looks exactly like a flaky/dead agent but is 100% deterministic.
  Keep the shipped string ASCII; put explanations in the host script, not the payload.
