#!/usr/bin/env bash
# ticket-loop.sh — thin per-ticket runner for the ticket-loop workflow
# (see choices/ai-dev-workflow.md).
#
# One invocation = one ticket, one attempt:
#   pick a ready-for-agent issue -> worktree -> implement pass (claude -p)
#   -> deterministic review gates (arm auto-merge, or human-signoff)
#   -> review pass (fresh context, reviewer identity) -> report.
#
# The review pass runs as the reviewer machine account (PAT fetched from
# Doppler), so its approvals are accepted by GitHub. Whether an approval may
# auto-land the PR is decided deterministically BEFORE review: changed paths
# are matched against standards/review-gates.yaml (+ the repo's own
# docs/agents/review-gates.yaml); ungated PRs are armed with
# `gh pr merge --auto`, gated PRs are labelled human-signoff and left
# disarmed. See standards/review-gates.md and choices/ai-dev-workflow.md.
#
# Parallelism = run several invocations against different issues; each gets
# its own worktree and branch. No orchestrator.
#
# Usage:
#   ./scripts/ticket-loop.sh [--issue N] [--repo-dir PATH] [--afk]
#
#   --issue N      work this issue instead of picking the oldest ready-for-agent
#   --repo-dir     project repo to operate on (default: current directory)
#   --afk          fully unattended: passes --dangerously-skip-permissions to
#                  the implement pass. Only for repos where issue creation and
#                  labelling are restricted to you (prompt-injection caution).
#
# Requires: gh (authenticated), git, claude, yq, jq, doppler (logged in; the
# reviewer PAT lives in Doppler — see 'Reviewer identity & onboarding' in
# choices/ai-dev-workflow.md). Onboard a repo with scripts/setup-reviewer.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/review-gates-lib.sh"

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

