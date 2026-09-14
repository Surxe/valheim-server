# BaldurianQuat — Valheim client mods (install guide)

> ⚠️ **Valheim 1.0 mod set.** Install exactly the mods in the table below, at the exact
> versions listed. The server (ModSentry) checks every mod's version + hash and **kicks any
> client that doesn't match** — so don't let mods auto-update, and don't add extras.

To join the **BaldurianQuat** server you must run this **exact** mod set. The **server
password** and the **join code** are shared separately (not in this doc). The join code is a
crossplay code and **changes whenever the server restarts** (e.g. on update days) — but once
you've joined once, Valheim remembers the server in your **Join Game list** and you can rejoin
from there without re-entering a code. So a freshly-shared code only matters for your **first**
join (or if you clear the saved entry).

---

## The mods (exact versions — must match the server)

| Mod | Version | Thunderstore package | Install? |
|---|---|---|---|
| BepInEx pack | 5.4.2350 | denikson / BepInExPack_Valheim | ✅ dependency |
| ModSentry | 1.0.19 | Landoria / ModSentry | ✅ required |
| Drop That | 3.1.5 | ASharpPen / Drop_That | ✅ required |
| Jotunn (library) | 2.30.0 | ValheimModding / Jotunn | ✅ required |
| BetterCarts | 1.1.1 | TastyChickenLegs / BetterCarts | ✅ required |
| OneMapToRuleThemAll | 2.8.1 | DrummerCraig / OneMapToRuleThemAll | ✅ required |
| GlassPieces | 1.2.7 | blacks7ar / GlassPieces | ✅ required |
| FarmGrid | 1.0.0 | Galateam / FarmGrid | ➖ optional |
| FirstPersonMode | 1.3.12 | Azumatt / FirstPersonMode | ➖ optional |
| FavoriteItems | 1.2.0 | ronaldoniz / FavoriteItems | ➖ optional |
| Unshamed | 1.0.4 | Azumatt / Unshamed | ➖ optional (achievements) |

**Install?** ✅ required = you're kicked without it. ➖ optional = client-side preference,
install it or not, either way you can join. The authoritative manifest the server enforces is
`../mods.manifest`.

### Achievements (Unshamed — optional)

Valheim 1.0 refuses Steam achievements to anyone running mods, so playing here normally blocks
them. **Unshamed** (Azumatt) unblocks them locally — install it if you want achievements while
playing on BaldurianQuat. It's **client-side and personal**: it changes nothing on the server or
for other players, and it does **not** grant free unlocks (you still have to actually do the thing;
spawned/cheated items are still flagged as cheated by the game as normal).

After installing, open its config (`BepInEx/config/Azumatt.Unshamed.cfg`, generated on first
launch — or edit it in r2modman's config editor) and set:

```
Enable Retroactive = true
```

That grants the achievements you'd **already earned** (once, on the next load). Leave it off and
you'll only start banking achievements from that point forward. Steam only — Xbox/Game Pass use a
separate achievement system this doesn't affect.

---

## Method A — r2modman / Thunderstore Mod Manager (recommended, easiest)

Cross-platform, handles BepInEx for you, and pulls the exact files (so hashes match).

1. Install **r2modman** (or Thunderstore Mod Manager) and pick **Valheim**.
2. Create a new profile, e.g. `BaldurianQuat`.
3. Install each ✅/➖ package above **at the exact version listed** (use the package's
   *Versions* tab if it defaults to a newer one). Installing Jotunn and Drop That will
   offer BepInEx as a dependency — accept it (5.4.2350).
4. Launch **Start Modded** once, load any world, then quit (lets the mods initialize).
5. Launch modded → Join Game → **Join by code** → enter the code → enter the password
   (code + password shared separately).

Do **not** click "update" on these mods later — versions must stay pinned to the server.

---

## Method B — Manual install (download the DLLs from Thunderstore)

Use this if you already have BepInEx set up, or prefer manual.

1. Install **BepInExPack_Valheim 5.4.2350** into your Valheim folder first
   (from Thunderstore: denikson / BepInExPack_Valheim). On Windows this means copying
   `winhttp.dll`, `doorstop_config.ini`, and the `BepInEx/` folder into the game dir
   (…/steamapps/common/Valheim). Launch once so BepInEx generates its folders, then quit.
2. For each ✅/➖ mod in the table above, open its Thunderstore page, switch to the exact
   **version listed**, and download the zip. Extract its `.dll` into your game's
   `…/Valheim/BepInEx/plugins/` folder.
3. Launch the game once, then quit.
4. Join: Join by code → enter the code → enter the password (both shared separately).

The exact SHA-256 for each mod's DLL is in `../mods.manifest` (the server enforces the same
hashes) if you want to verify a download by hand.

---

## If you get disconnected immediately

That's almost always ModSentry rejecting a mod mismatch (not a network issue). Make your
profile match the table exactly: every ✅ mod present at the exact version, no ❌ mods, and no
other Valheim mods (**extra** mods are rejected too). If ModSentry is installed it tells you
on-screen exactly what's wrong. Also double-check you used the **current** join code (it
changes on server restart).
