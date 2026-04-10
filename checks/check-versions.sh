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
PKG_MANAGER=$(yaml_get "$PRODUCT_YAML" '.package_manager')
GAPS=()

# Compare a single version. Conformant if actual >= target (floor, not pin).
check_version() {
  local key="$1" actual="$2" target="$3"
  if [ -z "$actual" ] || [ "$actual" = "null" ]; then
    GAPS+=("$key: unknown → $target")
    return
  fi
  local actual_major actual_minor target_major target_minor
  actual_major=$(echo "$actual" | cut -d. -f1)
  target_major=$(echo "$target" | cut -d. -f1)
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

# Detect actual version from project files.
# For runtimes/frameworks/languages: check product YAML first.
# For tooling: check .mise.toml and package.json devDependencies.
detect_version() {
  local key="$1"
  local version=""

  # 1. Check product YAML versions section
  version=$(yaml_get "$PRODUCT_YAML" ".versions.$key")
  if [ -n "$version" ] && [ "$version" != "null" ]; then
    echo "$version"
    return
  fi

  # 2. Check .mise.toml for runtime/tooling versions
  if [ -f "$PROJECT_PATH/.mise.toml" ]; then
    # mise.toml format: key = "version" under [tools]
    local mise_version
    mise_version=$(grep -E "^${key}\s*=" "$PROJECT_PATH/.mise.toml" 2>/dev/null | sed 's/.*=\s*"\?\([^"]*\)"\?/\1/' | tr -d ' ')
    if [ -n "$mise_version" ]; then
      echo "$mise_version"
      return
    fi
  fi

  # 3. Check package.json devDependencies for tooling (e.g. biome, drizzle-kit)
  if [ -f "$PROJECT_PATH/package.json" ]; then
    local pkg_key="$key"
    # Map tool names to package names
    case "$key" in
      biome) pkg_key="@biomejs/biome" ;;
      drizzle-kit) pkg_key="drizzle-kit" ;;
    esac
    local pkg_version
    pkg_version=$(grep "\"$pkg_key\"" "$PROJECT_PATH/package.json" 2>/dev/null | head -1 | sed 's/.*: *"\^*~*\([0-9][^"]*\)".*/\1/')
    if [ -n "$pkg_version" ]; then
      echo "$pkg_version"
      return
    fi
  fi

  echo ""
}

# Determine which tools are relevant for this project's ecosystem
is_relevant_tool() {
  local key="$1"
  case "$key" in
    # Python-only tools — skip for JS/TS projects
    uv|ruff)
      [ "$PKG_MANAGER" = "uv" ] && return 0 || return 1
      ;;
    # JS/TS-only tools — skip for Python projects
    pnpm|biome)
      [ "$PKG_MANAGER" = "pnpm" ] || [ "$PKG_MANAGER" = "npm" ] && return 0 || return 1
      ;;
    # Meta-tools (installed globally, not per-project)
    mise|just)
      return 1
      ;;
    # Universal tools
    *)
      return 0
      ;;
  esac
}

# Iterate version categories in manifest
for section in runtimes frameworks languages tooling; do
  keys=$(yq eval ".$section | keys | .[]" "$MANIFEST" 2>/dev/null)
  for key in $keys; do
    # Skip tools not relevant to this project's ecosystem
    if ! is_relevant_tool "$key"; then
      continue
    fi

    # Get target: check category override first, then default
    target=$(yq eval ".overrides.$CATEGORY.$key // .$section.$key" "$MANIFEST" 2>/dev/null)
    if [ -z "$target" ] || [ "$target" = "null" ]; then continue; fi

    # Detect actual version from project files
    actual=$(detect_version "$key")

    check_version "$key" "$actual" "$target"
  done
done

if [ ${#GAPS[@]} -eq 0 ]; then
  echo -e "  versions: ${PASS}"
else
  echo -e "  versions: ${FAIL} (${GAPS[*]})"
  exit 1
fi
