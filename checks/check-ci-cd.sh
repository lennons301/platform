#!/usr/bin/env bash
# Check CI/CD conformity for a single project.
# Usage: check-ci-cd.sh <project-path> <product-yaml-path>
#
# See standards/ci-cd.md. Verifies that PR-time checks exist, that deploys
# are wired up for the chosen hosting, and that CI installs from the
# lockfile. Branch-protection and hosting-platform-side checks are out of
# scope for a local static check.

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
ISSUES=()

if has_divergence "$PRODUCT_YAML" "ci-cd"; then
  echo -e "  ci-cd: ${DIVG} (intentional divergence)"
  exit 0
fi

CI_CHOICE=$(yaml_get "$PRODUCT_YAML" '.choices.ci_cd')
HOSTING=$(yaml_get "$PRODUCT_YAML" '.choices.hosting')
PKG_MANAGER=$(yaml_get "$PRODUCT_YAML" '.package_manager')

# Only github-actions is supported by this check today.
if [ "$CI_CHOICE" != "github-actions" ]; then
  echo -e "  ci-cd: ${WARN} (no check for ci_cd=$CI_CHOICE)"
  exit 0
fi

WF_DIR="$PROJECT_PATH/.github/workflows"
WF_FILES=()
if [ -d "$WF_DIR" ]; then
  while IFS= read -r -d '' f; do WF_FILES+=("$f"); done \
    < <(find "$WF_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
fi

if [ ${#WF_FILES[@]} -eq 0 ]; then
  echo -e "  ci-cd: ${FAIL} (no .github/workflows/ directory)"
  exit 1
fi

# Gather workflow contents once.
WF_CONTENT=$(cat "${WF_FILES[@]}" 2>/dev/null)

# 1. At least one workflow triggers on pull_request.
if ! echo "$WF_CONTENT" | grep -qE '^\s*(pull_request|pull_request_target):'; then
  ISSUES+=("no workflow triggers on pull_request")
fi

# 2. PR workflow runs at least one of lint/test/type-check.
if ! echo "$WF_CONTENT" | grep -qiE '(lint|biome|eslint|ruff|test|vitest|jest|pytest|tsc|type-?check)'; then
  ISSUES+=("PR workflows do not run lint/test/type-check")
fi

# 3. Lockfile-only installs in CI.
case "$PKG_MANAGER" in
  pnpm)
    if echo "$WF_CONTENT" | grep -qE 'pnpm\s+(install|i)\b' && \
       ! echo "$WF_CONTENT" | grep -qE 'pnpm\s+(install|i)\b.*--frozen-lockfile'; then
      ISSUES+=("pnpm install without --frozen-lockfile")
    fi
    ;;
  npm)
    if echo "$WF_CONTENT" | grep -qE 'npm\s+install\b' && \
       ! echo "$WF_CONTENT" | grep -qE 'npm\s+ci\b'; then
      ISSUES+=("npm install used instead of npm ci")
    fi
    ;;
  uv)
    if echo "$WF_CONTENT" | grep -qE 'uv\s+sync\b' && \
       ! echo "$WF_CONTENT" | grep -qE 'uv\s+sync\b.*--frozen'; then
      ISSUES+=("uv sync without --frozen")
    fi
    ;;
esac

# 4. Deploy path. Vercel-hosted projects deploy via the git integration, not
#    workflows, so skip that check for them. Self-hosted projects must have a
#    workflow that triggers on push to main.
case "$HOSTING" in
  vercel*|netlify*|cloudflare-pages)
    ;;
  *)
    if ! echo "$WF_CONTENT" | grep -qE '^\s*push:' || \
       ! echo "$WF_CONTENT" | grep -qE 'branches:\s*\[?\s*(main|master)'; then
      ISSUES+=("no workflow triggers on push to main")
    fi
    ;;
esac

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  ci-cd: ${PASS}"
  exit 0
else
  echo -e "  ci-cd: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
