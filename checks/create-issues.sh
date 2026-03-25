#!/usr/bin/env bash
# Create GitHub Issues for conformity gaps.
# Usage: create-issues.sh [--dry-run] [--repos-dir <path>]
#
# Reads product YAMLs and compares against manifest to find gaps,
# then creates issues on the target repos.
# Requires: gh CLI authenticated with repo scope.

source "$(dirname "$0")/lib.sh"
require_yq

SCRIPT_DIR="$(dirname "$0")"
PRODUCTS_DIR="$SCRIPT_DIR/../products"
MANIFEST="$SCRIPT_DIR/../versions/manifest.yaml"
DRY_RUN=""
REPOS_DIR="$HOME/code"

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN="true"; shift ;;
    --repos-dir) REPOS_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Ensure gh is available
if ! command -v gh &> /dev/null; then
  echo "ERROR: gh CLI is required." >&2
  exit 1
fi

CREATED=0
SKIPPED=0

create_issue_if_needed() {
  local repo="$1" title="$2" body="$3" marker="$4"

  # Ensure label exists
  if [ -z "$DRY_RUN" ]; then
    gh label create "platform-upgrade" --repo "$repo" --color "0E8A16" \
      --description "Automated platform conformity upgrade" --force 2>/dev/null || true
  fi

  # Check for existing open issue with same marker.
  # Search for the marker text without HTML comment tags (GitHub may not index HTML comments).
  local search_text
  search_text=$(echo "$marker" | sed 's/<!-- //;s/ -->//')
  existing=$(gh issue list --repo "$repo" --state open --search "$search_text" --json number --jq '.[0].number' 2>/dev/null || echo "")

  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    echo "  SKIP: issue #$existing already open on $repo"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  if [ -n "$DRY_RUN" ]; then
    echo "  DRY RUN: would create issue on $repo: $title"
    CREATED=$((CREATED + 1))
    return
  fi

  gh issue create --repo "$repo" --title "$title" --label "platform-upgrade" --body "$body"
  echo "  CREATED: $title on $repo"
  CREATED=$((CREATED + 1))
}

# Check version gaps and create issues
for product_yaml in "$PRODUCTS_DIR"/*.yaml; do
  name=$(product_name "$product_yaml")
  status=$(product_status "$product_yaml")
  repo=$(yaml_get "$product_yaml" '.repo')

  if [ "$status" = "archived" ]; then continue; fi
  if [ -z "$repo" ] || [ "$repo" = "null" ]; then continue; fi

  echo "Checking $name ($repo)..."

  # Version gaps
  for section in runtimes frameworks languages tooling; do
    keys=$(yq eval ".$section | keys | .[]" "$MANIFEST" 2>/dev/null)
    for key in $keys; do
      category=$(product_category "$product_yaml")
      target=$(yq eval ".overrides.$category.$key // .$section.$key" "$MANIFEST" 2>/dev/null)
      actual=$(yaml_get "$product_yaml" ".versions.$key")

      if [ -z "$target" ] || [ "$target" = "null" ]; then continue; fi
      if [ -z "$actual" ] || [ "$actual" = "null" ]; then continue; fi

      actual_major=$(echo "$actual" | cut -d. -f1)
      target_major=$(echo "$target" | cut -d. -f1)
      actual_minor=$(echo "$actual" | cut -d. -f2 -s)
      target_minor=$(echo "$target" | cut -d. -f2 -s)
      [ -z "$actual_minor" ] && actual_minor=0
      [ -z "$target_minor" ] && target_minor=0

      is_gap=false
      if [ "$actual_major" -lt "$target_major" ] 2>/dev/null; then
        is_gap=true
      elif [ "$actual_major" -eq "$target_major" ] 2>/dev/null && \
           [ "$actual_minor" -lt "$target_minor" ] 2>/dev/null; then
        is_gap=true
      fi

      if [ "$is_gap" = "true" ]; then
        marker="<!-- platform-check:versions/$key/$name -->"
        title="[platform] Upgrade $key to $target"
        body="## Gap
- **Product:** $name
- **Standard:** versions/manifest.yaml
- **Current:** $key $actual
- **Target:** $key $target

## Context
Platform repo: versions/manifest.yaml
Product config: products/$name.yaml

$marker"
        create_issue_if_needed "$repo" "$title" "$body" "$marker"
      fi
    done
  done

  # Secrets gap
  secrets_choice=$(yaml_get "$product_yaml" '.choices.secrets')
  if [ "$secrets_choice" = "pending-migration" ]; then
    if ! has_divergence "$product_yaml" "secrets"; then
      marker="<!-- platform-check:secrets/provider/$name -->"
      title="[platform] Migrate secrets to Doppler"
      body="## Gap
- **Product:** $name
- **Standard:** standards/secrets.md
- **Current:** $secrets_choice
- **Target:** doppler

## Context
Platform repo: choices/secrets-provider.md
Product config: products/$name.yaml

$marker"
      create_issue_if_needed "$repo" "$title" "$body" "$marker"
    fi
  fi
done

echo ""
echo "Done. Created: $CREATED, Skipped (already open): $SKIPPED"
