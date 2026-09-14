#!/bin/bash
# mod-fetch.sh — vet + stage a Thunderstore Valheim mod for mods.manifest.
#
# Resolves a package on Thunderstore, downloads the pinned (or latest) version, extracts its
# DLL, computes the SHA-256, shows its dependencies + CHANGELOG head, drops the DLL into
# ./dll/, and prints a ready-to-paste mods.manifest line — you fill in the ROLE. It does NOT
# edit mods.manifest (role + the explanatory comment are a human/skill judgement).
#
# Usage:
#   ./mod-fetch.sh <thunderstore-package-url>
#   ./mod-fetch.sh <Author> <Package> [version]
# e.g.
#   ./mod-fetch.sh https://thunderstore.io/c/valheim/p/Azumatt/FirstPersonMode/
#   ./mod-fetch.sh Azumatt FirstPersonMode          # latest
#   ./mod-fetch.sh Azumatt FirstPersonMode 1.3.12   # pinned
#
# Everything human-facing goes to stderr; the last stdout line is the manifest line, so you can
#   MODLINE="$(./mod-fetch.sh ... 2>/dev/tty | tail -1)"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DLLDIR="$HERE/dll"

# --- parse args -> AUTHOR / PKG / VERSION(optional) ---
AUTHOR=""; PKG=""; VERSION=""
if [[ "${1:-}" == http*://* ]]; then
  IFS='/' read -ra P <<< "${1%/}"
  for ((i=0; i<${#P[@]}; i++)); do
    if [[ "${P[i]}" == "p" || "${P[i]}" == "download" ]]; then
      AUTHOR="${P[i+1]:-}"; PKG="${P[i+2]:-}"; VERSION="${P[i+3]:-}"; break
    fi
  done
else
  AUTHOR="${1:-}"; PKG="${2:-}"; VERSION="${3:-}"
fi
[[ -n "$AUTHOR" && -n "$PKG" ]] || {
  echo "usage: $0 <thunderstore-url> | <Author> <Package> [version]" >&2; exit 2; }

API="https://thunderstore.io/api/experimental/package/${AUTHOR}/${PKG}/"
echo ">> querying $API" >&2
META="$(curl -fsSL "$API")" || { echo "package not found: $AUTHOR/$PKG" >&2; exit 1; }

# resolve version + download_url; print deps/desc to stderr; emit "<version> <download_url>" to stdout
INFO="$(python3 - "$META" "$VERSION" <<'PY'
import sys, json
meta = json.loads(sys.argv[1]); want = sys.argv[2].strip()
latest = meta["latest"]
if want and want != latest["version_number"]:
    v = next((x for x in meta.get("versions", []) if x["version_number"] == want), None)
    if v is None: sys.exit("version %r not found for %s" % (want, meta["full_name"]))
else:
    v = latest
deps = v.get("dependencies", [])
nonbep = [d for d in deps if "BepInExPack" not in d]
sys.stderr.write("package : %s\n" % meta["full_name"])
sys.stderr.write("version : %s\n" % v["version_number"])
sys.stderr.write("deps    : %s\n" % (", ".join(deps) if deps else "(none)"))
if nonbep:
    sys.stderr.write("  NOTE  : depends on more than BepInEx -> %s (must also be in the mod set)\n"
                     % ", ".join(nonbep))
sys.stderr.write("desc    : %s\n" % (v.get("description", "")[:200]))
print(v["version_number"], v["download_url"])
PY
)"
read -r RES_VERSION DLURL <<< "$INFO"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo ">> downloading $DLURL" >&2
curl -fsSL -o "$TMP/pkg.zip" "$DLURL"
unzip -oq "$TMP/pkg.zip" -d "$TMP/ex"

# pick the DLL: the only one, else the one whose basename matches the package name
mapfile -t DLLS < <(cd "$TMP/ex" && find . -name '*.dll' -printf '%P\n' | sort)
[ "${#DLLS[@]}" -gt 0 ] || { echo "no .dll found in package" >&2; exit 1; }
DLL=""
if [ "${#DLLS[@]}" -eq 1 ]; then
  DLL="${DLLS[0]}"
else
  for d in "${DLLS[@]}"; do [[ "$(basename "$d" .dll)" == "$PKG" ]] && { DLL="$d"; break; }; done
  [ -n "$DLL" ] || { echo "multiple DLLs — copy the right one into dll/ by hand:" >&2
                     printf '  %s\n' "${DLLS[@]}" >&2; exit 1; }
fi
DLLBASE="$(basename "$DLL")"
SHA="$(sha256sum "$TMP/ex/$DLL" | cut -d' ' -f1)"

CL="$(cd "$TMP/ex" && find . -iname 'CHANGELOG.md' | head -1 || true)"
if [ -n "$CL" ]; then echo ">> CHANGELOG.md (head):" >&2; head -20 "$TMP/ex/$CL" >&2; echo >&2; fi

mkdir -p "$DLLDIR"; cp "$TMP/ex/$DLL" "$DLLDIR/$DLLBASE"
echo ">> copied DLL -> dll/$DLLBASE ($(stat -c%s "$DLLDIR/$DLLBASE") bytes)" >&2
echo >&2
echo ">> mods.manifest line (replace ROLE with plugin|required|optional, combine with '+'):" >&2
echo "${PKG}|${RES_VERSION}|${DLLBASE}|${SHA}|ROLE|${DLURL}"
