#!/usr/bin/env bash
# ticket-loop.sh — thin per-ticket runner for the ticket-loop workflow
# (see choices/ai-dev-workflow.md).
#
# One invocation = one ticket, at most one implement attempt:
#   pick a ready-for-agent issue -> dispatch on any existing open PR's state
#   (see "PR-state dispatch" below: conflicting PRs get a repair pass, parked
#   approved PRs exit early) -> worktree -> implement pass (claude -p)
#   -> deterministic review gates (arm auto-merge, or human-signoff)
#   -> review pass (fresh context, reviewer identity) -> verify the review
#   actually landed on GitHub -> report.
#
# A `workflow:research` ticket takes a second route through the same guarantees
# (see "Research tickets" below): its deliverable is a finding recorded on the
# issue that asked the question, so there is no PR — research pass (finding
# posted as an issue comment) -> review pass against the issue thread, verdict
# posted as a comment -> verify it landed -> approve closes the issue.
#
# The review pass runs as the reviewer machine account (PAT fetched from
# Doppler), so its approvals are accepted by GitHub. Whether an approval may
# auto-land the PR is decided deterministically BEFORE review: changed paths
# are matched against standards/review-gates.yaml (+ the repo's own
# docs/agents/review-gates.yaml); ungated PRs are armed with
# `gh pr merge --auto`, gated PRs are labelled human-signoff and left
# disarmed. See standards/review-gates.md and choices/ai-dev-workflow.md.
#
# Parallel or sequenced, execution is always independent instances: run several
# invocations (different issues, or a dependency chain worked in order), each in
# its own worktree and branch. A driver may sequence them — never as subagents.
#
# Usage:
#   ./scripts/ticket-loop.sh [--issue N] [--repo-dir PATH] [--afk]
#
#   --issue N      work this issue instead of picking the oldest ready-for-agent
#   --repo-dir     project repo to operate on (default: current directory)
#   --afk          fully unattended: passes --dangerously-skip-permissions to
#                  the implement and repair passes. Only for repos where issue
#                  creation and labelling are restricted to you
#                  (prompt-injection caution).
#
# Requires: gh (authenticated), git, claude, yq, jq, doppler (logged in; the
# reviewer PAT lives in Doppler — see 'Reviewer identity & onboarding' in
# choices/ai-dev-workflow.md). Onboard a repo with scripts/setup-reviewer.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/review-gates-lib.sh"
source "$SCRIPT_DIR/review-verify-lib.sh"

# Reviewer identity (override via env if your estate differs)
REVIEWER_LOGIN="${REVIEWER_LOGIN:-lennons301-reviewer}"
REVIEWER_DOPPLER_PROJECT="${REVIEWER_DOPPLER_PROJECT:-platform}"
REVIEWER_DOPPLER_CONFIG="${REVIEWER_DOPPLER_CONFIG:-prd}"
REVIEWER_DOPPLER_SECRET="${REVIEWER_DOPPLER_SECRET:-REVIEWER_GH_TOKEN}"

ONBOARDING_DOC="~/code/platform/choices/ai-dev-workflow.md (Reviewer identity & onboarding)"

ISSUE=""
REPO_DIR="$PWD"
AFK=""
MAX_ATTEMPTS=3

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)    ISSUE="$2"; shift 2 ;;
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --afk)      AFK="1"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

cd "$REPO_DIR"
git rev-parse --git-dir > /dev/null || { echo "Not a git repo: $REPO_DIR" >&2; exit 1; }
REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_NAME="$(basename "$REPO_ROOT")"

# --- Capability contract -------------------------------------------------------
# Each headless pass pre-approves, via --allowedTools, exactly the command
# verbs its prompt (or the agent definition it launches) instructs — prompt
# and permissions ship together, so they cannot drift (issue #12: a repo whose
# allowlist lacked git commit / gh silently crippled the implement pass,
# including its own escape hatch). These arrays also feed the permission
# preflight below, so the carried sets and the checked set cannot drift
# either. Repo-specific check commands (tests, lint) are deliberately NOT
# part of the contract: they run under the already-approved `doppler run`,
# or fall to the repo's own allowlist.

# Implement pass (prompt below): read the issue, stage + commit, push, open
# or update the PR, run checks under doppler-injected env, leave the PR
# mergeable (fetch + merge the moved default branch — the exit criterion),
# and the escape hatch when blocked (comment on the issue + relabel
# ready-for-human).
IMPLEMENT_VERBS=(
  "gh issue view"
  "gh issue comment"
  "gh issue edit"
  "git add"
  "git commit"
  "git push"
  "git fetch"
  "git merge"
  "gh pr list"
  "gh pr view"
  "gh pr create"
  "gh pr edit"
  "doppler run"
)

# Research pass (prompt in the research section below): the workflow:research
# variant of the implement pass. Its deliverable is a finding recorded on the
# issue, so it carries the issue verbs and nothing else — no git, no PR verbs:
# a research ticket produces no commit, no branch push and no PR by design.
RESEARCH_VERBS=(
  "gh issue view"
  "gh issue comment"
  "gh issue edit"
  "doppler run"
)

