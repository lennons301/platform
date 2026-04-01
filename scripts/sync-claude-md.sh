#!/usr/bin/env bash
# Sync the global ~/.claude/CLAUDE.md from the platform repo's canonical template.
#
# Usage:
#   ./scripts/sync-claude-md.sh           # show diff and prompt before applying
#   ./scripts/sync-claude-md.sh --force   # apply without prompting
#
# On a fresh machine: creates ~/.claude/ and installs the template.
# On an existing machine: shows what changed and replaces the file (backs up first).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/claude-md-global.md"
TARGET="$HOME/.claude/CLAUDE.md"
FORCE="${1:-}"

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: Template not found at $TEMPLATE" >&2
  exit 1
fi

# Fresh install
if [ ! -f "$TARGET" ]; then
  mkdir -p "$(dirname "$TARGET")"
  cp "$TEMPLATE" "$TARGET"
  echo "Installed $TARGET (fresh)"
  exit 0
fi

# Check if already in sync
if diff -q "$TEMPLATE" "$TARGET" > /dev/null 2>&1; then
  echo "Already up to date."
  exit 0
fi

# Show diff
echo "Changes to apply to $TARGET:"
echo ""
diff --color=auto -u "$TARGET" "$TEMPLATE" || true
echo ""

if [ "$FORCE" != "--force" ]; then
  read -rp "Apply these changes? [y/N] " answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "Aborted."
    exit 0
  fi
fi

# Backup and apply
BACKUP="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
cp "$TARGET" "$BACKUP"
cp "$TEMPLATE" "$TARGET"
echo "Updated $TARGET (backup at $BACKUP)"
