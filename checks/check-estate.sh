#!/usr/bin/env bash
# Run conformity checks across the entire estate.
# Usage: check-estate.sh [--repos-dir <path>] [--products-dir <path>]
#                        [--include-archived] [--json <output-path>]
#
# --json writes a machine-readable snapshot consumed by create-issues.sh
# and the (planned) estate health dashboard.

source "$(dirname "$0")/lib.sh"
require_yq

SCRIPT_DIR="$(dirname "$0")"
PRODUCTS_DIR="$SCRIPT_DIR/../products"
REPOS_DIR="$HOME/code"
INCLUDE_ARCHIVED=""
JSON_OUT=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --repos-dir) REPOS_DIR="$2"; shift 2 ;;
    --products-dir) PRODUCTS_DIR="$2"; shift 2 ;;
    --include-archived) INCLUDE_ARCHIVED="--include-archived"; shift ;;
    --json) JSON_OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$JSON_OUT" ]; then
  require_jq
fi

echo ""
echo "Estate Conformity Report — $(date +%Y-%m-%d)"
echo "═══════════════════════════════════════"

TOTAL_PRODUCTS=0
TOTAL_GAPS=0
PRODUCT_DOCS=()

for product_yaml in "$PRODUCTS_DIR"/*.yaml; do
  name=$(product_name "$product_yaml")
  status=$(product_status "$product_yaml")
  category=$(product_category "$product_yaml")
  repo=$(yaml_get "$product_yaml" '.repo')

  if [ "$status" = "archived" ] && [ -z "$INCLUDE_ARCHIVED" ]; then
    continue
  fi

  project_path="$REPOS_DIR/$name"

  if [ ! -d "$project_path" ]; then
    echo "$name: skipped (repo not found at $project_path)"
    if [ -n "$JSON_OUT" ]; then
      PRODUCT_DOCS+=("$(jq -n \
        --arg name "$name" --arg repo "$repo" \
        --arg category "$category" --arg status "$status" \
        '{name: $name, repo: $repo, category: $category, status: $status,
          checked: false, skip_reason: "repo not found"}')")
    fi
    continue
  fi

  TOTAL_PRODUCTS=$((TOTAL_PRODUCTS + 1))

  # Run check-all and capture output + exit code (which is the gap count)
  output=$("$SCRIPT_DIR/check-all.sh" "$project_path" "$product_yaml" $INCLUDE_ARCHIVED 2>&1)
  gaps=$?
  echo "$output"
  TOTAL_GAPS=$((TOTAL_GAPS + gaps))

  if [ -n "$JSON_OUT" ]; then
    dims=$(echo "$output" | parse_check_output | jq -R -s '
      split("\n")
      | map(select(length > 0) | split("\t")
        | {dimension: .[0], status: .[1], details: .[2]})')
    PRODUCT_DOCS+=("$(jq -n \
      --arg name "$name" --arg repo "$repo" \
      --arg category "$category" --arg status "$status" \
      --argjson gaps "$gaps" --argjson dims "$dims" \
      '{name: $name, repo: $repo, category: $category, status: $status,
        checked: true, gap_count: $gaps, dimensions: $dims}')")
  fi

  echo ""
done

echo "═══════════════════════════════════════"
echo "$TOTAL_GAPS gap(s) found across $TOTAL_PRODUCTS product(s)."

if [ -n "$JSON_OUT" ]; then
  platform_commit=$(git -C "$SCRIPT_DIR/.." rev-parse --short HEAD 2>/dev/null || echo "unknown")
  { for doc in "${PRODUCT_DOCS[@]:-}"; do echo "$doc"; done; } | jq -s \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg platform_commit "$platform_commit" \
    --argjson total_gaps "$TOTAL_GAPS" \
    --argjson total_products "$TOTAL_PRODUCTS" \
    '{generated_at: $generated_at, platform_commit: $platform_commit,
      total_gaps: $total_gaps, total_products_checked: $total_products,
      products: (. | map(select(. != "")))}' > "$JSON_OUT"
  echo "Snapshot written to $JSON_OUT"
fi

if [ "$TOTAL_GAPS" -gt 0 ]; then
  echo "Run checks/create-issues.sh to file GitHub Issues."
fi
