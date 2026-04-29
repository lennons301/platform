#!/usr/bin/env bash
# Check local-development conformity for a single project.
# Usage: check-local-development.sh <project-path> <product-yaml-path>
#
# See standards/local-development.md. Verifies the project has an isolated
# dev data store setup (local docker-compose, supabase config, or an
# explicitly declared remote-dev configuration) and that schema migration
# and seed commands exist for projects that have a database.

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
ISSUES=()

if has_divergence "$PRODUCT_YAML" "local-development"; then
  echo -e "  local-development: ${DIVG} (intentional divergence)"
  exit 0
fi

DB_CHOICE=$(yaml_get "$PRODUCT_YAML" '.choices.database')
ORM_CHOICE=$(yaml_get "$PRODUCT_YAML" '.choices.orm')
DEV_DATA_STORE=$(yaml_get "$PRODUCT_YAML" '.dev_data_store')

# Projects without a database skip the data-store checks entirely.
if [ -z "$DB_CHOICE" ] || [ "$DB_CHOICE" = "null" ]; then
  echo -e "  local-development: ${PASS} (no database)"
  exit 0
fi

# 1. Isolated dev data store. Either:
#    - a local service (docker-compose.yml with a db or supabase/ directory), or
#    - an explicit remote-dev declaration in the product YAML (dev_data_store: remote-neon-branch etc.)
has_local_service=false
if [ -f "$PROJECT_PATH/docker-compose.yml" ] || [ -f "$PROJECT_PATH/docker-compose.yaml" ] || \
   [ -f "$PROJECT_PATH/compose.yml" ] || [ -f "$PROJECT_PATH/compose.yaml" ]; then
  has_local_service=true
fi
if [ -d "$PROJECT_PATH/supabase" ]; then
  has_local_service=true
fi

has_remote_dev_declared=false
if [ -n "$DEV_DATA_STORE" ] && [ "$DEV_DATA_STORE" != "null" ]; then
  has_remote_dev_declared=true
fi

if [ "$has_local_service" = false ] && [ "$has_remote_dev_declared" = false ]; then
  ISSUES+=("no local dev service (docker-compose / supabase) and no dev_data_store declared in product YAML")
fi

# 2. Migration and seed commands exist. Scope the requirement to ORMs that
#    have migrations as a first-class concept — skip for supabase-client etc.
case "$ORM_CHOICE" in
  drizzle|prisma|typeorm|alembic|sqlalchemy)
    has_migrate=false
    has_seed=false
    if [ -f "$PROJECT_PATH/package.json" ]; then
      grep -qE '"db:migrate"\s*:' "$PROJECT_PATH/package.json" && has_migrate=true
      grep -qE '"db:seed"\s*:' "$PROJECT_PATH/package.json" && has_seed=true
    fi
    if [ -f "$PROJECT_PATH/justfile" ]; then
      grep -qE '^\s*db-migrate\b|^\s*db:migrate\b' "$PROJECT_PATH/justfile" && has_migrate=true
      grep -qE '^\s*db-seed\b|^\s*db:seed\b' "$PROJECT_PATH/justfile" && has_seed=true
    fi
    [ "$has_migrate" = false ] && ISSUES+=("no db:migrate command")
    [ "$has_seed" = false ] && ISSUES+=("no db:seed command")
    ;;
esac

# 3. Dev setup documented in context file.
CONTEXT_FILE=$(resolve_context_file "$PROJECT_PATH")
if [ -n "$CONTEXT_FILE" ]; then
  if ! grep -qiE '(local.?dev|dev.?setup|getting.?started|docker.?compose|supabase)' "$CONTEXT_FILE"; then
    ISSUES+=("context file does not document local dev setup")
  fi
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  local-development: ${PASS}"
  exit 0
else
  echo -e "  local-development: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
