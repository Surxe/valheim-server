# BaldurianQuat — Valheim client mods (documentation)

This directory is **documentation only** — there is no distributable modpack zip and no
setup/build script. The server enforces the mod set itself (ModSentry compares each client's
mod versions + SHA-256 against the server policy), so the source of truth for what clients
must install is the server plus the docs here.

- `INSTALL.md` — the client install guide: **the mod table** (required / optional / skip at
  their exact pinned Thunderstore versions), how to install via r2modman or manually, and the
  join-code / password notes. That table is the single place the client set is written down.
- `../mods.manifest` — the authoritative manifest the server enforces (mod name, version,
  SHA-256, role, Thunderstore download URL).