# Review pass: the ticket-reviewer agent's contract (canonical at
# templates/agents/ticket-reviewer.md): read the ticket and PR (view, diff,
# CI checks), submit the verdict (approve / request-changes / comment),
# the human-signoff path (disarm auto-merge + label), and the escalation
# path (PR comment + relabel the issue). `gh pr merge` is carried only with
# --disable-auto — the reviewer may add a human gate, never merge.
# `gh issue comment` is for the agent's issue-thread mode: on a research
# ticket the verdict is posted on the issue, there being no PR to review.
REVIEW_VERBS=(
  "gh issue view"
  "gh issue comment"
  "gh issue edit"
  "gh pr view"
  "gh pr diff"
  "gh pr checks"
  "gh pr review"
  "gh pr comment"
  "gh pr edit"
  "gh pr merge --disable-auto"
  "doppler run"
)

# Repair pass (prompt in the mergeability section below): merge the moved
# default branch into the PR branch, resolve the conflicts, re-run the
# checks, push. The implement set minus the PR-creation verbs
# (gh pr list / create / edit) — git fetch / git merge stay. Merge only —
# no rebase, no force-push, in any headless contract.
REPAIR_VERBS=(
  "gh issue view"
  "gh issue comment"
  "gh issue edit"
  "git add"
  "git commit"
  "git push"
  "git fetch"
  "git merge"
  "gh pr view"
  "doppler run"
)

# "git push" "doppler run" -> "Bash(git push:*),Bash(doppler run:*)"
allowed_tools() {
  local CSV="" VERB
  for VERB in "$@"; do CSV+="${CSV:+,}Bash(${VERB}:*)"; done
  printf '%s' "$CSV"
}

# --- Permission preflight ------------------------------------------------------
# The passes pre-approve their carried verbs via --allowedTools, but
# permission rules evaluate deny -> ask -> allow with the FIRST match
# winning: an ask/deny rule covering a carried verb beats any allow from any
# source, and a non-interactive pass cannot answer an ask prompt, so the pass
# dies mid-run (worktree sessions resolve .claude/settings*.json to this
# checkout). Fail fast naming the offending rule instead. --afk skips
# permissions for the implement and repair passes only — the review pass
# always runs under permissions, so its verbs are checked regardless.
command -v jq > /dev/null || { echo "ERROR: jq is required." >&2; exit 1; }
if [ -n "$AFK" ]; then
  PREFLIGHT_VERBS=("${REVIEW_VERBS[@]}")
else
  PREFLIGHT_VERBS=("${IMPLEMENT_VERBS[@]}" "${REPAIR_VERBS[@]}"
                   "${RESEARCH_VERBS[@]}" "${REVIEW_VERBS[@]}")
fi
BLOCKING=""
for SETTINGS in "$HOME/.claude/settings.json" \
                "$REPO_ROOT/.claude/settings.json" \
                "$REPO_ROOT/.claude/settings.local.json"; do
  [ -f "$SETTINGS" ] || continue
  while IFS= read -r RULE; do
    PREFIX="${RULE#Bash(}"; PREFIX="${PREFIX%)}"; PREFIX="${PREFIX%":*"}"
    if [ "$RULE" = "Bash" ] || [ "$PREFIX" = "*" ]; then
      BLOCKING+="$SETTINGS: $RULE"$'\n'
      continue
    fi
    for NEED in "${PREFLIGHT_VERBS[@]}"; do
      case "$NEED" in "$PREFIX"*) BLOCKING+="$SETTINGS: $RULE"$'\n'; continue 2 ;; esac
      case "$PREFIX" in "$NEED"*) BLOCKING+="$SETTINGS: $RULE"$'\n'; continue 2 ;; esac
    done
  done < <(jq -r '((.permissions.ask // []) + (.permissions.deny // []))[]
                  | select(. == "Bash" or startswith("Bash("))' "$SETTINGS" 2>/dev/null)
done
if [ -n "$BLOCKING" ]; then
  echo "==> ERROR: ask/deny permission rules would block commands the ticket-loop passes carry:" >&2
  printf '%s' "$BLOCKING" | sed 's/^/    /' >&2
  echo "    These beat --allowedTools (deny -> ask -> allow, first match wins), and a" >&2
  echo "    non-interactive pass cannot answer an ask prompt. Remove or relax the rule(s)." >&2
  echo "    (--afk skips permissions for the implement and repair passes only; the review" >&2
  echo "    pass always runs under permissions.) See 'Repo permission rules' in choices/ai-dev-workflow.md." >&2
  exit 1
fi

# --- Pick a ticket -----------------------------------------------------------

# Wayfinder tickets are decision tickets, not build slices — a wayfinder:grilling
# ticket exists to be answered by a human, and an agent sent to "implement" one
# would answer its own question and open a PR for it. They must never reach this
# loop, however they got labelled ready-for-agent.
# Blocked tickets are skipped too. /to-tickets records dependency order as
# native GitHub issue dependencies, and GitHub counts only OPEN blockers — so a
# ticket is on the frontier exactly when blocked_by is 0, and it becomes
# eligible on its own as blockers close. Without this check the loop would take
# the oldest armed ticket and build a slice whose foundation does not exist yet.
is_blocked() {
  [ "$(gh api "repos/{owner}/{repo}/issues/$1" \
        --jq '.issue_dependencies_summary.blocked_by // 0' 2>/dev/null || echo 0)" != "0" ]
}

if [ -z "$ISSUE" ]; then
  CANDIDATES="$(gh issue list --label ready-for-agent --state open \
    --json number,labels \
    --jq '[.[] | select([.labels[].name | startswith("wayfinder:")] | any | not)]
          | sort_by(.number) | .[].number')"
  for c in $CANDIDATES; do
    if is_blocked "$c"; then
      echo "==> Skipping #$c — blocked by an open dependency."
      continue
    fi
    ISSUE="$c"; break
  done
  if [ -z "$ISSUE" ]; then
    echo "No open ready-for-agent issues on the frontier (excluding wayfinder and blocked tickets). Nothing to do."
    exit 0
  fi
fi

# The ticket's labels decide two things below: whether this loop refuses the
# ticket outright (wayfinder), and what shape its deliverable has (a research
# ticket answers a question on the issue instead of opening a PR). Read them
# once, and fail rather than proceed label-blind — an unreadable label set would
# silently look like "no wayfinder label, not research".
if ! LABEL_LIST="$(gh issue view "$ISSUE" --json labels --jq '.labels[].name')"; then
  echo "==> ERROR: could not read the labels on issue #$ISSUE." >&2
  exit 1
fi
mapfile -t LABELS <<< "$LABEL_LIST"
has_label() {
  local want="$1" label
  for label in ${LABELS[@]+"${LABELS[@]}"}; do
    [ "$label" = "$want" ] && return 0
  done
  return 1
}

# Explicit --issue bypasses the pick above, so guard it here too — loudly, since
# naming a wayfinder ticket directly is a mistake rather than a quiet skip.
for LABEL in ${LABELS[@]+"${LABELS[@]}"}; do
  case "$LABEL" in
    wayfinder:*)
      echo "==> ERROR: issue #$ISSUE is a wayfinder ticket ($LABEL)." >&2
      echo "    Wayfinder tickets resolve decisions, not code — work it with /wayfinder." >&2
      echo "    See 'The generation flow' (Wayfinder) in choices/ai-dev-workflow.md." >&2
      exit 1 ;;
  esac
