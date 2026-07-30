#!/usr/bin/env bash
# setup-reviewer.sh — onboard one repo to the separate-reviewer-identity flow
# (see 'Reviewer identity & onboarding' in choices/ai-dev-workflow.md and
# standards/review-gates.md).
#
# Idempotent: safe to re-run; every step converges rather than duplicates.
#
# What it does, in order (repo-side first, so a missing PAT only blocks the
# invitation steps and a re-run completes them):
#   1. branch protection on the default branch: require 1 approving review,
#      dismiss stale approvals on push — merged with any existing protection
#      (required status checks and enforce_admins are preserved)
#   2. enable the repo's allow-auto-merge setting
#   3. create the human-signoff and workflow:* labels
#   4. seed docs/agents/review-gates.yaml gate-extension stub (left for you
#      to commit)
#   5. invite the reviewer machine account as a write collaborator
#   6. accept the invitation using the reviewer PAT from Doppler
#
# Usage:
#   ./scripts/setup-reviewer.sh [--repo-dir PATH]
#
# Requires: gh (authenticated as the repo owner), jq, doppler (for step 6).
# Manual prerequisites (once, estate-wide): create the machine account, mint
# its classic PAT (repo scope), store it in Doppler.

set -euo pipefail

REVIEWER_LOGIN="${REVIEWER_LOGIN:-lennons301-reviewer}"
REVIEWER_DOPPLER_PROJECT="${REVIEWER_DOPPLER_PROJECT:-platform}"
REVIEWER_DOPPLER_CONFIG="${REVIEWER_DOPPLER_CONFIG:-prd}"
REVIEWER_DOPPLER_SECRET="${REVIEWER_DOPPLER_SECRET:-REVIEWER_GH_TOKEN}"

ONBOARDING_DOC="~/code/platform/choices/ai-dev-workflow.md (Reviewer identity & onboarding)"

REPO_DIR="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

cd "$REPO_DIR"
git rev-parse --git-dir > /dev/null || { echo "Not a git repo: $REPO_DIR" >&2; exit 1; }

command -v jq > /dev/null || { echo "ERROR: jq is required." >&2; exit 1; }

NWO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
echo "==> Onboarding $NWO (default branch: $DEFAULT_BRANCH) for reviewer $REVIEWER_LOGIN"

# --- 1. Branch protection (merge, don't clobber) -------------------------------

# NB: gh api prints the error body to stdout even on HTTP 404, so on failure
# the variable must be overwritten, not defaulted inside the substitution.
EXISTING="$(gh api "repos/$NWO/branches/$DEFAULT_BRANCH/protection" 2>/dev/null)" || EXISTING='{}'

