#!/usr/bin/env bash
# Check architecture diagram conformity for a single project.
# Usage: check-architecture.sh <project-path> <product-yaml-path>

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
ARCH_DIR="$PROJECT_PATH/docs/architecture"
ISSUES=()
WARNINGS=()

# Check for documented divergence
if has_divergence "$PRODUCT_YAML" "architecture-diagrams"; then
  echo -e "  architecture: ${DIVG} (intentional divergence)"
  exit 0
fi

# 1. Check docs/architecture/ directory exists
if [ ! -d "$ARCH_DIR" ]; then
  echo -e "  architecture: ${FAIL} (no docs/architecture/ directory)"
  exit 1
fi

# 2. Check mandatory diagrams exist
for diagram in context containers; do
  if [ ! -f "$ARCH_DIR/$diagram.puml" ]; then
    ISSUES+=("missing mandatory $diagram.puml")
  fi
done

# 3. Check optional declared diagrams exist
DIAGRAM_COUNT=$(yq eval '.architecture.diagrams | length' "$PRODUCT_YAML" 2>/dev/null)
if [ "$DIAGRAM_COUNT" != "null" ] && [ "$DIAGRAM_COUNT" != "0" ] && [ -n "$DIAGRAM_COUNT" ]; then
  for i in $(seq 0 $((DIAGRAM_COUNT - 1))); do
    diagram=$(yq eval ".architecture.diagrams[$i]" "$PRODUCT_YAML")
    # Skip mandatory ones already checked
    if [ "$diagram" = "context" ] || [ "$diagram" = "containers" ]; then
      continue
    fi
    # Check for exact match or pattern match (components-*, dynamic-*)
    found=false
    if [ -f "$ARCH_DIR/$diagram.puml" ]; then
      found=true
    elif ls "$ARCH_DIR"/${diagram}-*.puml 1>/dev/null 2>&1; then
      found=true
    fi
    if [ "$found" = false ]; then
      ISSUES+=("declared diagram missing: $diagram")
    fi
  done
fi

# 4+5. Validate C4 content in each .puml file
if ls "$ARCH_DIR"/*.puml 1>/dev/null 2>&1; then
  for puml_file in "$ARCH_DIR"/*.puml; do
    basename=$(basename "$puml_file")
    # Check for C4-PlantUML include
    if ! grep -q '!include.*C4_' "$puml_file"; then
      ISSUES+=("$basename: no C4-PlantUML include")
    fi
    # Check for at least one C4 model element
    if ! grep -qE '(Person|System|Container|System_Boundary|System_Ext|ContainerDb|Deployment_Node|Rel)\(' "$puml_file"; then
      ISSUES+=("$basename: no C4 model elements found")
    fi
  done
fi

# 6. Check rendered SVGs exist
if ls "$ARCH_DIR"/*.puml 1>/dev/null 2>&1; then
  for puml_file in "$ARCH_DIR"/*.puml; do
    basename=$(basename "$puml_file" .puml)
    if [ ! -f "$ARCH_DIR/rendered/$basename.svg" ]; then
      WARNINGS+=("rendered/$basename.svg missing (CI may not have run)")
    fi
  done
fi

# 7. Staleness check
if [ ${#ISSUES[@]} -eq 0 ] && ls "$ARCH_DIR"/*.puml 1>/dev/null 2>&1; then
  # Get last commit touching diagrams
  diagram_commit=$(git -C "$PROJECT_PATH" log -1 --format='%ct' -- "docs/architecture/*.puml" 2>/dev/null || echo "0")

  # Get staleness paths from YAML or use defaults
  STALE_PATHS=()
  STALE_COUNT=$(yq eval '.architecture.staleness_paths | length' "$PRODUCT_YAML" 2>/dev/null)
  if [ "$STALE_COUNT" != "null" ] && [ "$STALE_COUNT" != "0" ] && [ -n "$STALE_COUNT" ]; then
    for i in $(seq 0 $((STALE_COUNT - 1))); do
      STALE_PATHS+=($(yq eval ".architecture.staleness_paths[$i]" "$PRODUCT_YAML"))
    done
  else
    # Defaults
    STALE_PATHS=("docker-compose.yml" "docker-compose.yaml" "vercel.json" "supabase/")
  fi

  for path in "${STALE_PATHS[@]}"; do
    if [ -e "$PROJECT_PATH/$path" ] || ls "$PROJECT_PATH"/$path 1>/dev/null 2>&1; then
      path_commit=$(git -C "$PROJECT_PATH" log -1 --format='%ct' -- "$path" 2>/dev/null || echo "0")
      if [ "$path_commit" -gt "$diagram_commit" ] 2>/dev/null; then
        WARNINGS+=("diagrams may be stale ($path changed more recently)")
        break
      fi
    fi
  done
fi

# Report
if [ ${#WARNINGS[@]} -gt 0 ]; then
  for warning in "${WARNINGS[@]}"; do
    echo -e "  architecture: ${WARN} ($warning)"
  done
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  if [ ${#WARNINGS[@]} -eq 0 ]; then
    echo -e "  architecture: ${PASS}"
  fi
  exit 0
else
  echo -e "  architecture: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
