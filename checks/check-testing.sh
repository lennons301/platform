#!/usr/bin/env bash
# Check testing conformity for a single project.
# Usage: check-testing.sh <project-path> <product-yaml-path>
#
# See standards/testing.md. Verifies that a test command exists and is
# reachable via the project's command runner.

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
ISSUES=()

if has_divergence "$PRODUCT_YAML" "testing"; then
  echo -e "  testing: ${DIVG} (intentional divergence)"
  exit 0
fi

PKG_MANAGER=$(yaml_get "$PRODUCT_YAML" '.package_manager')

# 1. A test command exists.
has_test_cmd=false

# package.json scripts.test
if [ -f "$PROJECT_PATH/package.json" ]; then
  if grep -qE '"test"\s*:' "$PROJECT_PATH/package.json"; then
    has_test_cmd=true
  fi
fi

# justfile test recipe
if [ -f "$PROJECT_PATH/justfile" ]; then
  if grep -qE '^\s*test\b' "$PROJECT_PATH/justfile"; then
    has_test_cmd=true
  fi
fi

# pyproject.toml test dep (pytest) as a fallback signal for uv projects
if [ "$has_test_cmd" = false ] && [ "$PKG_MANAGER" = "uv" ] && [ -f "$PROJECT_PATH/pyproject.toml" ]; then
  if grep -qE '(pytest|unittest)' "$PROJECT_PATH/pyproject.toml"; then
    has_test_cmd=true
  fi
fi

if [ "$has_test_cmd" = false ]; then
  ISSUES+=("no test command found (package.json scripts.test or justfile test recipe)")
fi

# 2. Tests are documented in the context file.
CONTEXT_FILE=$(resolve_context_file "$PROJECT_PATH")
if [ -n "$CONTEXT_FILE" ]; then
  if ! grep -qiE '(test|vitest|jest|pytest)' "$CONTEXT_FILE"; then
    ISSUES+=("context file does not document test command")
  fi
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  testing: ${PASS}"
  exit 0
else
  echo -e "  testing: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
