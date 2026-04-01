#!/usr/bin/env bash
# Run all conformity checks against a single project.
# Usage: check-all.sh <project-path> <product-yaml-path> [--include-archived]

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
INCLUDE_ARCHIVED="${3:-}"
SCRIPT_DIR="$(dirname "$0")"

NAME=$(product_name "$PRODUCT_YAML")
STATUS=$(product_status "$PRODUCT_YAML")

# Skip archived unless requested
if [ "$STATUS" = "archived" ] && [ "$INCLUDE_ARCHIVED" != "--include-archived" ]; then
  echo "$NAME: skipped (archived)"
  exit 0
fi

echo "$NAME:"

TOTAL_GAPS=0

# Run each check, count failures
for check in check-secrets check-versions check-environments check-documentation check-architecture; do
  if ! "$SCRIPT_DIR/$check.sh" "$PROJECT_PATH" "$PRODUCT_YAML"; then
    TOTAL_GAPS=$((TOTAL_GAPS + 1))
  fi
done

exit $TOTAL_GAPS
