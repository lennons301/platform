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

# Resolve the context file (AGENTS.md if referenced, otherwise CLAUDE.md)
CONTEXT_FILE=$(resolve_context_file "$PROJECT_PATH")
if [ -z "$CONTEXT_FILE" ]; then
  echo -e "  documentation: ${FAIL} (no context file found)"
  exit 1
fi

# If CLAUDE.md references @AGENTS.md, verify AGENTS.md exists
if grep -q "@AGENTS.md" "$PROJECT_PATH/CLAUDE.md" && [ ! -f "$PROJECT_PATH/AGENTS.md" ]; then
  ISSUES+=("CLAUDE.md references @AGENTS.md but file missing")
fi

# Check required sections in the context file (case-insensitive heading search)
for section in "command" "stack|tech" "convention"; do
  if ! grep -qiE "^#.*($section)" "$CONTEXT_FILE"; then
    ISSUES+=("missing section: $section")
  fi
done

# Check platform context pointer
if ! grep -qi "platform" "$CONTEXT_FILE"; then
  ISSUES+=("no platform context pointer")
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  documentation: ${PASS}"
else
  echo -e "  documentation: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
