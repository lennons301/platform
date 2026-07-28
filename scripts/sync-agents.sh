#!/usr/bin/env bash
# Sync canonical agent definitions from the platform repo to ~/.claude/agents/.
#
# Usage:
#   ./scripts/sync-agents.sh           # show diffs and prompt before applying
#   ./scripts/sync-agents.sh --force   # apply without prompting
#
# Same pattern as sync-claude-md.sh: the platform repo is the source of
# truth; local copies are synced installs, backed up before replacement.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../templates/agents"
TARGET_DIR="$HOME/.claude/agents"
FORCE="${1:-}"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: No agent templates at $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
CHANGED=0

for template in "$SOURCE_DIR"/*.md; do
  name="$(basename "$template")"
  target="$TARGET_DIR/$name"

  if [ ! -f "$target" ]; then
    cp "$template" "$target"
    echo "Installed $target (fresh)"
    continue
  fi

  if diff -q "$template" "$target" > /dev/null 2>&1; then
    echo "$name: already up to date."
    continue
  fi

  echo "Changes to apply to $target:"
  echo ""
  diff --color=auto -u "$target" "$template" || true
  echo ""

  if [ "$FORCE" != "--force" ]; then
    read -rp "Apply these changes to $name? [y/N] " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
      echo "Skipped $name."
      continue
    fi
  fi

  BACKUP="$target.bak.$(date +%Y%m%d%H%M%S)"
  cp "$target" "$BACKUP"
  cp "$template" "$target"
  echo "Updated $target (backup at $BACKUP)"
  CHANGED=$((CHANGED + 1))
done
