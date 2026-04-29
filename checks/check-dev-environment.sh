#!/usr/bin/env bash
# Check dev-environment conformity for a single project.
# Usage: check-dev-environment.sh <project-path> <product-yaml-path>
#
# See standards/dev-environment.md. Verifies a version-manager config and a
# command runner with the expected named commands exist in the repo root.

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
ISSUES=()

if has_divergence "$PRODUCT_YAML" "dev-environment"; then
  echo -e "  dev-environment: ${DIVG} (intentional divergence)"
  exit 0
fi

DEV_CHOICE=$(yaml_get "$PRODUCT_YAML" '.choices.dev_environment')

# 1. Version-manager config checked in.
has_version_manager=false
if [ -f "$PROJECT_PATH/.mise.toml" ] || [ -f "$PROJECT_PATH/mise.toml" ]; then
  has_version_manager=true
elif [ -f "$PROJECT_PATH/.tool-versions" ]; then
  has_version_manager=true
fi
if [ "$has_version_manager" = false ]; then
  ISSUES+=("no version-manager config (.mise.toml or .tool-versions)")
fi

# 2. Command runner exists and has the expected recipes.
has_runner=false
if [ -f "$PROJECT_PATH/justfile" ] || [ -f "$PROJECT_PATH/Justfile" ]; then
  has_runner=true
  JUSTFILE="$PROJECT_PATH/justfile"
  [ -f "$PROJECT_PATH/Justfile" ] && JUSTFILE="$PROJECT_PATH/Justfile"

  # Check for expected recipe names (loosely: line that starts with the name).
  missing_recipes=()
  for recipe in setup dev lint test; do
    if ! grep -qE "^\s*${recipe}\b" "$JUSTFILE"; then
      missing_recipes+=("$recipe")
    fi
  done
  if [ ${#missing_recipes[@]} -gt 0 ]; then
    ISSUES+=("justfile missing recipes: ${missing_recipes[*]}")
  fi
fi

if [ "$has_runner" = false ]; then
  case "$DEV_CHOICE" in
    mise-just)
      ISSUES+=("no justfile (dev_environment=mise-just)")
      ;;
    *)
      ISSUES+=("no command runner found (justfile)")
      ;;
  esac
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  dev-environment: ${PASS}"
  exit 0
else
  echo -e "  dev-environment: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
