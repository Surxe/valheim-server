# valheim-server

Config-as-code for a **modded Valheim dedicated server**, split out of the `home-server`
repo into its own home. It runs as a Docker container (`lloesche/valheim-server`) **inside
Proxmox VM 100** on the home-server box; this repo is the source of truth for its
container config, mod set, deploy tooling, the host-side systemd feeds that watch it, and
the agent skills + memory that operate it.

> **Box-coupled by design.** These scripts target *this* box: they drive VM 100 over the
> QEMU guest agent (`qm guest exec`, no SSH) from the Proxmox host. The host itself — wifi,
> networking, host backups, the `todo` hub, the generic VM-create mechanism — stays in the
> sibling [`home-server`](https://github.com/Surxe/home-server) repo. This repo is normally
> checked out next to it at `/srv/dev/repos/valheim-server`.

## Layout

| Path | What |
|---|---|
| `valheim/` | The application: `docker-compose.yml`, `mods.manifest`, `dll/`, mod configs, and all the deploy/verify/notify scripts. See `valheim/README.md`. |
| `guests/` | Valheim VM provisioning: `create-valheim-vm.sh` (wraps the host's generic `create-vm.sh`), `cloud-init-valheim.yaml`, and `vm-apply-valheim.sh` (push config into the VM + restart). |
| `systemd/` | Host units that watch/serve the VM: mod-update checks, Discord feeds (up/down, mod list, mod-change announce), and the guest vzdump. `systemd/install.sh` links + enables them. |
| `backups/` | `vzdump-valheim.sh` (whole-guest dump, host-run) and `restic-b2-world.sh` (offsite world backup, runs inside the VM). |
| `docs/` | `02-valheim-vm.md` — the VM runbook. Host/backup/restore context lives in the `home-server` repo's `docs/`. |
| `claude/` | Agent context: the `add-valheim-mod` / `announce-valheim-mods` / `restart-valheim` / `valheim-server-install` skills and the `valheim-*` memory notes, for Claude Code and the DeepSeek Harness. |

## Install

Run as root on the Proxmox host (idempotent, safe to re-run):

```
sudo /srv/dev/repos/valheim-server/install.sh
```

This links + enables the Valheim systemd units and deploys the agent context into dev's
`~/.agents` (Claude) and `~/.dsh` (DeepSeek). The host's own `home-server/install.sh` runs
this as a final step, so a whole-box install still covers Valheim. Applying a mod/config
change to the running server is a separate step — `guests/vm-apply-valheim.sh` — see
`valheim/README.md`.

## Secrets

None live here. Only their *locations* are documented (`*.env.example`): the Discord
webhook and SMTP creds in `/etc/home-server/`, the server/world values in
`/etc/valheim/valheim.env`, and restic/B2 creds in `/etc/home-server/backup.env`.

## History

Extracted from `home-server` in September 2026; earlier history of these files lives in
that repo.