PAYLOAD="$(jq -n --argjson existing "$EXISTING" '
  {
    required_status_checks: (
      if $existing.required_status_checks then
        { strict: $existing.required_status_checks.strict,
          contexts: ($existing.required_status_checks.contexts // []) }
      else null end
    ),
    enforce_admins: ($existing.enforce_admins.enabled // false),
    required_pull_request_reviews: (
      ($existing.required_pull_request_reviews // {}) as $r |
      { dismiss_stale_reviews: true,
        require_code_owner_reviews: ($r.require_code_owner_reviews // false),
        required_approving_review_count: ([($r.required_approving_review_count // 0), 1] | max) }
    ),
    restrictions: null
  }')"

echo "$PAYLOAD" | gh api -X PUT "repos/$NWO/branches/$DEFAULT_BRANCH/protection" \
  --input - > /dev/null
echo "==> Branch protection: 1 approving review required, stale approvals dismissed (existing checks preserved)"

if [ "$(echo "$PAYLOAD" | jq -r .enforce_admins)" = "true" ]; then
  echo "==> WARNING: enforce_admins is ON for this repo (pre-existing; preserved)." >&2
  echo "    A solo developer cannot bypass-merge here: every PR needs the reviewer's" >&2
  echo "    approval before a human can merge. This breaks human parity — see" >&2
  echo "    'Human parity' in choices/ai-dev-workflow.md. Turn it off to restore" >&2
  echo "    the solo path, or accept reviewer-approval-then-merge as the only flow." >&2
fi

# --- 2. Auto-merge repo setting -------------------------------------------------

gh api -X PATCH "repos/$NWO" -F allow_auto_merge=true > /dev/null
echo "==> allow_auto_merge: enabled"

# --- 3. Labels ------------------------------------------------------------------

gh label create human-signoff --repo "$NWO" --force \
  --description "Gated: reviewer done, a human merges after looking" \
  --color 5319e7 > /dev/null
echo "==> Label: human-signoff"

# Workflow menu: the label name IS the skill name, so a ticket labelled
# workflow:tdd selects /tdd with no menu file to maintain. See 'Workflows per
# ticket' in choices/ai-dev-workflow.md.
for wf in tdd:"Red-green loop — body MUST name the seams under test" \
          diagnosing-bugs:"Diagnosis loop before any fix" \
          research:"Background agent against primary sources" \
          prototype:"Throwaway prototype — HITL, pair with ready-for-human"; do
  gh label create "workflow:${wf%%:*}" --repo "$NWO" --force \
    --description "${wf#*:}" --color 1d76db > /dev/null
done
echo "==> Labels: workflow:tdd, workflow:diagnosing-bugs, workflow:research, workflow:prototype"

# --- 4. Gate-extension stub -----------------------------------------------------

STUB="docs/agents/review-gates.yaml"
if [ -f "$STUB" ]; then
  echo "==> Gate extension: $STUB already present"
else
  mkdir -p docs/agents
  cat > "$STUB" <<'EOF'
# Repo-specific human-sign-off gates — ADDITIVE extension of the estate
# default (~/code/platform/standards/review-gates.yaml). A repo can add
# gates, never remove estate ones. Same shape:
#
# human_signoff:
#   <category>:
#     - "<glob>"
human_signoff: {}
EOF
  echo "==> Gate extension: seeded $STUB — review and commit it"
fi

# --- 5. Invite the reviewer -----------------------------------------------------

if gh api "repos/$NWO/collaborators/$REVIEWER_LOGIN" > /dev/null 2>&1; then
  echo "==> Collaborator: $REVIEWER_LOGIN already has access"
else
  gh api -X PUT "repos/$NWO/collaborators/$REVIEWER_LOGIN" -f permission=push > /dev/null
  echo "==> Collaborator: invited $REVIEWER_LOGIN (write)"

  # --- 6. Accept the invitation as the reviewer --------------------------------

  if ! command -v doppler > /dev/null 2>&1; then
    echo "==> WARNING: doppler CLI not found — cannot accept the invitation automatically." >&2
    echo "    Bootstrap (doppler login) and re-run, or accept manually as $REVIEWER_LOGIN. See $ONBOARDING_DOC." >&2
    exit 1
  fi
  if ! REVIEWER_TOKEN="$(doppler secrets get "$REVIEWER_DOPPLER_SECRET" \
      --project "$REVIEWER_DOPPLER_PROJECT" --config "$REVIEWER_DOPPLER_CONFIG" \
      --plain 2>/dev/null)" || [ -z "$REVIEWER_TOKEN" ]; then
    echo "==> WARNING: reviewer PAT not readable from Doppler ($REVIEWER_DOPPLER_PROJECT/$REVIEWER_DOPPLER_CONFIG/$REVIEWER_DOPPLER_SECRET)." >&2
    echo "    Complete the manual prerequisites, then re-run to accept the invitation. See $ONBOARDING_DOC." >&2
    exit 1
  fi

  INVITE_ID="$(GH_TOKEN="$REVIEWER_TOKEN" gh api user/repository_invitations \
    --jq ".[] | select(.repository.full_name == \"$NWO\") | .id" | head -1)"
  if [ -z "$INVITE_ID" ]; then
    echo "==> WARNING: no pending invitation found for $REVIEWER_LOGIN on $NWO — accept manually if needed." >&2
  else
    GH_TOKEN="$REVIEWER_TOKEN" gh api -X PATCH "user/repository_invitations/$INVITE_ID" > /dev/null
    echo "==> Collaborator: invitation accepted as $REVIEWER_LOGIN"
  fi
fi

echo "==> Done. $NWO is onboarded; ticket-loop PRs will arm auto-merge unless a review gate matches."
