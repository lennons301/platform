#!/usr/bin/env bash
# Check documentation conformity for a single project.
# Enforces standards/documentation.md + standards/agent-context.md:
#   - README.md exists and is written for this project (scaffold boilerplate
#     left in place counts as no README)
#   - AGENTS.md is the single context file and carries the required sections
#   - tool-specific files (CLAUDE.md, GEMINI.md, copilot-instructions.md) are
#     thin pointers to AGENTS.md, never a second copy of it
#   - AGENTS.md stays a size an agent can afford to load every session (warn)
# Usage: check-documentation.sh <project-path> <product-yaml-path>

source "$(dirname "$0")/lib.sh"

PROJECT_PATH="$1"
# shellcheck disable=SC2034  # unused here, but every check takes the same two args
PRODUCT_YAML="$2"
ISSUES=()
WARNINGS=()

# Thresholds. Env-tunable so the tests can exercise them without big fixtures.
AGENTS_MD_MAX_BYTES="${AGENTS_MD_MAX_BYTES:-49152}"  # 48 KiB ≈ 12k tokens paid on every session
AGENTS_MD_MAX_LINE="${AGENTS_MD_MAX_LINE:-2000}"     # longer than this is a paragraph in disguise
TOOL_FILE_MAX_LINES="${TOOL_FILE_MAX_LINES:-40}"     # non-blank lines a "thin pointer" may run to

# AGENTS.md is the required context file — a monolithic CLAUDE.md does not comply
if [ ! -f "$PROJECT_PATH/AGENTS.md" ]; then
  echo -e "  documentation: ${FAIL} (no AGENTS.md — see standards/agent-context.md)"
  exit 1
fi

CONTEXT_FILE="$PROJECT_PATH/AGENTS.md"

# README.md — human onboarding. Scaffold text nobody replaced is not a README.
README_BOILERPLATE='Welcome to your Lovable project|bootstrapped with .*create-next-app|Getting Started with Create React App|This template provides a minimal setup to get React working in Vite'
if [ ! -f "$PROJECT_PATH/README.md" ]; then
  ISSUES+=("no README.md")
elif grep -qiE "$README_BOILERPLATE" "$PROJECT_PATH/README.md"; then
  ISSUES+=("README.md is scaffold boilerplate")
fi

# Tool-specific files point at AGENTS.md and add only tool-specific
# instructions. CLAUDE.md is required (the estate runs Claude Code); the
# others are checked when present. "Thin pointer" is enforced two ways: none
# of AGENTS.md's sections may reappear, and the file stays short.
if [ ! -f "$PROJECT_PATH/CLAUDE.md" ]; then
  ISSUES+=("no CLAUDE.md (should reference @AGENTS.md)")
fi
SECTION_HEADINGS='^#.*(command|stack|tech|convention|structure|overview)'
for tool_file in CLAUDE.md GEMINI.md .github/copilot-instructions.md; do
  path="$PROJECT_PATH/$tool_file"
  [ -f "$path" ] || continue
  case "$tool_file" in
    CLAUDE.md|GEMINI.md)
      # These tools import with an @file directive; that is the reference.
      grep -q "@AGENTS.md" "$path" || ISSUES+=("$tool_file does not reference @AGENTS.md") ;;
    *)
      grep -q "AGENTS.md" "$path" || ISSUES+=("$tool_file does not reference AGENTS.md") ;;
  esac
  if grep -qiE "$SECTION_HEADINGS" "$path"; then
    ISSUES+=("$tool_file duplicates AGENTS.md sections (should be a thin pointer)")
  else
    nonblank=$(grep -c '[^[:space:]]' "$path")
    if [ "$nonblank" -gt "$TOOL_FILE_MAX_LINES" ]; then
      ISSUES+=("$tool_file is not a thin pointer ($nonblank non-blank lines)")
    fi
  fi
done

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

# Size. AGENTS.md is loaded into every agent session, so its size is a cost
# paid on every task; past these limits the fix is a linked doc, not a gap.
agents_bytes=$(wc -c < "$CONTEXT_FILE")
if [ "$agents_bytes" -gt "$AGENTS_MD_MAX_BYTES" ]; then
  WARNINGS+=("AGENTS.md is $((agents_bytes / 1024))KB, over $((AGENTS_MD_MAX_BYTES / 1024))KB — move reference detail into linked docs/")
fi
long_lines=$(awk -v max="$AGENTS_MD_MAX_LINE" 'length > max' "$CONTEXT_FILE" | wc -l)
if [ "$long_lines" -gt 0 ]; then
  WARNINGS+=("AGENTS.md has $long_lines line(s) over $AGENTS_MD_MAX_LINE chars — break them up or move them out")
fi

# Report. Warnings never count as gaps: exit 0, and no ✓ line so the snapshot
# records the dimension as warn (same shape as check-architecture.sh).
if [ ${#WARNINGS[@]} -gt 0 ]; then
  for warning in "${WARNINGS[@]}"; do
    echo -e "  documentation: ${WARN} ($warning)"
  done
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  if [ ${#WARNINGS[@]} -eq 0 ]; then
    echo -e "  documentation: ${PASS}"
  fi
  exit 0
else
  echo -e "  documentation: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
