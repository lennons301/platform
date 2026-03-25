#!/usr/bin/env bash
# Check documentation conformity for a single project.
# Usage: check-documentation.sh <project-path> <product-yaml-path>

source "$(dirname "$0")/lib.sh"

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
ISSUES=()

# Check CLAUDE.md exists
if [ ! -f "$PROJECT_PATH/CLAUDE.md" ]; then
  echo -e "  documentation: ${FAIL} (no CLAUDE.md)"
  exit 1
fi

CLAUDE_MD="$PROJECT_PATH/CLAUDE.md"

# Check required sections (case-insensitive heading search)
for section in "command" "stack|tech" "convention"; do
  if ! grep -qiE "^#.*($section)" "$CLAUDE_MD"; then
    ISSUES+=("missing section: $section")
  fi
done

# Check platform context pointer
if ! grep -qi "platform" "$CLAUDE_MD"; then
  ISSUES+=("no platform context pointer")
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  documentation: ${PASS}"
else
  echo -e "  documentation: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
