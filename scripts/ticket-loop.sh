#!/usr/bin/env bash
# ticket-loop.sh — thin per-ticket runner for the ticket-loop workflow
# (see choices/ai-dev-workflow.md).
#
# One invocation = one ticket, one attempt:
#   pick a ready-for-agent issue -> worktree -> implement pass (claude -p)
#   -> review pass (fresh context) -> report.
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
# Requires: gh (authenticated), git, claude.

set -euo pipefail

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
REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"

# --- Pick a ticket -----------------------------------------------------------

if [ -z "$ISSUE" ]; then
  ISSUE="$(gh issue list --label ready-for-agent --state open \
    --json number --jq 'sort_by(.number) | .[0].number // empty')"
  if [ -z "$ISSUE" ]; then
    echo "No open ready-for-agent issues. Nothing to do."
    exit 0
  fi
fi
echo "==> Issue #$ISSUE in $REPO_NAME"

# --- Attempt accounting ------------------------------------------------------
# Attempts are visible on the issue as comments; after MAX_ATTEMPTS the ticket
# goes back to a human instead of thrashing.

ATTEMPT=$(( $(gh issue view "$ISSUE" --comments --json comments \
  --jq '[.comments[].body | select(startswith("🤖 Attempt"))] | length') + 1 ))

if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
  echo "Issue #$ISSUE already has $((ATTEMPT - 1)) attempts. Flagging for a human."
  gh issue edit "$ISSUE" --remove-label ready-for-agent --add-label ready-for-human
  gh issue comment "$ISSUE" --body "🤖 $((ATTEMPT - 1)) agent attempts without an approved PR — flagging ready-for-human."
  exit 1
fi
gh issue comment "$ISSUE" --body "🤖 Attempt $ATTEMPT/$MAX_ATTEMPTS starting." > /dev/null
echo "==> Attempt $ATTEMPT/$MAX_ATTEMPTS"

# --- Worktree ----------------------------------------------------------------

BRANCH="agent/issue-$ISSUE"
WORKTREE="$(git rev-parse --show-toplevel)/../${REPO_NAME}-issue-${ISSUE}"

if [ ! -d "$WORKTREE" ]; then
  DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
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

IMPLEMENT_FLAGS=(--permission-mode acceptEdits)
[ -n "$AFK" ] && IMPLEMENT_FLAGS=(--dangerously-skip-permissions)

(cd "$WORKTREE" && claude -p "${IMPLEMENT_FLAGS[@]}" "
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
5. Push the branch and open a PR titled after the issue, whose body starts
   with 'Closes #$ISSUE'. If a PR for this branch already exists, push to it.
6. If you are genuinely blocked (missing decision, contradictory spec),
   comment your findings on issue #$ISSUE, label it ready-for-human, and stop.
")

# --- Review pass -------------------------------------------------------------
# Separate process = genuinely fresh eyes. The reviewer approves, requests
# changes, or escalates; it never edits code.

PR="$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')"
if [ -z "$PR" ]; then
  echo "==> No open PR for $BRANCH after implement pass; see issue #$ISSUE for why."
  exit 1
fi

echo "==> Reviewing PR #$PR"
(cd "$WORKTREE" && claude -p "
Launch the ticket-reviewer agent to review PR #$PR (originating issue #$ISSUE),
then relay its verdict verbatim.
")

echo "==> Done. Issue #$ISSUE, PR #$PR, attempt $ATTEMPT."
