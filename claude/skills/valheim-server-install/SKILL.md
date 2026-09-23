---
name: valheim-server-install
description: >-
  Use this WHENEVER you edit code in the valheim-server repo that gets deployed — the
  systemd units under systemd/, the agent context under claude/ (skills, memory), the VM
  provisioning under guests/, or the VM-side Valheim assets under valheim/ (compose, mods,
  configs, hooks). It enforces the rule: an edit isn't done until it's applied live AND
  verified. If you tested it yourself and it passed, Ethan's review is not required; if you
  couldn't test it, say so and leave it for him. Trigger on any such edit, before you
  report the change as complete.
---

# Apply-and-verify valheim-server changes

valheim-server is config-as-code: editing a repo file is only half the job — the **live
system must be updated to match, and the change must be verified.** This is the checklist
for closing that loop. The repo lives at `/srv/dev/repos/valheim-server` (a sibling clone
of `home-server` on the Proxmox host); operate from the host as root/sudo.

## Two deploy paths — pick the one that fits the edit

**A. Host-side (`install.sh`)** — systemd units and agent context that live on the host:

- `systemd/*.service` / `*.timer` — symlinked into `/etc/systemd/system`; systemd needs a
  daemon-reload (the installer does it) to pick up changes.
- `claude/skills/**`, `claude/memory/**` — **copied** to `~/.agents` (skills symlinked into
  `~/.claude/skills`; memory into `~/.claude/projects/-<proj>/memory` and rendered to
  `~/.dsh/memory` for the DeepSeek Harness). A repo edit does NOT reach the live area until
  you re-install. NB: the per-project `MEMORY.md` index is SHARED with the home-server repo
  via fragments — this repo owns `claude/memory/srv-dev/MEMORY.md` (its section only).
- Host-run scripts a unit invokes in place (e.g. `valheim/notify-mod-updates.sh`,
  `valheim/server-status-discord.sh`, `backups/vzdump-valheim.sh`) — live immediately from
  the repo path, but still must be **tested**.

Install: `sudo /srv/dev/repos/valheim-server/install.sh` (whole subsystem), or a targeted
sub-installer — `sudo /srv/dev/repos/valheim-server/systemd/install.sh` (units) or
`/srv/dev/repos/valheim-server/claude/install.sh` (agent context; run as dev, or it drops
to dev when run as root). Installers are idempotent.

**B. VM-side (`vm-apply-valheim.sh`)** — the Valheim container's own assets:
`docker-compose.yml`, `mods.manifest`, `dll/`, `stage-mods.sh`, the mod `.cfg`s, the
catalog, `hooks/sync-plugins.sh`. These deploy INTO VM 100, not via `install.sh`:

```
sudo /srv/dev/repos/valheim-server/guests/vm-apply-valheim.sh   # push + stage + restart
sudo /srv/dev/repos/valheim-server/valheim/verify-boot.sh --wait 60
```

For a mod add/bump/remove specifically, use the `add-valheim-mod` skill (it wraps this).

## The loop — do all four

1. **Edit** the repo file.
2. **Apply** via path A or B above so the live system matches the repo.
3. **Verify** it actually works (see checks below). This is the important step.
4. **Report honestly**: verified + passed → done, no Ethan review needed. Could NOT verify
   yourself (needs a secret, a reboot, a real backup stick, someone to join the server) →
   say exactly what's unverified and leave it for Ethan. Never claim "done/tested" for
   something you only installed.

## Verify, by type

- **systemd unit/timer:** installer runs `daemon-reload`. Then `systemctl status <unit>`
  (loaded, no error) and `systemctl list-timers <timer>` (next run set). For a oneshot
  that's safe to run now (e.g. `hs-valheim-status`), `sudo systemctl start <svc>` and read
  `journalctl -u <svc> -n 30`. A service that hard-fails only on a missing secret is
  "unverified", not "broken" — note it.
- **Agent context (`claude/`):** after `claude/install.sh`, confirm the file landed —
  `~/.agents/skills/<name>/SKILL.md` and memory under `~/.agents/memory/`, the SHARED
  `~/.agents/memory/MEMORY.md` shows both the host and valheim sections, and `~/.dsh/memory/`
  lists the `valheim-server` id (DeepSeek). A skill/memory change is picked up by a NEW
  session — verify file content, not live behavior.
- **VM-side change:** `verify-boot.sh --wait 60` → **exit 0** = clean boot, plugins loaded,
  session active. Read its output for the plugin list and any `TypeLoad/Method/Field` errors.
- **A script:** run it (or a dry-run / read-only path) and check the output.

## Rules

- Idempotent, non-destructive, understand-before-change; keep repo == live.
- **No secrets in the repo** — only their `/etc/...` locations (e.g.
  `/etc/home-server/discord-server-status.env`, `/etc/valheim/valheim.env`). Never read or
  print secrets. This repo is PUBLIC.
- Commit/push when asked; branch off `main`.
