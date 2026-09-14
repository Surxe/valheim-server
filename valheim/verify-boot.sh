#!/bin/bash
# verify-boot.sh — inspect the LATEST BepInEx boot of the Valheim server (VM 100) and report
# whether it came up clean. Runs on the Proxmox HOST as root (sudo) — uses the guest agent.
#
#   verify-boot.sh                 full report; exit 0 only if no load errors (and, with --mod,
#                                  that mod loaded)
#   verify-boot.sh --wait <sec>    sleep <sec> on the HOST first, then read once (let a
#                                  just-restarted server finish loading before we probe)
#   verify-boot.sh --mod <Name>    also assert "Loading [<Name> ...]" is present this boot;
#                                  <Name> is the BepInEx DISPLAY name as it appears in the log
#                                  (e.g. "FirstPersonMode", "BetterCarts" — note "Drop That!",
#                                  "One Map To Rule Them All" differ from their package names)
#   verify-boot.sh --plugins       print only the plugins that loaded this boot, then exit
#   verify-boot.sh --errors        print only the load errors this boot; exit 1 if any
#
# "This boot" = from the last "Chainloader started" in the log (it's appended across restarts).
# The log on the VM host is the container's /opt/valheim/bepinex/... via the data bind mount.
#
# CAUTION: run this only once the server has FINISHED loading the world. World-load pegs the
# game threads, and a guest-exec issued during that CPU spike can wedge the guest agent (which
# then needs a VM restart to recover — retries won't fix it). After a plain container restart
# give it ~60s; after a full VM (re)boot the startup storm is heavier — wait ~2-3 min. In steady
# state (server long-up, idle) it's safe and instant.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-gx.sh
source "$HERE/lib-gx.sh"

WAIT=0; MOD=""; MODE="full"
while [ $# -gt 0 ]; do
  case "$1" in
    --wait)    WAIT="${2:?}"; shift 2;;
    --mod)     MOD="${2:?}"; shift 2;;
    --plugins) MODE="plugins"; shift;;
    --errors)  MODE="errors"; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

# Wait on the HOST, not inside the guest-exec: a long-held exec during world-load (CPU heavy)
# can starve the guest agent. Keep each guest call short + retry if the agent is momentarily busy.
[ "${WAIT:-0}" -gt 0 ] && sleep "$WAIT"

# read_boot: emit the latest boot's plugins / load errors / session line from the guest.
# CRITICAL: the string passed to `gx bash -c` must be PURE ASCII with NO comments. A non-ASCII
# byte in the guest-exec payload (e.g. a "—" em-dash in a comment) hangs the guest-side exec over
# QGA until it times out — the bug that made this script "flaky" (it was 100% deterministic).
# So all explanation lives out here, never inside the quoted payload. Notes on the payload:
#   - bash -c (not -lc): no need for a login shell; just tail/grep, on the default PATH.
#   - NEVER scan the whole log (it grows across restarts): read a bounded `tail -n 8000` only.
#     The boot marker, plugin loads and session line cluster right after a (re)start, inside it.
#     If the last boot is older than the window (long-up server) we emit NO-BOOT-IN-WINDOW.
#   - The "is active with" session line is in this same BepInEx log (like the restart-valheim
#     skill) — grep it from the slice; do NOT use `docker logs` (that can wedge the agent).
read_boot() {
  gx bash -c '
LOG=/srv/valheim/data/bepinex/BepInEx/LogOutput.log
[ -f "$LOG" ] || { echo "LOG-MISSING"; exit 0; }
tail -n 8000 "$LOG" > /tmp/vb.tail
START=$(grep -an "Chainloader started" /tmp/vb.tail | tail -1 | cut -d: -f1)
[ -n "$START" ] || { echo "NO-BOOT-IN-WINDOW"; exit 0; }
tail -n +"$START" /tmp/vb.tail > /tmp/vb.log
echo "===PLUGINS==="
grep -aoE "Loading \[[^]]+\]" /tmp/vb.log || true
echo "===ERRORS==="
grep -aniE "TypeLoad|could not be instantiated|could not resolve type|Method not found|Field not found|Exception|Failed to load" /tmp/vb.log || true
echo "===SESSION==="
grep -aE "is active with" /tmp/vb.log | tail -1 || true
echo "===END==="
'
}

# Preflight: only touch the log if the agent actually answers a trivial exec. This avoids firing
# the (heavier) log read at a busy/wedged agent and wedging it further — the failure mode that
# has bitten us. If it's not answering, the SERVER may well be fine; we just can't read yet.
if ! gx_ready 2 12; then
  echo "guest agent not answering a trivial exec — NOT a boot error. The server may be fine; we" >&2
  echo "just can't read the log. If it just (re)started, world-load pegs CPU and starves the" >&2
  echo "agent — wait ~2-3 min and retry. Do not reboot on this alone (see read-logs-targeted /" >&2
  echo "valheim-server memories; ping lies here, so this used a real exec)." >&2
  exit 2
fi

OUT=""
for attempt in 1 2; do
  if OUT="$(read_boot)"; then break; fi
  OUT=""; [ "$attempt" -lt 2 ] && { echo "log read failed (agent busy with world-load?) — one retry in 15s" >&2; sleep 15; }
done
[ -n "$OUT" ] || { echo "log read failed after preflight passed — agent likely busy (world-load?); wait and retry" >&2; exit 2; }

grep -q '^LOG-MISSING$' <<<"$OUT" && { echo "BepInEx log not found — server not booted yet?" >&2; exit 2; }
grep -q '^NO-BOOT-IN-WINDOW$' <<<"$OUT" && { echo "no 'Chainloader started' in the recent-log window — server has been up a long time (this tool is the post-restart gate; restart first, or it's fine as-is)" >&2; exit 2; }

extract() { awk -v s="===$1===" '$0==s{f=1;next} /^===/{f=0} f' <<<"$OUT"; }
PLUGINS="$(extract PLUGINS)"; ERRORS="$(extract ERRORS)"; SESSION="$(extract SESSION)"

case "$MODE" in
  plugins) printf '%s\n' "${PLUGINS:-(none)}"; exit 0;;
  errors)  printf '%s\n' "${ERRORS}"; [ -z "$ERRORS" ] && exit 0 || exit 1;;
esac

echo "== plugins loaded (latest boot) =="; printf '%s\n' "${PLUGINS:-(none)}"
echo "== load errors ==";                  printf '%s\n' "${ERRORS:-(none)}"
echo "== session ==";                       printf '%s\n' "${SESSION:-(no active session line yet — may still be booting)}"
echo "=================================="

rc=0
[ -n "$ERRORS" ] && { echo "VERDICT: load errors present on the latest boot" >&2; rc=1; }
if [ -n "$MOD" ]; then
  if grep -qE "Loading \[$MOD" <<<"$PLUGINS"; then echo "VERDICT: $MOD loaded ✓"
  else echo "VERDICT: $MOD did NOT load this boot ✗" >&2; rc=1; fi
fi
[ -z "$SESSION" ] && echo "VERDICT: no active-session line yet (give it ~40-60s, or --wait)" >&2
[ "$rc" -eq 0 ] && [ -n "$SESSION" ] && echo "VERDICT: clean ✓"
exit "$rc"
