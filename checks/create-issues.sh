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
    review-gate) echo "standards/review-gates.md" ;;
    *) echo "standards/$1.md" ;;
  esac
}

# Most gaps are mechanical — an agent can close them, so they carry
# platform-upgrade. A few need a human decision and are filed ready-for-human
# instead, which also keeps them out of ticket-loop.sh's auto-pick.
issue_label() {
  case "$1" in
    domain-modelling) echo "ready-for-human" ;;
    # Four of the five review-gate dimensions (collaborator, branch protection,
    # allow_auto_merge, label) are admin-scoped API writes, and the remedy needs
    # a Doppler-held reviewer PAT to accept the invitation. An agent holds
    # neither, so this is human work by construction.
    review-gate) echo "ready-for-human" ;;
    *) echo "platform-upgrade" ;;
  esac
}

# Dimensions whose remedy is a conversation rather than a code change say so in
# the body; everything else relies on the generic definition-of-done above it.
issue_remedy() {
  case "$1" in
    domain-modelling)
      cat <<'REMEDY'

## How to close this

A conversation, not a commit. In the repo:

- `/grill-with-docs` — builds the domain model through `/domain-modeling` as
  terms get resolved
- `/wayfinder` first if the area is too large to settle in one session

Zero ADRs is fine and stays fine — `docs/adr/` is written only when a decision
is hard to reverse, surprising, and a real trade-off. `CONTEXT.md` is what
records that the modelling happened, which is what makes an empty `docs/adr/`
mean "nothing qualified" rather than "never done".

**Do not relabel this `ready-for-agent`.** An agent inventing a domain model
unattended produces plausible fiction that every later session then treats as
authoritative.
REMEDY
      ;;
    review-gate)
      cat <<'REMEDY'

## How to close this

Onboard the repo, from the platform repo:

```bash
./scripts/setup-reviewer.sh --repo-dir <path-to-this-checkout>
```

It is idempotent and sets up every dimension the check audits. Two caveats:

- It needs a token with admin rights on this repo, plus Doppler access to the
  reviewer PAT (`platform`/`prd`/`REVIEWER_GH_TOKEN`) to accept the collaborator
  invitation — see "Reviewer identity & onboarding" in
  `choices/ai-dev-workflow.md`.
- It only *seeds* `docs/agents/review-gates.yaml` in the working tree. The
  check reads a fresh clone, so that dimension closes when the file is
  committed.

**Do not relabel this `ready-for-agent`.** The remaining work is admin-scoped
API calls an agent has no credentials for.
REMEDY
      ;;
    *) : ;;
  esac
}

create_issue_if_needed() {
  local repo="$1" title="$2" body="$3" marker="$4" label="$5"

  if [ -n "$DRY_RUN" ]; then
    echo "  DRY RUN: would create issue on $repo [$label]: $title"
    CREATED=$((CREATED + 1))
    return
  fi

  # Ensure label exists. ready-for-human is a canonical triage role that
  # ticket-loop repos already have; --force keeps this idempotent either way.
  if [ "$label" = "platform-upgrade" ]; then
    gh label create "platform-upgrade" --repo "$repo" --color "0E8A16" \
      --description "Automated platform conformity upgrade" --force 2>/dev/null || true
  else
    gh label create "$label" --repo "$repo" --color "D93F0B" \
      --description "Needs a human decision or human implementation" --force 2>/dev/null || true
  fi

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

  gh issue create --repo "$repo" --title "$title" --label "$label" --body "$body"
  echo "  CREATED: $title on $repo [$label]"
  CREATED=$((CREATED + 1))
}

GENERATED_AT=$(jq -r '.generated_at // empty' "$SNAPSHOT")
echo "Reading snapshot: $SNAPSHOT (generated ${GENERATED_AT:-unknown})"

# Issues filed from a stale snapshot describe an estate that no longer exists,
# and — worse — the gaps it does not mention read as closed. Say so here; the
# conformity watchdog is what escalates it to a human (see "Estate conformity
# feed" in choices/ci-cd.md).
STALE_HOURS="${SNAPSHOT_STALE_HOURS:-48}"
generated_epoch=""
if [ -n "$GENERATED_AT" ]; then
  generated_epoch=$(date -u -d "$GENERATED_AT" +%s 2>/dev/null)
fi
if [ -z "$generated_epoch" ]; then
  echo "WARNING: snapshot has no readable generated_at — cannot tell how old it is." >&2
else
  age_hours=$(( ($(date -u +%s) - generated_epoch) / 3600 ))
  if [ "$age_hours" -gt "$STALE_HOURS" ]; then
    echo "WARNING: this snapshot is ${age_hours}h old (limit ${STALE_HOURS}h)." >&2
    echo "         Regenerate it first: ./checks/check-estate.sh --json $SNAPSHOT" >&2
  fi
fi

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
$(issue_remedy "$dimension")

$marker"

  create_issue_if_needed "$repo" "$title" "$body" "$marker" "$(issue_label "$dimension")"
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
