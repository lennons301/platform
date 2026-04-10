#!/usr/bin/env bash
# Check environment conformity for a single project.
# Usage: check-environments.sh <project-path> <product-yaml-path>

source "$(dirname "$0")/lib.sh"

PROJECT_PATH="$1"
PRODUCT_YAML="$2"

if has_divergence "$PRODUCT_YAML" "environments"; then
  echo -e "  environments: ${DIVG} (intentional divergence)"
  exit 0
fi

ISSUES=()
CONTEXT_FILE=$(resolve_context_file "$PROJECT_PATH")

# Check context file documents environments
if [ -n "$CONTEXT_FILE" ]; then
  if ! grep -qiE '(dev|stg|prd|production|staging|local)' "$CONTEXT_FILE"; then
    ISSUES+=("project context does not document environments")
  fi
else
  ISSUES+=("no context file found")
fi

# Check for local dev setup
if [ ! -f "$PROJECT_PATH/docker-compose.yml" ] && \
   [ ! -f "$PROJECT_PATH/docker-compose.yaml" ] && \
   [ ! -f "$PROJECT_PATH/compose.yml" ] && \
   [ ! -f "$PROJECT_PATH/compose.yaml" ]; then
  # Supabase projects may use supabase config instead
  if [ ! -d "$PROJECT_PATH/supabase" ]; then
    ISSUES+=("no docker-compose or supabase config for local dev")
  fi
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  environments: ${PASS}"
elif [ ${#ISSUES[@]} -eq 1 ]; then
  echo -e "  environments: ${WARN} (${ISSUES[*]})"
  exit 1
else
  echo -e "  environments: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