# --- Permission preflight ------------------------------------------------------
# The implement pass pre-approves git push / doppler run via --allowedTools,
# but permission rules evaluate deny -> ask -> allow with the FIRST match
# winning: an ask/deny rule covering those commands beats any allow from any
# source, and a non-interactive pass cannot answer an ask prompt, so the push
# dies mid-run (worktree sessions resolve .claude/settings*.json to this
# checkout). Fail fast naming the offending rule instead.
if [ -z "$AFK" ]; then  # --afk skips permissions entirely, nothing can block it
  command -v jq > /dev/null || { echo "ERROR: jq is required." >&2; exit 1; }
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
      for NEED in "git push" "doppler run"; do
        case "$NEED" in "$PREFIX"*) BLOCKING+="$SETTINGS: $RULE"$'\n'; continue 2 ;; esac
        case "$PREFIX" in "$NEED"*) BLOCKING+="$SETTINGS: $RULE"$'\n'; continue 2 ;; esac
      done
    done < <(jq -r '((.permissions.ask // []) + (.permissions.deny // []))[]
                    | select(. == "Bash" or startswith("Bash("))' "$SETTINGS" 2>/dev/null)
  done
  if [ -n "$BLOCKING" ]; then
    echo "==> ERROR: ask/deny permission rules would block the implement pass's git push / doppler run:" >&2
    printf '%s' "$BLOCKING" | sed 's/^/    /' >&2
    echo "    These beat --allowedTools (deny -> ask -> allow, first match wins), and a" >&2
    echo "    non-interactive pass cannot answer an ask prompt. Remove or relax the rule(s)," >&2
    echo "    or run with --afk. See 'Per-repo onboarding' in choices/ai-dev-workflow.md." >&2
    exit 1
  fi
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

# Explicit --issue bypasses the pick above, so guard it here too — loudly, since
# naming a wayfinder ticket directly is a mistake rather than a quiet skip.
if gh issue view "$ISSUE" --json labels \
    --jq '[.labels[].name | startswith("wayfinder:")] | any' | grep -q true; then
  echo "==> ERROR: issue #$ISSUE is a wayfinder ticket (wayfinder:* label)." >&2
  echo "    Wayfinder tickets resolve decisions, not code — work it with /wayfinder." >&2
  echo "    See 'Plan, don't do' in choices/ai-dev-workflow.md." >&2
  exit 1
fi

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

# --- Attempt accounting ------------------------------------------------------
# Attempts are visible on the issue as comments; after MAX_ATTEMPTS the ticket
# goes back to a human instead of thrashing.

ATTEMPT=$(( $(gh issue view "$ISSUE" --comments --json comments \
  --jq '[.comments[].body | select(startswith("🤖 Attempt"))] | length') + 1 ))

if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
  echo "Issue #$ISSUE already has $((ATTEMPT - 1)) attempts. Flagging for a human."
  # Label ops use REST: gh's GraphQL editors (gh pr/issue edit) query the
  # sunset projectCards field and error out (observed 2026-07-28, gh 2.45).
  gh api "repos/{owner}/{repo}/issues/$ISSUE/labels" -f 'labels[]=ready-for-human' > /dev/null
  gh api -X DELETE "repos/{owner}/{repo}/issues/$ISSUE/labels/ready-for-agent" > /dev/null || true
  gh issue comment "$ISSUE" --body "🤖 $((ATTEMPT - 1)) agent attempts without an approved PR — flagging ready-for-human."
  exit 1
fi
gh issue comment "$ISSUE" --body "🤖 Attempt $ATTEMPT/$MAX_ATTEMPTS starting." > /dev/null
echo "==> Attempt $ATTEMPT/$MAX_ATTEMPTS"

# --- Worktree ----------------------------------------------------------------

BRANCH="agent/issue-$ISSUE"
WORKTREE="$(git rev-parse --show-toplevel)/../${REPO_NAME}-issue-${ISSUE}"

DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"

if [ ! -d "$WORKTREE" ]; then
  git fetch origin "$DEFAULT_BRANCH"
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git worktree add "$WORKTREE" "$BRANCH"
  else
    git worktree add -b "$BRANCH" "$WORKTREE" "origin/$DEFAULT_BRANCH"
  fi
fi
echo "==> Worktree: $WORKTREE"

# --- Implement pass ----------------------------------------------------------
# Fresh claude process, fresh context. The ticket is the spec.

# Non-interactive sessions can't answer permission prompts, so pre-approve
# what the loop's contract requires: pushing the branch and running the
# repo's checks under doppler-injected env. (Prompting on git push while gh
# api writes are allowed was cosmetic anyway — same capability.)
IMPLEMENT_FLAGS=(--permission-mode acceptEdits
  --allowedTools "Bash(git push:*),Bash(doppler run:*)")
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
   justfile exists). Do not proceed with failing checks.
5. Self-review before pushing: run the /code-review skill with fixed point
   origin/$DEFAULT_BRANCH and issue #$ISSUE as the spec. Act on findings you
   agree with; where you disagree, say so in the PR body rather than silently
   ignoring them. This is rework-avoidance, not the gate — a separate
   ticket-reviewer with fresh eyes is still the thing that approves.
6. Push the branch and open a PR titled after the issue, whose body starts
   with 'Closes #$ISSUE'. If a PR for this branch already exists, push to it.
7. If you are genuinely blocked (missing decision, contradictory spec),
   comment your findings on issue #$ISSUE, label it ready-for-human, and stop.
" "${IMPLEMENT_FLAGS[@]}")

PR="$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')"
if [ -z "$PR" ]; then
  echo "==> No open PR for $BRANCH after implement pass; see issue #$ISSUE for why."
  exit 1
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
trap 'rm -f "$GATES_REPO_TMP"' EXIT
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

echo "==> Reviewing PR #$PR as $REVIEWER_ACTUAL"
(cd "$WORKTREE" && GH_TOKEN="$REVIEWER_TOKEN" claude -p "
Launch the ticket-reviewer agent to review PR #$PR (originating issue #$ISSUE),
then relay its verdict verbatim.

Context for the reviewer: $GATE_NOTE
")

echo "==> Done. Issue #$ISSUE, PR #$PR, attempt $ATTEMPT."
