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
ISSUES=()    # confirmed gaps — each one costs an exit code
UNVERIFIED=() # things this token is not allowed to see — never gaps

# GET a path, leaving the response in GH_BODY. Return code says which of three
# different answers the API gave, because they must not be conflated:
#   0  yes
#   1  no — the thing is absent (404), which is a real gap
#   2  won't say — the token lacks the scope (403), which is evidence of
#      nothing at all
# Several of the endpoints below are privilege-gated: branch protection needs
# admin (administration:read), collaborator lookup needs push. Reading a 403 as
# "not configured" would report a correctly onboarded repo as broken.
# NB: gh prints the response body to stdout even on failure and its own
# "(HTTP 403)" line to stderr, so both streams are captured to classify.
gh_api_get() {
  local rc
  GH_BODY="$(gh api "$1" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && return 0
  if grep -qiE 'HTTP 403|must have admin rights|must have push access|resource not accessible|forbidden' <<< "$GH_BODY"; then
    return 2
  fi
  return 1
}

# 1. Reviewer machine account is a collaborator.
gh_api_get "repos/$REPO/collaborators/$REVIEWER_LOGIN"
case $? in
  0) ;;
  2) UNVERIFIED+=("collaborators (token lacks push access)") ;;
  *) ISSUES+=("$REVIEWER_LOGIN is not a collaborator") ;;
esac

# 2+3. Branch protection (>=1 approving review, dismiss_stale_reviews) and
# allow_auto_merge both hang off the repo's default branch / settings — fetch
# the repo once rather than twice.
gh_api_get "repos/$REPO"
REPO_RC=$?
if [ "$REPO_RC" -eq 2 ]; then
  UNVERIFIED+=("repo settings and branch protection (token lacks admin)")
elif [ "$REPO_RC" -ne 0 ]; then
  ISSUES+=("could not fetch repo $REPO via gh api")
else
  REPO_JSON="$GH_BODY"
  DEFAULT_BRANCH=$(echo "$REPO_JSON" | jq -r '.default_branch // empty')

  # allow_auto_merge is only present in the payload for tokens that may see
  # repo settings. Absent means invisible, not disabled.
  if [ "$(echo "$REPO_JSON" | jq -r 'has("allow_auto_merge")')" != "true" ]; then
    UNVERIFIED+=("allow_auto_merge (absent from the repo payload for this token)")
  elif [ "$(echo "$REPO_JSON" | jq -r '.allow_auto_merge')" != "true" ]; then
    ISSUES+=("allow_auto_merge is not enabled")
  fi

  if [ -z "$DEFAULT_BRANCH" ]; then
    ISSUES+=("could not determine default branch")
  else
    gh_api_get "repos/$REPO/branches/$DEFAULT_BRANCH/protection"
    case $? in
      2) UNVERIFIED+=("branch protection on $DEFAULT_BRANCH (token lacks admin)") ;;
      0)
        PROTECTION="$GH_BODY"
        APPROVALS=$(echo "$PROTECTION" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
        DISMISS=$(echo "$PROTECTION" | jq -r '.required_pull_request_reviews.dismiss_stale_reviews // false')
        # Anything not a plain count (absent, null, unexpected shape) is a gap:
        # a rule the API served but cannot express as a count is not evidence
        # that the rule is in place.
        if ! [[ "$APPROVALS" =~ ^[0-9]+$ ]] || [ "$APPROVALS" -lt 1 ]; then
          ISSUES+=("branch protection does not require an approving review")
        fi
        if [ "$DISMISS" != "true" ]; then
          ISSUES+=("branch protection does not dismiss stale reviews")
        fi
        ;;
      *) ISSUES+=("no branch protection on $DEFAULT_BRANCH") ;;
    esac
  fi
fi

# 4. human-signoff label exists. Labels are readable by anyone who can read the
# repo, so a failure here really is a missing label.
if ! gh api "repos/$REPO/labels/human-signoff" > /dev/null 2>&1; then
  ISSUES+=("human-signoff label missing")
fi

# 5. Repo-side gate extension file exists.
if [ ! -f "$PROJECT_PATH/docs/agents/review-gates.yaml" ]; then
  ISSUES+=("docs/agents/review-gates.yaml missing")
fi

# A confirmed gap still fails even when something else was unverifiable — but
# unverifiable dimensions are reported alongside it, so the gap is not read as
# a complete audit.
if [ ${#ISSUES[@]} -gt 0 ]; then
  DETAILS="${ISSUES[*]}"
  if [ ${#UNVERIFIED[@]} -gt 0 ]; then
    DETAILS="$DETAILS; unverified: ${UNVERIFIED[*]}"
  fi
  echo -e "  review-gate: ${FAIL} (${DETAILS})"
  exit 1
fi

# Nothing is wrong that this token could see, and something was hidden from it:
# warn rather than pass, for the same reason a missing token warns above.
if [ ${#UNVERIFIED[@]} -gt 0 ]; then
  echo -e "  review-gate: ${WARN} (cannot fully audit $REPO — unverified: ${UNVERIFIED[*]})"
  exit 0
fi

echo -e "  review-gate: ${PASS}"
