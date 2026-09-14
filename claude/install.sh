#!/usr/bin/env bash
# claude/install.sh — deploy valheim-server's agent context (skills + memory) into the
# dev user's neutral `~/.agents` root, then symlink the Claude-specific paths into
# `~/.claude` and render the DeepSeek Harness memory into `~/.dsh/memory`. Copy-based
# (dev owns these files) and additive. Idempotent.
#
# This repo does NOT ship a box-global AGENTS.md — that stays owned by the home-server
# repo. valheim-server only ADDS its Valheim skills + memory notes to the shared store.
#
# The per-project memory index (~/.agents/memory/MEMORY.md) is SHARED with the host repo:
# each repo drops its curated index as a fragment under memory/.index.d/<NN>-<repo>.md and
# the live MEMORY.md is their concatenation in name order — so both installers rebuild it
# identically regardless of run order. The DeepSeek index is merged by --memory-id.
#
# Runnable standalone as dev (no root), or as a step of ../install.sh (run as root, in
# which case the writes are done AS dev via runuser). Mirrors home-server/claude/install.sh.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEV_HOME="$(getent passwd dev | cut -d: -f6)"; DEV_HOME="${DEV_HOME:-/home/dev}"
CLAUDE_DIR="$DEV_HOME/.claude"
AGENTS_DIR="$DEV_HOME/.agents"
DSH_HOME_DIR="$DEV_HOME/.dsh"
DEV_ENV_REPO="$HERE/../../dev-env"

MEMORY_ID="valheim-server"          # dsh index section + shared MEMORY.md fragment id
FRAGMENT_NAME="20-valheim-server.md" # sorts AFTER home-server's 10-home-server.md

# Run a command AS dev: directly if we already are dev, else via runuser (root only).
as_dev() {
  if [ "$(id -un)" = dev ]; then "$@"; else runuser -u dev -- "$@"; fi
}
say() { printf '  %s\n' "$*"; }

# Point a live ~/.claude/~/.dsh path at a neutral ~/.agents target, as dev.
# Idempotent; a pre-existing real file/dir (the one-time migration) is moved aside
# to <path>.pre-agents rather than deleted.
ensure_agents_symlink() {   # $1 = target (must exist), $2 = link path
  local target="$1" link="$2"
  as_dev bash -c '
    set -euo pipefail
    target="$1"; link="$2"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      echo "  symlink: target missing: $target" >&2; exit 1
    fi
    if [ -L "$link" ]; then
      [ "$(readlink "$link")" = "$target" ] && exit 0
      rm -f "$link"
    elif [ -e "$link" ]; then
      bak="$link.pre-agents"
      rm -rf "$bak"
      mv "$link" "$bak"
      echo "  symlink: moved existing $link -> $bak"
    fi
    mkdir -p "$(dirname "$link")"
    ln -s "$target" "$link"
    echo "  symlink: $link -> $target"
  ' _ "$target" "$link"
}

echo "== valheim-server context install (-> $AGENTS_DIR, symlinked into $CLAUDE_DIR) =="

# 1. Skills -> neutral skills dir (dsh reads ~/.agents/skills natively). Additive; skill
#    dir names are unique across repos, so this never collides with home-server's skills.
if [ -d "$HERE/skills" ]; then
  as_dev mkdir -p "$AGENTS_DIR/skills"
  as_dev cp -a "$HERE/skills/." "$AGENTS_DIR/skills/"
  say "skills -> $AGENTS_DIR/skills/  ($(ls -1 "$HERE/skills" | tr '\n' ' '))"
  ensure_agents_symlink "$AGENTS_DIR/skills" "$CLAUDE_DIR/skills"
fi

# 2. Memory -> project-scoped. One subdir per project under memory/.
if [ -d "$HERE/memory" ]; then
  for d in "$HERE"/memory/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    dst="$AGENTS_DIR/memory"
    as_dev mkdir -p "$dst" "$dst/.index.d"

    # 2a. Note files -> the shared store (everything EXCEPT the index fragment), additive.
    as_dev bash -c '
      set -euo pipefail
      d="$1"; dst="$2"
      for f in "$d"*.md; do
        [ -e "$f" ] || continue
        b="$(basename "$f")"
        case "$b" in MEMORY.md|MEMORY.*) continue;; esac
        install -D -m 0644 "$f" "$dst/$b"
      done
    ' _ "$d" "$dst"

    # 2b. This repo's curated index -> its fragment, then reassemble the shared MEMORY.md.
    if [ -f "${d}MEMORY.md" ]; then
      as_dev install -D -m 0644 "${d}MEMORY.md" "$dst/.index.d/$FRAGMENT_NAME"
    fi
    as_dev bash -c '
      set -euo pipefail
      dst="$1"
      if compgen -G "$dst/.index.d/*.md" >/dev/null; then
        cat "$dst"/.index.d/*.md > "$dst/MEMORY.md"
      fi
    ' _ "$dst"
    say "memory ($name) -> $dst  (fragment $FRAGMENT_NAME)"
    ensure_agents_symlink "$dst" "$CLAUDE_DIR/projects/-$name/memory"

    # 2c. DeepSeek Harness: same notes, memory-standard layout, keyed by --memory-id so
    #     this repo's notes merge with (don't clobber) the host repo's dsh index section.
    if [ -f "$DEV_ENV_REPO/lib/memory-standard.py" ]; then
      as_dev python3 "$DEV_ENV_REPO/lib/memory-standard.py" render --src "$d" --dst "$DSH_HOME_DIR/memory" --memory-id "$MEMORY_ID" || \
        say "!! dsh memory render failed (see above)"
    else
      say "memory: no $DEV_ENV_REPO/lib/memory-standard.py — skipping dsh memory"
    fi
  done
fi

echo "valheim-server context installed."
