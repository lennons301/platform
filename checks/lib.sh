#!/usr/bin/env bash
# Shared helpers for conformity check scripts.
# Source this file: source "$(dirname "$0")/lib.sh"

set -uo pipefail
# NOTE: do NOT use set -e here. Check scripts return non-zero exit codes
# to signal gaps, and callers must be able to count failures without
# the shell terminating on the first one.

# Colours (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; NC=''
fi

# The four status symbols are read by the scripts that source this file, which
# is why each one carries an unused-variable exemption.
# shellcheck disable=SC2034
PASS="${GREEN}✓${NC}"
# shellcheck disable=SC2034
FAIL="${RED}✗${NC}"
# shellcheck disable=SC2034
WARN="${YELLOW}~${NC}"
# shellcheck disable=SC2034
DIVG="${GREEN}✓*${NC}"

# Check that yq is available
require_yq() {
  if ! command -v yq &> /dev/null; then
    echo "ERROR: yq is required but not installed." >&2
    echo "Install: https://github.com/mikefarah/yq#install" >&2
    exit 1
  fi
}

# Read a YAML field. Usage: yaml_get <file> <path>
yaml_get() {
  yq eval "$2" "$1" 2>/dev/null || echo ""
}

# Check if a standard has a documented divergence.
# Usage: has_divergence <product-yaml> <standard-name>
# Returns 0 (true) if divergence exists, 1 (false) if not.
has_divergence() {
  local product_yaml="$1"
  local standard="$2"
  local count
  count=$(yq eval ".divergences[] | select(.standard == \"$standard\") | length" "$product_yaml" 2>/dev/null | wc -l)
  [ "$count" -gt 0 ]
}

# Get product status
product_status() {
  yaml_get "$1" '.status'
}

# Get product category
product_category() {
  yaml_get "$1" '.category'
}

# Get product name
product_name() {
  yaml_get "$1" '.name'
}

# Resolve the project context file. If CLAUDE.md contains "@AGENTS.md",
# return the path to AGENTS.md. Otherwise return CLAUDE.md.
# Usage: resolve_context_file <project-path>
resolve_context_file() {
  local project_path="$1"
  local claude_md="$project_path/CLAUDE.md"
  local agents_md="$project_path/AGENTS.md"

  if [ -f "$claude_md" ] && grep -q "@AGENTS.md" "$claude_md" && [ -f "$agents_md" ]; then
    echo "$agents_md"
  elif [ -f "$claude_md" ]; then
    echo "$claude_md"
  else
    echo ""
  fi
}

# Check that jq is available
require_jq() {
  if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed." >&2
    echo "Install: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

# ISO-8601 UTC timestamp -> epoch seconds on stdout; empty and non-zero when
# it cannot be parsed. GNU and BSD `date` disagree on the flags, so try both:
# on macOS the GNU form alone makes every timestamp look unreadable.
iso_to_epoch() {
  date -u -d "$1" +%s 2>/dev/null ||
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null
}

# Is the gh CLI available and authenticated? Prints why not on stdout and
# returns 1; returns 0 silently when it is.
# Checks that read the GitHub API use this to warn-and-skip rather than let
# absent credentials count as a conformity gap — a machine without a token
# knows nothing about the repo either way (see check-review-gate.sh).
gh_ready() {
  if ! command -v gh &> /dev/null; then
    echo "gh CLI not installed"
    return 1
  fi
  if ! gh auth status &> /dev/null; then
    echo "gh CLI not authenticated"
    return 1
  fi
}

# Parse check output into TSV: dimension<TAB>status<TAB>details
# Reads stdin, writes stdout. Non-matching lines are ignored.
# Symbol mapping: ✓ -> pass, ✗ -> fail, ✓* -> divergence, ~ -> warn.
# NOTE: this makes the check output line format a contract. If a check
# script changes its output shape, update this parser and test-parse.sh.
parse_check_output() {
  local line dim sym details status
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]][[:space:]]([a-z-]+):[[:space:]](✓\*|✓|✗|~)([[:space:]]\((.*)\))?$ ]]; then
      dim="${BASH_REMATCH[1]}"
      sym="${BASH_REMATCH[2]}"
      details="${BASH_REMATCH[4]:-}"
      case "$sym" in
        "✓*") status="divergence" ;;
        "✓")  status="pass" ;;
        "✗")  status="fail" ;;
        "~")  status="warn" ;;
      esac
      printf '%s\t%s\t%s\n' "$dim" "$status" "$details"
    fi
  done
}
