#!/usr/bin/env bash
# Check documentation conformity for a single project.
# Enforces standards/agent-context.md + standards/documentation.md:
# AGENTS.md is the single context file; tool-specific files (CLAUDE.md)
# reference it with @AGENTS.md rather than duplicating its content.
# Usage: check-documentation.sh <project-path> <product-yaml-path>

source "$(dirname "$0")/lib.sh"

PROJECT_PATH="$1"
# shellcheck disable=SC2034  # unused here, but every check takes the same two args
PRODUCT_YAML="$2"
ISSUES=()

# AGENTS.md is the required context file — a monolithic CLAUDE.md does not comply
if [ ! -f "$PROJECT_PATH/AGENTS.md" ]; then
  echo -e "  documentation: ${FAIL} (no AGENTS.md — see standards/agent-context.md)"
  exit 1
fi

CONTEXT_FILE="$PROJECT_PATH/AGENTS.md"

# CLAUDE.md must exist and be a reference to AGENTS.md
if [ ! -f "$PROJECT_PATH/CLAUDE.md" ]; then
  ISSUES+=("no CLAUDE.md (should reference @AGENTS.md)")
elif ! grep -q "@AGENTS.md" "$PROJECT_PATH/CLAUDE.md"; then
  ISSUES+=("CLAUDE.md does not reference @AGENTS.md")
fi

# Check required sections in AGENTS.md (case-insensitive heading search)
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
