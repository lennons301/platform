#!/usr/bin/env bash
# Run conformity checks across the entire estate.
# Usage: check-estate.sh [--repos-dir <path>] [--include-archived]

source "$(dirname "$0")/lib.sh"
require_yq

SCRIPT_DIR="$(dirname "$0")"
PRODUCTS_DIR="$SCRIPT_DIR/../products"
REPOS_DIR="$HOME/code"
INCLUDE_ARCHIVED=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --repos-dir) REPOS_DIR="$2"; shift 2 ;;
    --include-archived) INCLUDE_ARCHIVED="--include-archived"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

echo ""
echo "Estate Conformity Report — $(date +%Y-%m-%d)"
echo "═══════════════════════════════════════"

TOTAL_PRODUCTS=0
TOTAL_GAPS=0

for product_yaml in "$PRODUCTS_DIR"/*.yaml; do
  name=$(product_name "$product_yaml")
  status=$(product_status "$product_yaml")

  if [ "$status" = "archived" ] && [ -z "$INCLUDE_ARCHIVED" ]; then
    continue
  fi

  project_path="$REPOS_DIR/$name"

  if [ ! -d "$project_path" ]; then
    echo "$name: skipped (repo not found at $project_path)"
    continue
  fi

  TOTAL_PRODUCTS=$((TOTAL_PRODUCTS + 1))

  # Run check-all and capture output + exit code (which is the gap count)
  output=$("$SCRIPT_DIR/check-all.sh" "$project_path" "$product_yaml" $INCLUDE_ARCHIVED 2>&1)
  gaps=$?
  echo "$output"
  TOTAL_GAPS=$((TOTAL_GAPS + gaps))

  echo ""
done

echo "═══════════════════════════════════════"
echo "$TOTAL_GAPS gap(s) found across $TOTAL_PRODUCTS product(s)."

if [ "$TOTAL_GAPS" -gt 0 ]; then
  echo "Run checks/create-issues.sh to file GitHub Issues."
fi
