#!/usr/bin/env bash
# Check reviewer setup conformity for a single project.
# Usage: check-review-gate.sh <project-path> <product-yaml-path>
#
# See "Reviewer identity & onboarding" in choices/ai-dev-workflow.md and
# scripts/setup-reviewer.sh. A repo flipped to choices.ai_workflow: ticket-loop
# without running setup-reviewer.sh fails at review/merge time instead of
# showing up here — this check catches that gap ahead of time. Only products
# on ticket-loop are in scope; superpowers (legacy) and unset workflows are
# skipped, not failed.

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"

# Both spellings are honoured: the dimension name and the standard's filename
# (standards/review-gates.md) are both plausible things to write, and a
# divergence that silently fails to register is worse than a lenient match.
if has_divergence "$PRODUCT_YAML" "review-gate" ||
   has_divergence "$PRODUCT_YAML" "review-gates"; then
  echo -e "  review-gate: ${DIVG} (intentional divergence)"
  exit 0
fi

WORKFLOW=$(yaml_get "$PRODUCT_YAML" '.choices.ai_workflow')
if [ "$WORKFLOW" != "ticket-loop" ]; then
  echo -e "  review-gate: ${DIVG} (n/a: ${WORKFLOW:-no} workflow)"
  exit 0
fi

REPO=$(yaml_get "$PRODUCT_YAML" '.repo')
if [ -z "$REPO" ] || [ "$REPO" = "null" ]; then
  echo -e "  review-gate: ${FAIL} (no repo configured in product YAML)"
  exit 1
fi

# The four API-side dimensions need a token; the fifth (the repo's gate
# extension file) is on disk. Without credentials this machine cannot tell a
# conformant repo from a broken one, so warn and skip rather than file a gap
# the owner cannot act on — the estate audit runs with GH_TOKEN set
# (.github/workflows/conformity.yml) and does exercise these.
if ! GH_SKIP_REASON=$(gh_ready); then
  echo -e "  review-gate: ${WARN} (${GH_SKIP_REASON}: cannot audit $REPO)"
  exit 0
fi
require_jq

REVIEWER_LOGIN="${REVIEWER_LOGIN:-lennons301-reviewer}"
ISSUES=()

# 1. Reviewer machine account is a collaborator.
if ! gh api "repos/$REPO/collaborators/$REVIEWER_LOGIN" > /dev/null 2>&1; then
  ISSUES+=("$REVIEWER_LOGIN is not a collaborator")
fi

# 2+3. Branch protection (>=1 approving review, dismiss_stale_reviews) and
# allow_auto_merge both hang off the repo's default branch / settings — fetch
# the repo once rather than twice.
# NB: gh api prints the error body to stdout even on HTTP 404, so on
# failure the variable must be overwritten, not defaulted inside the
# substitution (see scripts/setup-reviewer.sh for the same gotcha).
REPO_JSON="$(gh api "repos/$REPO" 2>/dev/null)" || REPO_JSON=""
if [ -z "$REPO_JSON" ]; then
  ISSUES+=("could not fetch repo $REPO via gh api")
else
  DEFAULT_BRANCH=$(echo "$REPO_JSON" | jq -r '.default_branch // empty')
  AUTO_MERGE=$(echo "$REPO_JSON" | jq -r '.allow_auto_merge // false')

  if [ "$AUTO_MERGE" != "true" ]; then
    ISSUES+=("allow_auto_merge is not enabled")
  fi

  if [ -z "$DEFAULT_BRANCH" ]; then
    ISSUES+=("could not determine default branch")
  else
    PROTECTION="$(gh api "repos/$REPO/branches/$DEFAULT_BRANCH/protection" 2>/dev/null)" || PROTECTION=""
    if [ -z "$PROTECTION" ]; then
      ISSUES+=("no branch protection on $DEFAULT_BRANCH")
    else
      APPROVALS=$(echo "$PROTECTION" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
      DISMISS=$(echo "$PROTECTION" | jq -r '.required_pull_request_reviews.dismiss_stale_reviews // false')
      # Anything not a plain count (absent, null, unexpected shape) is a gap:
      # an unreadable rule is not evidence that the rule is in place.
      if ! [[ "$APPROVALS" =~ ^[0-9]+$ ]] || [ "$APPROVALS" -lt 1 ]; then
        ISSUES+=("branch protection does not require an approving review")
      fi
      if [ "$DISMISS" != "true" ]; then
        ISSUES+=("branch protection does not dismiss stale reviews")
      fi
    fi
  fi
fi

# 4. human-signoff label exists.
if ! gh api "repos/$REPO/labels/human-signoff" > /dev/null 2>&1; then
  ISSUES+=("human-signoff label missing")
fi

# 5. Repo-side gate extension file exists.
if [ ! -f "$PROJECT_PATH/docs/agents/review-gates.yaml" ]; then
  ISSUES+=("docs/agents/review-gates.yaml missing")
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  review-gate: ${PASS}"
else
  echo -e "  review-gate: ${FAIL} (${ISSUES[*]})"
  exit 1
fi
