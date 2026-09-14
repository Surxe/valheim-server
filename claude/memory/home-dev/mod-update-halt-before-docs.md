---
name: mod-update-halt-before-docs
description: When adding/updating Valheim mods, stop after the server is up and verified — get Ethan's confirmation before writing docs or updating the client mod docs
metadata:
  type: feedback
---

When **adding or updating mods** on the Valheim server, treat "server is back up and
verified" as a **checkpoint, not the finish line**. Once the container is running and the
mod change is confirmed working (mods loaded, no crash-on-connect, ModSentry policy sane),
**halt and wait for Ethan to confirm** before doing either of the follow-on steps:

- **creating/updating docs** (README notes, `docs/`, memory state, changelog), and
- **updating the client mod docs** (`valheim/client-modpack/INSTALL.md` and `README.md`).

**Why:** the server working is necessary but not sufficient. Ethan may still want to
tweak the set, roll it back, or hold the change before it's written down and — especially —
before the **client-facing mod docs** are updated (that's what friends read to install the
set; an unconfirmed version written there means everyone re-installs a set that might change
again). The verification step is the natural place to pause and let him make that call.

**How to apply:** do the mod edit → apply to VM → verify the server is up, then **stop and
report**: what changed, that it's verified, and that docs are pending his OK. Only after he
confirms, update the docs. See [[valheim-server]].