done

# Same for blockers: a quiet skip is right for the auto-pick, but naming a
# blocked ticket directly is a mistake worth stopping on.
if is_blocked "$ISSUE"; then
  echo "==> ERROR: issue #$ISSUE is blocked by an open dependency." >&2
  gh api "repos/{owner}/{repo}/issues/$ISSUE/dependencies/blocked_by" \
    --jq '.[] | select(.state == "open") | "    blocked by #\(.number) — \(.title)"' >&2 2>/dev/null || true
  echo "    Work its blockers first, or clear the edge if it is wrong." >&2
  exit 1
fi

echo "==> Issue #$ISSUE in $REPO_NAME"

# A workflow:research ticket is a knowledge ticket: it asks a question, and its
# deliverable is the finding that answers it — recorded on the issue that asked,
# where the question and its answer stay together. Nothing about it is
# PR-shaped, so the whole PR half of this runner (dispatch, mergeability, gates,
# auto-merge, diff review) is skipped for one: see the research section below.
RESEARCH=""
if has_label "workflow:research"; then
  RESEARCH="1"
  echo "==> workflow:research ticket — the finding is recorded on the issue; no PR, no gates."
fi

BRANCH="agent/issue-$ISSUE"
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"

# --- PR-state dispatch ---------------------------------------------------------
# Parked PRs go stale underneath this loop: gated (human-signoff) PRs wait
# for a human merge, and each human merge can flip the still-parked ones to
# CONFLICTING (and the eventual fix-push dismisses the reviewer's approval —
# stale-approval dismissal is deliberate). So when the issue already has an
# open PR, read its state first and do only the work that state calls for,
# instead of burning one of the limited implement attempts regardless:
#
#   CONFLICTING                   -> repair pass (merge the default branch,
#                                    resolve, push), then gates + review
#   MERGEABLE + APPROVED          -> parked awaiting human merge; exit 0
#   MERGEABLE + CHANGES_REQUESTED -> implement attempt (the work is
#                                    addressing the feedback) — unchanged
#   MERGEABLE + not reviewed      -> gates + review only (an approval was
#                                    dismissed, or a runner died mid-run)
#   no open PR                    -> implement attempt — unchanged

# GitHub computes mergeability lazily: `mergeable` reads UNKNOWN until a
# background job finishes, and UNKNOWN means "not computed yet" — never a
# verdict either way. Poll until it resolves; fail rather than guess.
pr_merge_state() {
  local TRY STATE
  for TRY in $(seq 1 20); do
    # || true: a transient gh failure is one failed try, not (via errexit) a
    # dead run — the empty STATE falls through to the retry like UNKNOWN does.
    STATE="$(gh pr view "$1" --json mergeable --jq '.mergeable // "UNKNOWN"' || true)"
    case "$STATE" in MERGEABLE|CONFLICTING) printf '%s' "$STATE"; return 0 ;; esac
    sleep 3
  done
  echo "==> ERROR: PR #$1 mergeability still UNKNOWN after ~60s of polling —" >&2
  echo "    GitHub has not computed it yet. Re-run shortly; UNKNOWN is never treated as a verdict." >&2
  return 1
}

MODE="implement"
PR=""
# Research tickets have no PR to dispatch on, by design — skip the read entirely.
[ -z "$RESEARCH" ] && PR="$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')"
if [ -n "$PR" ]; then
  MERGE_STATE="$(pr_merge_state "$PR")"
  REVIEW_DECISION="$(gh pr view "$PR" --json reviewDecision --jq '.reviewDecision // ""')"
  if [ "$MERGE_STATE" = "CONFLICTING" ]; then
    MODE="repair"
    echo "==> Open PR #$PR is CONFLICTING — repair pass instead of an implement attempt."
  elif [ "$REVIEW_DECISION" = "APPROVED" ]; then
    echo "==> Open PR #$PR is MERGEABLE and APPROVED — parked awaiting human merge. Nothing to do."
    exit 0
  elif [ "$REVIEW_DECISION" = "CHANGES_REQUESTED" ]; then
    echo "==> Open PR #$PR has changes requested — implement attempt addresses the feedback."
  else
    MODE="review-only"
    echo "==> Open PR #$PR is MERGEABLE but not approved — running gates + review only."
  fi
