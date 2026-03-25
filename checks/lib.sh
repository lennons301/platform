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

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}~${NC}"
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
