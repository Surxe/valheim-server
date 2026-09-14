#!/bin/bash
# stage-mods.sh — deploy the authoritative mod set into the BepInEx tree with the
# ModSentry policy layout. Runs INSIDE the Valheim VM. Idempotent.
#
# DLL source per mod: ./dll/<dll> if present (byte-exact repo copy); else download the
# pinned Thunderstore zip and extract <dll>. Either way the DLL is SHA-256 verified.
#
#   plugin   -> BepInEx/plugins/<name>/<dll>            (loaded on the server)
#   required -> BepInEx/config/ModSentry_Required/<dll> (hash reference copy)
#   optional -> BepInEx/config/ModSentry_Optional/<dll> (hash reference copy)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${HERE}/mods.manifest"
DLLDIR="${HERE}/dll"
CACHE="${HERE}/mod-cache"; mkdir -p "$CACHE"
BEPINEX=/srv/valheim/config/bepinex
# lloesche symlinks the runtime BepInEx/config -> /config/bepinex, so the BepInEx CONFIG
# dir IS /config/bepinex itself (NOT /config/bepinex/config). ModSentry reads its policy
# folders from BepInEx/config, i.e. directly under /config/bepinex — putting them a level
# deeper means ModSentry finds no policy. Same for the DropThat loot cfg.
PLUGINS="${BEPINEX}/plugins"
CFG="${BEPINEX}"
REQ="${CFG}/ModSentry_Required"
OPT="${CFG}/ModSentry_Optional"

[ -d "$BEPINEX" ] || { echo "BepInEx tree missing ($BEPINEX). Start the server once (BEPINEX=true) first."; exit 1; }
mkdir -p "$PLUGINS" "$REQ" "$OPT" "$CFG"
# Clear prior staging so removed mods don't linger. Wipe ALL plugin dirs (not a hand-kept
# name list): a mod ever staged as a plugin — including a temporary load-test of a client-only
# mod — must not survive into the runtime mirror below. $PLUGINS holds only our staged mods
# (BepInEx core lives in the runtime tree, not here), so this is safe.
rm -rf "${PLUGINS:?}"/*
rm -f "$REQ"/*.dll "$OPT"/*.dll

resolve_dll() {  # sets DLLPATH for name/dll/sha/url; verifies sha256
  local name="$1" dll="$2" sha="$3" url="$4"
  if [ -f "${DLLDIR}/${dll}" ]; then DLLPATH="${DLLDIR}/${dll}"
  else
    local zip="${CACHE}/${name}.zip"
    [ -f "$zip" ] || curl -sSL -o "$zip" "$url"
    local ex="${CACHE}/${name}"; rm -rf "$ex"; mkdir -p "$ex"; unzip -oq "$zip" -d "$ex"
    DLLPATH="$(find "$ex" -type f -name "$dll" | head -1)"
    [ -n "$DLLPATH" ] || { echo "  $dll not found in $url"; exit 1; }
  fi
  echo "${sha}  ${DLLPATH}" | sha256sum -c - >/dev/null || { echo "  SHA MISMATCH: $dll"; exit 1; }
}

while IFS='|' read -r name version dll sha role url; do
  case "$name" in ''|\#*) continue;; esac
  name="${name//[[:space:]]/}"; dll="${dll//[[:space:]]/}"; sha="${sha//[[:space:]]/}"
  role="${role//[[:space:]]/}"; url="${url//[[:space:]]/}"
  resolve_dll "$name" "$dll" "$sha" "$url"
  case "$role" in *plugin*)  install -D "$DLLPATH" "${PLUGINS}/${name}/${dll}"; echo "plugin   ${name}/${dll}";; esac
  case "$role" in *required*) cp "$DLLPATH" "${REQ}/${dll}"; echo "required ${dll}";;
                  *optional*) cp "$DLLPATH" "${OPT}/${dll}"; echo "optional ${dll}";; esac
done < "$MANIFEST"

[ -f "${HERE}/drop_that.drop_table.cfg" ] && cp "${HERE}/drop_that.drop_table.cfg" "${CFG}/drop_that.drop_table.cfg" && echo "config   drop_that.drop_table.cfg"
[ -f "${HERE}/drummercraig.one_map_to_rule_them_all.cfg" ] && cp "${HERE}/drummercraig.one_map_to_rule_them_all.cfg" "${CFG}/drummercraig.one_map_to_rule_them_all.cfg" && echo "config   drummercraig.one_map_to_rule_them_all.cfg"
mkdir -p "${CFG}/OneMapToRuleThemAll"
[ -f "${HERE}/OneMapToRuleThemAll.catalog.txt" ] && cp "${HERE}/OneMapToRuleThemAll.catalog.txt" "${CFG}/OneMapToRuleThemAll/OneMapToRuleThemAll.catalog.txt" && echo "config   OneMapToRuleThemAll/OneMapToRuleThemAll.catalog.txt"

# lloesche only ADDITIVELY syncs /config/bepinex/plugins into its runtime tree (no
# delete), and does not always re-sync on a plain restart. So mirror /config into the
# runtime tree ourselves — exact match — otherwise removed mods linger, and a wiped
# tree comes up EMPTY (0 plugins, ModSentry off). After this, a container restart loads
# exactly the /config set.
RUNTIME_PLUGINS=/srv/valheim/data/bepinex/BepInEx/plugins
if [ -d "$(dirname "$RUNTIME_PLUGINS")" ]; then
  mkdir -p "$RUNTIME_PLUGINS"; rm -rf "${RUNTIME_PLUGINS:?}"/*
  cp -a "$PLUGINS"/. "$RUNTIME_PLUGINS"/
  echo "mirrored /config plugins -> runtime cache ($(ls -1 "$RUNTIME_PLUGINS" | tr '\n' ' '))"
fi

echo; echo "== plugins (loaded) =="; ls -1 "$PLUGINS"
echo "== ModSentry_Required =="; ls -1 "$REQ"
echo "== ModSentry_Optional =="; ls -1 "$OPT"
echo; echo "Restart to load:  docker compose -f /srv/valheim/docker-compose.yml restart"
