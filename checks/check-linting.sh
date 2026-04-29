#!/usr/bin/env bash
# Check linting conformity for a single project.
# Usage: check-linting.sh <project-path> <product-yaml-path>
#
# See standards/linting.md. Verifies linter config is checked into the
# repo, a pre-commit hook runs the linter, and the linter is reachable
# via the project's command runner.

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"
ISSUES=()

if has_divergence "$PRODUCT_YAML" "linting"; then
  echo -e "  linting: ${DIVG} (intentional divergence)"
  exit 0
fi

LINT_CHOICE=$(yaml_get "$PRODUCT_YAML" '.choices.linting')

# 1. Linter config checked in. Required filename depends on the choice.
has_config=false
case "$LINT_CHOICE" in
  biome)
    [ -f "$PROJECT_PATH/biome.json" ] || [ -f "$PROJECT_PATH/biome.jsonc" ] && has_config=true
    if [ "$has_config" = false ]; then
      ISSUES+=("no biome.json (linting=biome)")
    fi
    ;;
  eslint)
    for f in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts .eslintrc .eslintrc.js .eslintrc.json .eslintrc.cjs; do
      [ -f "$PROJECT_PATH/$f" ] && has_config=true && break
    done
    if [ "$has_config" = false ]; then
      ISSUES+=("no eslint config (linting=eslint)")
    fi
    ;;
  ruff)
    if [ -f "$PROJECT_PATH/ruff.toml" ] || [ -f "$PROJECT_PATH/.ruff.toml" ]; then
      has_config=true
    elif [ -f "$PROJECT_PATH/pyproject.toml" ] && grep -q '\[tool.ruff' "$PROJECT_PATH/pyproject.toml"; then
      has_config=true
    fi
    if [ "$has_config" = false ]; then
      ISSUES+=("no ruff config (linting=ruff)")
    fi
    ;;
  "")
    ISSUES+=("no linting choice declared in product YAML")
    ;;
  *)
    ISSUES+=("unknown linting choice: $LINT_CHOICE")
    ;;
esac

# 2. Pre-commit hook runs the linter.
has_hook=false
hook_runs_lint=false

if [ -f "$PROJECT_PATH/.husky/pre-commit" ]; then
  has_hook=true
  if grep -qiE '(lint|biome|eslint|ruff|lint-staged)' "$PROJECT_PATH/.husky/pre-commit"; then
    hook_runs_lint=true
  fi
fi

if [ "$has_hook" = false ] && [ -f "$PROJECT_PATH/.pre-commit-config.yaml" ]; then
  has_hook=true
  if grep -qiE '(biome|eslint|ruff|lint)' "$PROJECT_PATH/.pre-commit-config.yaml"; then
    hook_runs_lint=true
  fi
fi

if [ "$has_hook" = false ] && [ -f "$PROJECT_PATH/lefthook.yml" ]; then
  has_hook=true
  if grep -qiE '(biome|eslint|ruff|lint)' "$PROJECT_PATH/lefthook.yml"; then
    hook_runs_lint=true
  fi
fi

if [ "$has_hook" = false ]; then
  ISSUES+=("no pre-commit hook (.husky/pre-commit, .pre-commit-config.yaml, or lefthook.yml)")
elif [ "$hook_runs_lint" = false ]; then
  ISSUES+=("pre-commit hook does not run linter")
fi

# 3. Lint command reachable via command runner.
has_lint_cmd=false
if [ -f "$PROJECT_PATH/package.json" ] && grep -qE '"lint"\s*:' "$PROJECT_PATH/package.json"; then
  has_lint_cmd=true
fi
if [ -f "$PROJECT_PATH/justfile" ] && grep -qE '^\s*lint\b' "$PROJECT_PATH/justfile"; then
  has_lint_cmd=true
fi
if [ "$has_lint_cmd" = false ]; then
  ISSUES+=("no lint command in command runner")
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  linting: ${PASS}"
  exit 0
else
  echo -e "  linting: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
