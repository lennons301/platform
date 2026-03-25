#!/usr/bin/env bash
# Check secrets conformity for a single project.
# Usage: check-secrets.sh <project-path> <product-yaml-path>

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"

if [ ! -d "$PROJECT_PATH" ]; then
  echo -e "  secrets: ${FAIL} project path not found: $PROJECT_PATH"
  exit 1
fi

# Check for documented divergence
if has_divergence "$PRODUCT_YAML" "secrets"; then
  echo -e "  secrets: ${DIVG} (intentional divergence)"
  exit 0
fi

SECRETS_CHOICE=$(yaml_get "$PRODUCT_YAML" '.choices.secrets')
ISSUES=()

case "$SECRETS_CHOICE" in
  doppler)
    # Check for Doppler config
    if [ ! -f "$PROJECT_PATH/doppler.yaml" ] && [ ! -f "$PROJECT_PATH/.doppler.yaml" ]; then
      ISSUES+=("no doppler.yaml found")
    fi
    # Check for committed .env files
    if git -C "$PROJECT_PATH" ls-files '*.env' '*.env.*' --error-unmatch 2>/dev/null | grep -q '.'; then
      ISSUES+=("committed .env files found in git")
    fi
    # Check CLAUDE.md references doppler
    if [ -f "$PROJECT_PATH/CLAUDE.md" ]; then
      if ! grep -qi "doppler" "$PROJECT_PATH/CLAUDE.md"; then
        ISSUES+=("CLAUDE.md does not reference Doppler")
      fi
    fi
    ;;
  pending-migration)
    ISSUES+=("not yet migrated to Doppler")
    ;;
  env-file)
    # env-file without a divergence is non-conformant
    ISSUES+=("using env-file without documented divergence")
    ;;
  *)
    ISSUES+=("unknown secrets choice: $SECRETS_CHOICE")
    ;;
esac

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  secrets: ${PASS}"
else
  echo -e "  secrets: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
