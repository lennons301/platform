#!/usr/bin/env bash
# Check version conformity for a single project.
# Usage: check-versions.sh <project-path> <product-yaml-path>

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
SCRIPT_DIR="$(dirname "$0")"
MANIFEST="$SCRIPT_DIR/../versions/manifest.yaml"

if [ ! -f "$MANIFEST" ]; then
  echo -e "  versions: ${FAIL} manifest not found: $MANIFEST"
  exit 1
fi

CATEGORY=$(product_category "$PRODUCT_YAML")
GAPS=()

# Compare a single version. Conformant if actual >= target (floor, not pin).
# Major-only target "22": any 22.x satisfies.
# Minor target "5.7": any 5.7.x or higher satisfies. 5.3 would NOT satisfy.
check_version() {
  local key="$1" actual="$2" target="$3"
  if [ -z "$actual" ] || [ "$actual" = "null" ]; then
    GAPS+=("$key: unknown → $target")
    return
  fi
  local actual_major actual_minor target_major target_minor
  actual_major=$(echo "$actual" | cut -d. -f1)
  target_major=$(echo "$target" | cut -d. -f1)
  # Extract minor version; default to 0 if not present
  actual_minor=$(echo "$actual" | cut -d. -f2 -s)
  target_minor=$(echo "$target" | cut -d. -f2 -s)
  [ -z "$actual_minor" ] && actual_minor=0
  [ -z "$target_minor" ] && target_minor=0

  if [ "$actual_major" -lt "$target_major" ] 2>/dev/null; then
    GAPS+=("$key: $actual → $target")
  elif [ "$actual_major" -eq "$target_major" ] 2>/dev/null && \
       [ "$actual_minor" -lt "$target_minor" ] 2>/dev/null; then
    GAPS+=("$key: $actual → $target")
  fi
}

# Iterate version categories in manifest
for section in runtimes frameworks languages tooling; do
  keys=$(yq eval ".$section | keys | .[]" "$MANIFEST" 2>/dev/null)
  for key in $keys; do
    # Get target: check category override first, then default
    target=$(yq eval ".overrides.$CATEGORY.$key // .$section.$key" "$MANIFEST" 2>/dev/null)
    if [ -z "$target" ] || [ "$target" = "null" ]; then continue; fi

    # Get actual from product YAML
    actual=$(yaml_get "$PRODUCT_YAML" ".versions.$key")

    check_version "$key" "$actual" "$target"
  done
done

if [ ${#GAPS[@]} -eq 0 ]; then
  echo -e "  versions: ${PASS}"
else
  echo -e "  versions: ${FAIL} (${GAPS[*]})"
  exit 1
fi
