#!/usr/bin/env bash
# Create GitHub Issues for conformity gaps recorded in a snapshot.
# Usage: create-issues.sh [--dry-run] [--snapshot <path>]
#
# Consumes the JSON snapshot emitted by `check-estate.sh --json` and files
# one issue per (product, failed dimension). Passing dimensions, documented
# divergences, and unchecked products generate no issues.
# Requires: jq; gh CLI authenticated with repo scope (not needed for --dry-run).

source "$(dirname "$0")/lib.sh"
require_jq

SCRIPT_DIR="$(dirname "$0")"
SNAPSHOT="$SCRIPT_DIR/../data/conformity-snapshot.json"
DRY_RUN=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN="true"; shift ;;
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ ! -f "$SNAPSHOT" ]; then
  echo "ERROR: snapshot not found: $SNAPSHOT" >&2
  echo "Generate one: ./checks/check-estate.sh --json $SNAPSHOT" >&2
  exit 1
fi

if [ -z "$DRY_RUN" ] && ! command -v gh &> /dev/null; then
  echo "ERROR: gh CLI is required." >&2
  exit 1
fi

CREATED=0
SKIPPED=0

# Map a check dimension to the platform doc that defines the standard.
standard_doc() {
  case "$1" in
    versions) echo "versions/manifest.yaml" ;;
    architecture) echo "standards/architecture-diagrams.md" ;;
    *) echo "standards/$1.md" ;;
  esac
}

create_issue_if_needed() {
  local repo="$1" title="$2" body="$3" marker="$4"

  if [ -n "$DRY_RUN" ]; then
    echo "  DRY RUN: would create issue on $repo: $title"
    CREATED=$((CREATED + 1))
    return
  fi

  # Ensure label exists
  gh label create "platform-upgrade" --repo "$repo" --color "0E8A16" \
    --description "Automated platform conformity upgrade" --force 2>/dev/null || true

  # Dedupe: search for the marker text without HTML comment tags
  # (GitHub may not index HTML comments).
  local search_text existing
  search_text=$(echo "$marker" | sed 's/<!-- //;s/ -->//')
  existing=$(gh issue list --repo "$repo" --state open --search "$search_text" \
    --json number --jq '.[0].number' 2>/dev/null || echo "")

  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    echo "  SKIP: issue #$existing already open on $repo"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  gh issue create --repo "$repo" --title "$title" --label "platform-upgrade" --body "$body"
  echo "  CREATED: $title on $repo"
  CREATED=$((CREATED + 1))
}

echo "Reading snapshot: $SNAPSHOT (generated $(jq -r '.generated_at' "$SNAPSHOT"))"

while IFS=$'\t' read -r name repo dimension details; do
  if [ -z "$repo" ] || [ "$repo" = "null" ]; then
    echo "  SKIP: $name/$dimension (no repo configured)"
    continue
  fi

  marker="<!-- platform-check:$dimension/$name -->"
  title="[platform] $name: fix $dimension conformity"
  body="## Conformity gap

- **Product:** $name
- **Dimension:** $dimension
- **Details:** $details

## Definition of done

From the platform repo, this exits 0:

\`\`\`bash
./checks/check-$dimension.sh <path-to-$name-checkout> products/$name.yaml
\`\`\`

## Context

- Standard: $(standard_doc "$dimension")
- Product config: products/$name.yaml
- If this gap is intentional, document a divergence in products/$name.yaml instead of fixing.

$marker"

  create_issue_if_needed "$repo" "$title" "$body" "$marker"
done < <(jq -r '
  .products[]
  | select(.checked == true)
  | .name as $n | .repo as $r
  | .dimensions[]
  | select(.status == "fail")
  | [$n, ($r // "null"), .dimension, .details]
  | @tsv' "$SNAPSHOT")
# NOTE: null repo is emitted as the literal string "null" — an empty TSV
# field would be collapsed by bash read (tab is IFS whitespace), shifting
# the remaining fields.

echo ""
echo "Done. Created: $CREATED, Skipped (already open): $SKIPPED"