fi

# --- Attempt accounting ------------------------------------------------------
# Attempts are visible on the issue as comments; after MAX_ATTEMPTS the ticket
# goes back to a human instead of thrashing. Only implement attempts count:
# a repair pass posts its own 🔧 marker (deliberately not matching the
# "🤖 Attempt" prefix counted here) and a gates+review-only run posts nothing.

if [ "$MODE" = "implement" ]; then
  ATTEMPT=$(( $(gh issue view "$ISSUE" --comments --json comments \
    --jq '[.comments[].body | select(startswith("🤖 Attempt"))] | length') + 1 ))

  if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
    echo "Issue #$ISSUE already has $((ATTEMPT - 1)) attempts. Flagging for a human."
    # Label ops use REST: gh's GraphQL editors (gh pr/issue edit) query the
    # sunset projectCards field and error out (observed 2026-07-28, gh 2.45).
    gh api "repos/{owner}/{repo}/issues/$ISSUE/labels" -f 'labels[]=ready-for-human' > /dev/null
    gh api -X DELETE "repos/{owner}/{repo}/issues/$ISSUE/labels/ready-for-agent" > /dev/null || true
    # What "no result" means depends on the ticket's deliverable: a research
    # ticket never had a PR to get approved (see the research section below).
    EXHAUSTED_WITHOUT="an approved PR"
    [ -n "$RESEARCH" ] && EXHAUSTED_WITHOUT="an approved finding"
    gh issue comment "$ISSUE" --body "🤖 $((ATTEMPT - 1)) agent attempts without $EXHAUSTED_WITHOUT — flagging ready-for-human."
    exit 1
  fi
  gh issue comment "$ISSUE" --body "🤖 Attempt $ATTEMPT/$MAX_ATTEMPTS starting." > /dev/null
  echo "==> Attempt $ATTEMPT/$MAX_ATTEMPTS"
fi

# --- Worktree ----------------------------------------------------------------

WORKTREE="$(git rev-parse --show-toplevel)/../${REPO_NAME}-issue-${ISSUE}"

if [ ! -d "$WORKTREE" ]; then
  git fetch origin "$DEFAULT_BRANCH"
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git worktree add "$WORKTREE" "$BRANCH"
  elif git fetch origin "$BRANCH" > /dev/null 2>&1; then
    # The branch lives only on origin (an open PR can outlive this machine's
    # worktree and local branch) — start from the PR branch, not the default.
    git worktree add -b "$BRANCH" "$WORKTREE" "origin/$BRANCH"
  else
    git worktree add -b "$BRANCH" "$WORKTREE" "origin/$DEFAULT_BRANCH"
  fi
fi
echo "==> Worktree: $WORKTREE"

# --- Reviewer identity -------------------------------------------------------
# Both review paths (PR diff, research issue thread) run as the reviewer machine
# account, so both resolve it the same way: PAT out of Doppler, confirmed live
# and confirmed to be someone other than the implementer. Sets REVIEWER_TOKEN
# and REVIEWER_ACTUAL; exits non-zero rather than reviewing under the wrong
# identity. Called from the review sections, so the token is exported only
# around a review pass — an implement pass never sees it.

resolve_reviewer_identity() {
  if ! command -v doppler > /dev/null 2>&1; then
    echo "==> ERROR: doppler CLI not found. The review pass authenticates via a PAT in Doppler." >&2
    echo "    Bootstrap this machine: install doppler, then 'doppler login'. See $ONBOARDING_DOC." >&2
    exit 1
  fi

  if ! REVIEWER_TOKEN="$(doppler secrets get "$REVIEWER_DOPPLER_SECRET" \
      --project "$REVIEWER_DOPPLER_PROJECT" --config "$REVIEWER_DOPPLER_CONFIG" \
      --plain 2>/dev/null)" || [ -z "$REVIEWER_TOKEN" ]; then
    echo "==> ERROR: could not read $REVIEWER_DOPPLER_SECRET from Doppler ($REVIEWER_DOPPLER_PROJECT/$REVIEWER_DOPPLER_CONFIG)." >&2
    echo "    Is this machine logged in (doppler login)? Has the reviewer PAT been minted and stored? See $ONBOARDING_DOC." >&2
    exit 1
  fi

  REVIEWER_ACTUAL="$(GH_TOKEN="$REVIEWER_TOKEN" gh api user --jq .login 2>/dev/null || true)"
  if [ -z "$REVIEWER_ACTUAL" ]; then
    echo "==> ERROR: reviewer PAT was rejected by GitHub (expired or revoked?). See $ONBOARDING_DOC." >&2
    exit 1
  fi
  IMPLEMENTER="$(gh api user --jq .login)"
  if [ "$REVIEWER_ACTUAL" = "$IMPLEMENTER" ]; then
    echo "==> ERROR: reviewer token belongs to '$REVIEWER_ACTUAL' — same identity as the implementer." >&2
    echo "    GitHub rejects self-approval; store the machine account's PAT instead. See $ONBOARDING_DOC." >&2
    exit 1
  fi
}

