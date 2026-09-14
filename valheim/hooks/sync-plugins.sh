#!/bin/bash
# sync-plugins.sh — lloesche/valheim-server PRE_SERVER_RUN_HOOK.
#
# Re-sync the staged BepInEx mods into the runtime tree before EVERY server
# (re)start. The image only syncs /config/bepinex/plugins -> the runtime tree in
# valheim-bootstrap, which runs on CONTAINER start. But the in-place restart the
# auto-updater does after a game/BepInEx update (`supervisorctl restart
# valheim-server`) skips bootstrap, and a game update rebuilds the runtime BepInEx
# tree with an EMPTY plugins/ dir -> the server relaunches with 0 mods. That is
# exactly what happened on the Valheim 1.0 update (2026-09-09): the game updated
# to l-1.0.7 and the server came back modless.
#
# run_server() in /usr/local/bin/valheim-server calls pre_server_run_hook on every
# launch, including the updater's restart, so pointing PRE_SERVER_RUN_HOOK at this
# script closes the gap. Paths below are CONTAINER paths.
#
# Fail-open: this must never prevent the server from starting.

SRC=/config/bepinex/plugins
DST=/opt/valheim/bepinex/BepInEx/plugins

if [ "${BEPINEX:-false}" = "true" ] && [ -d "$SRC" ]; then
    mkdir -p "$DST"
    rsync -a --delete --itemize-changes "$SRC/" "$DST/"
    rc=$?
    n=$(find "$DST" -name '*.dll' 2>/dev/null | wc -l)
    if [ "$rc" -eq 0 ]; then
        echo "sync-plugins: synced staged mods -> runtime ($n plugin dll(s))"
    else
        echo "sync-plugins: WARNING rsync rc=$rc; continuing server start ($n dll(s) present)" >&2
    fi
fi

exit 0
