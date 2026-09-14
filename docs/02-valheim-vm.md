# 02 — Valheim VM (Docker + modded dedicated server)

Goal: a modded Valheim dedicated server your friends can join today by crossplay
join code, running in its own VM so it snapshots/restores independently.

The **authoritative mod manifest** (exact versions, SHA-256 hashes, ModSentry
policy-folder layout, launch args) is
`../valheim-mods/SERVER-HANDOFF.md`. Do not re-derive it here — follow it. This
doc covers the *hosting* layer around it.

## 1. Create the VM

In Proxmox:

- Guest: a small **Debian 13** VM (netinst, minimal, no desktop).
- vCPU/RAM: Valheim is memory-hungry per world; start ~4GB RAM / 2-4 vCPU and
  adjust. An old laptop CPU is fine for a few friends. On this 7.1 GiB host the alloc
  stays **4 GiB fixed** (bumping toward 5.5 would risk host OOM); cloud-init instead adds
  a small **1.5 GiB swapfile** (`vm.swappiness=10`) as an OOM cushion so a transient spike
  past RAM degrades gracefully instead of killing the server.
- Disk: ~**32GB** thin-provisioned (8GB game + world + guest OS + Docker images,
  with headroom). Grow later if needed.
- Network: attach to the **NAT/routed** internal bridge from `01-proxmox-host.md`
  (outbound-only is all crossplay needs).
- Enable the **QEMU guest agent** in the VM (`qemu-guest-agent`) so Proxmox can do
  clean, consistent snapshots/backups.

Why a VM and not LXC today: Docker "just works" in a VM with no nesting/keyctl
tweaks. Revisit LXC later if you want to reclaim the overhead.

## 2. Install Docker in the VM

Standard Docker CE install on the Debian guest. Confirm `docker run hello-world`.

## 3. Separate the data from the container (important)

The container is throwaway; the **world + server config are precious**. Bind-mount
them to a host path in the VM so rebuilding/upgrading the container never touches
the world:

```
# host-side dir in the VM, e.g.:
/srv/valheim/config      # lloesche image /config : worlds, server config, BepInEx
/srv/valheim/server      # optional: the game/server install cache
```

Everything under `/srv/valheim/config` is what backups and the B2 world-save copy
target (see `03-backups.md`). Keep it out of the container's writable layer.

## 4. Run the server (lloesche/valheim-server)

Use the well-maintained `lloesche/valheim-server` image via a
`docker-compose.yml`. It handles SteamCMD (app id 896660), the BepInEx doorstop
launcher, scheduled world backups, and mod loading. Key points to wire in:

- Mount `/srv/valheim/config` -> container `/config`.
- Env for server name / world / password / crossplay. **`-crossplay` is
  mandatory** for ModSentry (see SERVER-HANDOFF constraints).
- `-public 0` is fine — it only hides from the public browser; the crossplay join
  code still works.
- `Restart=unless-stopped` (compose) or run it under a systemd unit so it comes
  back on boot and on failure.

## 5. Mods and ModSentry

> **Valheim 1.0 status (2026-09-09):** Jotunn 2.29.2 crashes on 1.0 (server-side
> `SynchronizeInitialData` -> `ZRoutedRpc.Everybody` not found), blocking all joins.
> Jotunn + its dependents **Huginn Map** and **FarmGrid** are temporarily disabled
> (moved to `/srv/valheim/config/_disabled_mods_20260909/` on the VM; commented out in
> `valheim/mods.manifest`; dropped from the client docs). Active set: **ModSentry,
> DropThat, GlassPieces**. Re-enable the Jotunn stack once Jotunn ships a 1.0 build —
> Ethan will tell Claude when it does. Poll releases with `valheim/check-mod-updates.sh`.
>
> NOTE: the "Huginn is client-side only" guidance below is wrong for 1.0 — Jotunn's
> NetworkCompatibility makes Huginn mandatory on the server too, so Jotunn/Huginn are
> `plugin+required` (not just `required`) when re-enabled.

Follow `../valheim-mods/SERVER-HANDOFF.md` exactly for:

- BepInEx pack extraction and the `start_server_bepinex.sh` launcher.
- Which DLLs load in `BepInEx/plugins/` (ModSentry + DropThat server-side) vs.
  which are **policy reference copies** in `ModSentry_Required/` (incl. Jotunn!)
  and `ModSentry_Optional/` (FarmGrid).
- The DropThat loot config (`drop_that.drop_table.cfg`) — copy the verified file,
  and re-dump prefab ids on *this* server/version before trusting it.
- The version+hash pins. Client and server DLLs must be **byte-identical** or
  clients are kicked.

The lloesche image supports supplying BepInEx mods; decide whether to let it fetch
or to bake the pinned DLLs in from the manifest. **Pinning wins** here — ModSentry
demands exact hashes, so fetch-latest would break policy. Stage the exact DLLs
into the bind-mounted `/config/bepinex` tree.

## 6. Let friends in (no IP, no ports)

- Start the server; watch the logs for the **crossplay join code**.
- Give friends: **join code + server password + the exact client mod set** (same
  versions/hashes as the server policy). Anything mismatched is kicked by
  ModSentry.
- No router config. No port forwarding. The PlayFab relay handles NAT traversal,
  which is exactly why the wifi/NAT host setup in `01` is sufficient.

## 7. Snapshot discipline

- Take a Proxmox **snapshot before every mod/game update**. If an update bricks
  the server, roll back in seconds.
- Nightly/every-other-day **vzdump** of this whole guest is the "restore the whole
  Valheim box" path (see `03-backups.md`).

## Exit criteria for today

- Server boots, BepInEx loads, ModSentry active, crossplay code printed.
- A friend on a matching modded client joins successfully via the code.
- World + config live under the bind-mounted data dir, not inside the container.
