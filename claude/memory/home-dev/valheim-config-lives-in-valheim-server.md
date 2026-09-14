---
name: valheim-config-lives-in-valheim-server
description: Valheim server config, systemd units, skills and memory live in the valheim-server repo (a sibling clone), NOT in home-server — edit there, then run its install.sh
metadata:
  type: feedback
---

The Valheim dedicated server was split out of `home-server` into its own repo,
**`valheim-server`**, checked out as a sibling at **`/srv/dev/repos/valheim-server`** on
this box. Everything Valheim now lives there, not in `home-server`:

- the app + mod tooling (`valheim/`), VM provisioning (`guests/`), the Valheim host
  systemd units (`systemd/`), world/guest backups (`backups/`), the VM runbook
  (`docs/02-valheim-vm.md`),
- **and the agent context** — the `add-valheim-mod`, `announce-valheim-mods`,
  `restart-valheim`, `valheim-server-install` skills and every `valheim-*` memory note
  (this one included).

`home-server` keeps only the host layer: Proxmox, wifi, host backups, the `todo` hub, and
the generic `guests/create-vm.sh` (which the valheim VM-create wrapper calls).

New or updated Valheim memories/skills/units go in the **valheim-server repo copy**, then
get deployed with `sudo /srv/dev/repos/valheim-server/install.sh` (or its sub-installers).
Never edit the live `~dev/.agents/...` copies directly — they're a deployment target,
overwritten on the next install. Same rule as [[memories-live-in-this-repo]] and
[[edit-in-repo]], just for the Valheim repo. Apply-and-verify via [[valheim-add-mod]] and
the `valheim-server-install` skill.

**Why:** config-as-code — version-controlled, reviewed, rebuildable; a note that exists
only in the live store is invisible to git and dies on reinstall.

**How to apply:** decide the file belongs to Valheim (vs the host), author/edit it under
`/srv/dev/repos/valheim-server/`, update that repo's index/`MEMORY.md` fragment, and run
its `install.sh`. The shared per-project `MEMORY.md` is assembled from each repo's fragment
under `~/.agents/memory/.index.d/`, so the host and valheim sections coexist.