# --- Research tickets: finding on the issue, reviewed on the issue ------------
# The whole path for a workflow:research ticket, and it ends in an exit: the PR
# machinery below (mergeability, gates, auto-merge, diff review) has no object
# to act on here, so the ticket never reaches it — which is also why the PR path
# needs no research conditionals at all.
#
# What the loop guarantees is unchanged: one bounded attempt against the ticket
# as spec, a fresh-eyes review under a separate identity, and side effects
# verified against GitHub rather than taken from a pass's narration. Only the
# object those guarantees apply to changes — an issue comment, not a diff. The
# question and its answer end up on the same issue, and nothing lands in the
# repo: a research finding that leaves an artefact behind answered in the wrong
# shape (interlude#59, 2026-08-06 — the finding was right, the merged
# docs/research/*.md was not).

if [ -n "$RESEARCH" ]; then
  # Baseline first: "the pass recorded its finding" means a comment the issue
  # did not already have — earlier attempts and reviewer verdicts are already
  # there. Runner markers (🤖 / 🔧) are excluded from both reads.
  set +e
  FINDING_BASELINE="$(issue_finding_count "$ISSUE")"
  BASELINE_RC=$?
  set -e
  if [ "$BASELINE_RC" -ne 0 ]; then
    echo "==> ERROR: could not read the comments on issue #$ISSUE before the research pass." >&2
    echo "    Without a baseline, a finding that landed cannot be told from one already there. Re-run." >&2
    exit 1
  fi

  # Pre-approve the research pass's capability contract (RESEARCH_VERBS above).
  # Same NB as the other passes: the prompt must come BEFORE --allowedTools.
  # acceptEdits is kept for symmetry even though the prompt forbids editing the
  # repo: what keeps a research finding out of the repo is structural, not a
  # permission mode — the contract carries no git and no PR verbs, so nothing
  # this pass writes in the worktree can be committed, pushed or opened as a PR.
  # A scratch file it writes while investigating should not kill the pass.
  RESEARCH_FLAGS=(--permission-mode acceptEdits
    --allowedTools "$(allowed_tools "${RESEARCH_VERBS[@]}")")
  [ -n "$AFK" ] && RESEARCH_FLAGS=(--dangerously-skip-permissions)

  (cd "$WORKTREE" && claude -p "
Answer the research question in GitHub issue #$ISSUE of this repo. This is
attempt $ATTEMPT of $MAX_ATTEMPTS.

This is a research ticket (workflow:research): the deliverable is the finding
itself, recorded on the issue that asks the question. Do NOT write code, do NOT
add or edit any file in this repo, and do NOT open a PR — a finding that leaves
an artefact behind is the wrong shape of answer.

1. Read the issue in full (gh issue view $ISSUE --comments). The question, and
   any acceptance criteria it sets for the answer, are the spec. Read the
   existing comments too: on a repeat attempt the reviewer's verdict says what
   was missing, and that is what this attempt must fix.
2. Investigate with the /research skill. Primary sources first: this repo's own
   code and docs, AGENTS.md / CLAUDE.md and CONTEXT.md for how it is meant to
   work, upstream sources, and experiments you can actually run. Keep what you
   verified separate from what you inferred.
3. This pass is permitted the issue verbs (gh issue view / comment / edit) and
   'doppler run'; anything else depends on what this repo's own permission
   settings already allow. If a check you need is not permitted, say so in the
   finding — an unrun experiment reported as a result is the one outcome worse
   than a gap.
4. Post the finding as a comment on the issue (gh issue comment $ISSUE): the
   answer to the question first, then the evidence for it (what you ran or read,
   with sources specific enough for the reviewer to check without repeating the
   investigation), then what it changes and what it leaves open. If the honest
   answer is 'it depends' or 'no', say that — a research ticket is not obliged
   to produce a yes.
5. If the question cannot be answered as asked (it needs a decision only a human
   can make, or access you do not have), say exactly that in the comment, label
   issue #$ISSUE ready-for-human, and stop.
" "${RESEARCH_FLAGS[@]}")

  # The runner is the guarantor here too: the finding is the deliverable, so a
  # pass that narrated one but posted nothing fails the run — the research
  # analogue of "no open PR for $BRANCH after the implement pass".
  set +e
  verify_finding_landed "$ISSUE" "$FINDING_BASELINE"
  FINDING_RC=$?
  set -e
  if [ "$FINDING_RC" -ne 0 ]; then
    echo "==> No finding recorded on issue #$ISSUE by the research pass (see above)." >&2
    echo "    Nothing to review; the attempt is spent. See the issue for what the pass said." >&2
    exit 1
  fi

  # The escape hatch posts a comment too, so the check above cannot tell it from
  # a finding — the relabel can. A ticket handed back to a human is not reviewed.
  if [ -n "$(gh issue view "$ISSUE" --json labels \
              --jq '.labels[] | select(.name == "ready-for-human") | .name')" ]; then
    echo "==> Issue #$ISSUE is now labelled ready-for-human — the research pass handed it back." >&2
    echo "    Not reviewing a question it says needs a human. See the issue." >&2
    exit 1
  fi

  resolve_reviewer_identity

  REVIEW_LOG="$(mktemp)"   # the review pass's own output — see the verification below
  trap 'rm -f "$REVIEW_LOG"' EXIT

  echo "==> Reviewing the finding on issue #$ISSUE as $REVIEWER_ACTUAL"
  (cd "$WORKTREE" && GH_TOKEN="$REVIEWER_TOKEN" claude -p "
Launch the ticket-reviewer agent to review the research finding recorded on
issue #$ISSUE of this repo, then relay its verdict verbatim.

Context for the reviewer: this is a research ticket (workflow:research), so it
reviews in issue-thread mode — see 'Issue-thread mode (research tickets)' in its
own definition. There is no PR and no diff: what is under review is the finding
comment on the issue (gh issue view $ISSUE --comments), judged against the
question the issue asks. It posts its verdict as a comment on the issue
(gh issue comment $ISSUE), not as a PR review, and nothing merges — an approval
means the question is answered, and the runner then closes the issue.

End your output with the machine-readable verdict on its own final line —
exactly 'VERDICT: approve' (the question is answered and the evidence holds),
'VERDICT: request-changes' (gaps — name them), 'VERDICT: comment' (recommend a
human looks), or 'VERDICT: escalate'. The runner reads that line and checks the
issue for the reviewer's matching verdict comment before reporting success: a
verdict you narrate but never post with gh issue comment fails this run.
" --allowedTools "$(allowed_tools "${REVIEW_VERBS[@]}")") 2>&1 | tee "$REVIEW_LOG"

  set +e
  verify_issue_verdict_landed "$ISSUE" "$REVIEWER_ACTUAL" "$REVIEW_LOG"
  VERIFY_RC=$?
  set -e
  if [ "$VERIFY_RC" -ne 0 ]; then
    echo "==> ERROR: the review pass's verdict is not on issue #$ISSUE as a comment by $REVIEWER_ACTUAL (see above)." >&2
    echo "    Not reporting success on a review GitHub has no record of. A re-run works the ticket" >&2
    echo "    again from the top — there is no PR to dispatch on, so it re-investigates and spends" >&2
    echo "    another attempt." >&2
    exit 1
  fi

  VERDICT="$(claimed_review_verdict "$REVIEW_LOG")"
  if [ "$VERDICT" = "approve" ]; then
    # Closing is this path's 'landing the PR', and the runner does it for the
    # same reason it arms auto-merge rather than letting a pass merge: the
    # question is answered, so the ticket is done. REST, not gh issue close —
    # see the projectCards note above.
    gh api -X PATCH "repos/{owner}/{repo}/issues/$ISSUE" \
      -f state=closed -f state_reason=completed > /dev/null
    echo "==> Done. Issue #$ISSUE — finding recorded and approved by $REVIEWER_ACTUAL; issue closed (attempt $ATTEMPT)."
  else
    echo "==> Done. Issue #$ISSUE stays open — reviewer verdict '$VERDICT' on attempt $ATTEMPT/$MAX_ATTEMPTS."
  fi
  exit 0
fi

# --- Implement pass ----------------------------------------------------------
# Fresh claude process, fresh context. The ticket is the spec.

if [ "$MODE" = "implement" ]; then
  # Non-interactive sessions can't answer permission prompts, so pre-approve
  # the pass's capability contract (IMPLEMENT_VERBS above) — everything the
  # prompt below instructs the agent to run.
  IMPLEMENT_FLAGS=(--permission-mode acceptEdits
    --allowedTools "$(allowed_tools "${IMPLEMENT_VERBS[@]}")")
  [ -n "$AFK" ] && IMPLEMENT_FLAGS=(--dangerously-skip-permissions)

  # NB: prompt must come BEFORE the flags — --allowedTools is variadic and
  # would swallow a trailing prompt as another tool pattern.
  (cd "$WORKTREE" && claude -p "
Work GitHub issue #$ISSUE of this repo. This is attempt $ATTEMPT of $MAX_ATTEMPTS.

1. Read the issue in full (gh issue view $ISSUE --comments). The ticket is the
   spec — do what it asks, all of it, and only it. If the body has a
   'Workflow' section, follow those steps and gates exactly; otherwise follow
   any workflow named by the issue's labels; otherwise use your judgement.
2. Read AGENTS.md / CLAUDE.md, CONTEXT.md, and relevant docs/adr/ entries
   before writing code.
3. Implement on the current branch ($BRANCH). Make small atomic commits.
4. Validate: run the repo's tests and lint (just test / just lint if a
   justfile exists; wrap in 'doppler run --' if the checks need the repo's
   env — that wrapper is pre-approved). Do not proceed with failing checks.
5. Self-review before pushing: run the /code-review skill with fixed point
   origin/$DEFAULT_BRANCH and issue #$ISSUE as the spec. Act on findings you
   agree with; where you disagree, say so in the PR body rather than silently
   ignoring them. This is rework-avoidance, not the gate — a separate
   ticket-reviewer with fresh eyes is still the thing that approves.
6. Push the branch and open a PR titled after the issue, whose body starts
   with 'Closes #$ISSUE'. If a PR for this branch already exists, push to it.
7. Before finishing, confirm the PR is mergeable: gh pr view --json mergeable
   must report MERGEABLE. If it reports CONFLICTING, integrate the current
   default branch — git fetch origin, then git merge origin/$DEFAULT_BRANCH
   (merge only, never rebase, never force-push) — resolve the conflicts,
   re-run the checks, and push again.
8. If you are genuinely blocked (missing decision, contradictory spec),
   comment your findings on issue #$ISSUE, label it ready-for-human, and stop.
" "${IMPLEMENT_FLAGS[@]}")

  PR="$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')"
  if [ -z "$PR" ]; then
    echo "==> No open PR for $BRANCH after implement pass; see issue #$ISSUE for why."
    exit 1
  fi
fi

# --- Mergeability guarantee & repair pass --------------------------------------
# The implement prompt asks the agent to leave the PR mergeable, but the
# runner is the deterministic guarantor: whichever route got here (a fresh
# implement pass, or a dispatch straight to repair), a CONFLICTING PR gets
# exactly one repair pass — a fresh headless session in the issue worktree
# that merges the default branch (merge only — never rebase, never
# force-push), resolves the conflicts, re-runs the repo's checks, and pushes.
# Success falls through to the gates + review sections UNCHANGED: a
# resolution that newly touches a gated path re-gates the PR, and an approval
# the fix-push dismissed gets its review rerun without further wiring. Still
# CONFLICTING after the repair -> escape hatch (findings on the issue,
# relabel ready-for-human), exit non-zero. Fail fast — no retry loop.

if [ "$MODE" != "review-only" ]; then
  MERGE_STATE="$(pr_merge_state "$PR")"
  if [ "$MERGE_STATE" = "CONFLICTING" ]; then
    echo "==> PR #$PR is CONFLICTING with $DEFAULT_BRANCH — running repair pass."
    # Distinct marker: must NOT match the "🤖 Attempt" prefix the attempt
    # counter greps for — repairs never consume an attempt.
    gh issue comment "$ISSUE" --body "🔧 Repair pass starting — merging $DEFAULT_BRANCH into PR #$PR to resolve conflicts." > /dev/null

    # Pre-approve the repair pass's capability contract (REPAIR_VERBS above);
    # --afk is honoured the same way as the implement pass. Same NB: the
    # prompt must come BEFORE --allowedTools.
    REPAIR_FLAGS=(--permission-mode acceptEdits
      --allowedTools "$(allowed_tools "${REPAIR_VERBS[@]}")")
    [ -n "$AFK" ] && REPAIR_FLAGS=(--dangerously-skip-permissions)

    (cd "$WORKTREE" && claude -p "
PR #$PR (branch $BRANCH) for issue #$ISSUE is CONFLICTING with
$DEFAULT_BRANCH — the default branch has moved underneath it. Repair the PR
so it is mergeable again. Merge only: never rebase, never force-push.

1. Read the issue for context (gh issue view $ISSUE --comments) and check the
   PR (gh pr view $PR).
2. Integrate the default branch: git fetch origin, then
   git merge origin/$DEFAULT_BRANCH.
3. Resolve the conflicts with the /resolving-merge-conflicts skill; stage the
   resolved files (git add) and complete the merge (git commit).
4. Validate: run the repo's tests and lint (just test / just lint if a
   justfile exists; wrap in 'doppler run --' if the checks need the repo's
   env — that wrapper is pre-approved). Do not push failing checks.
5. Push the branch (git push) and confirm the PR reports MERGEABLE
   (gh pr view $PR --json mergeable).
6. If you cannot produce a sound resolution (the conflict needs a decision
   only a human can make), comment your findings on issue #$ISSUE, label it
   ready-for-human, and stop.
" "${REPAIR_FLAGS[@]}")

    MERGE_STATE="$(pr_merge_state "$PR")"
    if [ "$MERGE_STATE" = "CONFLICTING" ]; then
      echo "==> PR #$PR is still CONFLICTING after the repair pass. Flagging for a human." >&2
      gh issue comment "$ISSUE" --body "🔧 Repair pass could not make PR #$PR mergeable — still CONFLICTING with $DEFAULT_BRANCH after a merge attempt. The conflicts need a human resolution (merge, never rebase). Flagging ready-for-human."
      # REST, not gh issue edit — see the projectCards note above.
      gh api "repos/{owner}/{repo}/issues/$ISSUE/labels" -f 'labels[]=ready-for-human' > /dev/null
      gh api -X DELETE "repos/{owner}/{repo}/issues/$ISSUE/labels/ready-for-agent" > /dev/null || true
      exit 1
    fi
    echo "==> Repair pass done — PR #$PR is MERGEABLE; continuing to gates + review."
  fi
fi

# --- Deterministic review gates ------------------------------------------------
# Whether this PR may auto-land is decided here, by globs — not by the
# reviewer's judgement. Gated -> human-signoff label, auto-merge stays off.
# Ungated -> arm auto-merge; the reviewer's approval lands it.
# The repo's gate extension is read from the default branch, never the PR
# branch, so a PR cannot re-write its own gates.

mapfile -t CHANGED < <(gh pr diff "$PR" --name-only)

GATES_PLATFORM="$SCRIPT_DIR/../standards/review-gates.yaml"
GATES_REPO=""
GATES_REPO_TMP="$(mktemp)"
REVIEW_LOG="$(mktemp)"   # the review pass's own output — see the verification below
trap 'rm -f "$GATES_REPO_TMP" "$REVIEW_LOG"' EXIT
git fetch origin "$DEFAULT_BRANCH" --quiet || true
if git -C "$WORKTREE" show "origin/$DEFAULT_BRANCH:docs/agents/review-gates.yaml" \
    > "$GATES_REPO_TMP" 2>/dev/null; then
  GATES_REPO="$GATES_REPO_TMP"
fi

set +e
GATE_MATCHES="$(evaluate_review_gates "$GATES_PLATFORM" "$GATES_REPO" "${CHANGED[@]}")"
GATE_RC=$?
set -e

if [ "$GATE_RC" -eq 0 ]; then
  echo "==> Review gate matched — human sign-off required, auto-merge stays off."
  echo "$GATE_MATCHES" | sed 's/^/    /'
  gh pr merge --disable-auto "$PR" > /dev/null 2>&1 || true
  # REST, not gh pr edit — see the projectCards note above.
  gh api "repos/{owner}/{repo}/issues/$PR/labels" -f 'labels[]=human-signoff' > /dev/null 2>&1 \
    || echo "==> WARNING: could not apply human-signoff label — does it exist? (scripts/setup-reviewer.sh creates it)"
  gh pr comment "$PR" --body "🔒 Deterministic review gate matched — auto-merge disarmed; a human merges after review.

| gate | glob | path |
|---|---|---|
$(echo "$GATE_MATCHES" | awk -F'\t' '{printf "| %s | `%s` | `%s` |\n", $1, $2, $3}')" > /dev/null
  GATE_NOTE="This PR is GATED for human sign-off (deterministic path gates matched). Approving is safe and expected if the work is sound: approval only satisfies branch protection; a human performs the merge."
elif [ "$GATE_RC" -eq 1 ]; then
  echo "==> No review gate matched — arming auto-merge (squash)."
  if gh pr merge --auto --squash "$PR" > /dev/null 2>&1; then
    GATE_NOTE="This PR is ARMED for auto-merge: your approval will land it on $DEFAULT_BRANCH immediately. If you conclude a human should look despite the work being complete, do NOT approve — disarm ('gh pr merge --disable-auto $PR'), add the human-signoff label, and leave a comment-type review instead."
  else
    echo "==> WARNING: could not arm auto-merge — has this repo run scripts/setup-reviewer.sh?"
    GATE_NOTE="Auto-merge could not be armed (repo may not be onboarded); approval will not auto-land this PR."
  fi
else
  echo "==> ERROR: review-gate config unusable (see above). Failing closed: not arming auto-merge, not reviewing." >&2
  echo "    Fix standards/review-gates.yaml (or the repo's docs/agents/review-gates.yaml) and re-run." >&2
  exit 1
fi

# --- Review pass -------------------------------------------------------------
# Separate process = genuinely fresh eyes, and a separate GitHub identity =
# approvals GitHub accepts. The reviewer approves, requests changes, or
# escalates; it never edits code. Its PAT comes from Doppler and is exported
# only around this pass — the implement pass never sees it.

resolve_reviewer_identity

echo "==> Reviewing PR #$PR as $REVIEWER_ACTUAL"
# Pre-approve the reviewer's capability contract (REVIEW_VERBS above). Same
# NB as the implement pass: the prompt must come BEFORE --allowedTools.
# Output is teed: the verdict line the verification below reads has to survive
# the pass, and the operator still watches the review live.
(cd "$WORKTREE" && GH_TOKEN="$REVIEWER_TOKEN" claude -p "
Launch the ticket-reviewer agent to review PR #$PR (originating issue #$ISSUE),
then relay its verdict verbatim.

Context for the reviewer: $GATE_NOTE

End your output with the machine-readable verdict on its own final line —
exactly 'VERDICT: approve', 'VERDICT: request-changes', 'VERDICT: comment'
(recommend human sign-off), or 'VERDICT: escalate'. The runner reads that line
and checks GitHub for the matching review before reporting success: a verdict
you narrate but never submit with gh pr review fails this run.
" --allowedTools "$(allowed_tools "${REVIEW_VERBS[@]}")") 2>&1 | tee "$REVIEW_LOG"

# --- Review side-effect verification -------------------------------------------
# The runner is the deterministic guarantor here too: a pass's narration is not
# evidence that GitHub recorded anything. interlude PR #99 (2026-08-05) produced
# a complete 'VERDICT: approve' with reasoning and reported "my approval
# satisfies branch protection" while GitHub showed reviews: [] /
# reviewDecision: REVIEW_REQUIRED — the pass skipped or lost its
# `gh pr review` step and narrated success anyway, and the runner exited 0.
# Same shape as the capability-contract failures (interlude#29 / platform#12):
# claims drifting from side effects. So: read the claimed verdict, read the
# reviewer identity's actual review off the PR, and require them to agree —
# an unverifiable review (no machine-readable verdict, or an API read that
# failed) is a failure, never a pass.
set +e
verify_review_landed "$PR" "$REVIEWER_ACTUAL" "$REVIEW_LOG"
VERIFY_RC=$?
set -e
if [ "$VERIFY_RC" -ne 0 ]; then
  echo "==> ERROR: the review pass's verdict is not on PR #$PR as reviewed by $REVIEWER_ACTUAL (see above)." >&2
  echo "    Not reporting success on a review GitHub has no record of. Re-run to review again;" >&2
  echo "    the PR-state dispatch routes an unreviewed MERGEABLE PR straight back to gates + review." >&2
  exit 1
fi

case "$MODE" in
  implement)   echo "==> Done. Issue #$ISSUE, PR #$PR, attempt $ATTEMPT." ;;
  repair)      echo "==> Done. Issue #$ISSUE, PR #$PR, repair pass (no attempt consumed)." ;;
  review-only) echo "==> Done. Issue #$ISSUE, PR #$PR, gates + review only (no attempt consumed)." ;;
esac
