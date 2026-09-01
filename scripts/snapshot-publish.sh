#!/usr/bin/env bash
# Publish the estate conformity snapshot without pushing to a protected branch.
#
# This repo is governed by the reviewer flow it publishes: `setup-reviewer.sh`
# put branch protection on its own default branch, so the conformity workflow
# can no longer `git push` the snapshot straight to it. Instead:
#
#   1. every run force-updates a machine-owned *feed branch*
#      (default `automation/conformity-snapshot`) with the fresh snapshot —
#      that branch is the always-current, durable copy the estate dashboard
#      and the staleness watchdog read;
#   2. when the snapshot changed *semantically* (i.e. ignoring `generated_at`
#      and `platform_commit` churn), it also opens a PR from that branch onto
#      the default branch, so the committed copy still lands the way every
#      other change to this repo does — through review. That PR touches only
#      the snapshot, which matches no glob in `standards/review-gates.yaml`,
#      so it is gate-clear and auto-merge is armed on it.
#
#   ./scripts/snapshot-publish.sh --snapshot data/conformity-snapshot.json \
#       --repo lennons301/platform
#
# The feed branch is rebuilt from the base branch on every run, so its diff is
# always exactly one file and it never needs merging or conflict resolution —
# hence the force-push. Nothing but this script writes to it.
#
# Exit codes: 0 = published (or deliberately left alone), 1 = error.
set -uo pipefail

SNAPSHOT=""
REPO="${GITHUB_REPOSITORY:-}"
REPO_DIR="$PWD"
BASE=""
BRANCH="automation/conformity-snapshot"
SNAPSHOT_PATH="data/conformity-snapshot.json"
REMOTE="origin"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: snapshot-publish.sh --snapshot <path> [options]

Options:
  --snapshot <path>    Freshly generated snapshot to publish (required)
  --repo <owner/name>  Repository to open the PR on (default: $GITHUB_REPOSITORY)
  --repo-dir <path>    Git checkout to publish from (default: cwd)
  --base <branch>      Branch the PR targets (default: the checkout's current branch)
  --branch <name>      Feed branch to force-update
                       (default: automation/conformity-snapshot)
  --path <path>        Repo-relative path of the snapshot
                       (default: data/conformity-snapshot.json)
  --remote <name>      Git remote to push to (default: origin)
  --dry-run            Report what would be published without pushing
  -h, --help           Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --snapshot) SNAPSHOT="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --repo-dir) REPO_DIR="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --path) SNAPSHOT_PATH="${2:-}"; shift 2 ;;
    --remote) REMOTE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$SNAPSHOT" ]; then
  echo "ERROR: --snapshot is required." >&2
  usage >&2
  exit 1
fi
if [ ! -f "$SNAPSHOT" ]; then
  echo "ERROR: snapshot not found: $SNAPSHOT" >&2
  exit 1
fi
SNAPSHOT="$(cd "$(dirname "$SNAPSHOT")" && pwd)/$(basename "$SNAPSHOT")"

for cmd in git jq; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "ERROR: $cmd is required." >&2
    exit 1
  fi
done
if [ "$DRY_RUN" = false ] && ! command -v gh > /dev/null 2>&1; then
  echo "ERROR: gh is required (or pass --dry-run)." >&2
  exit 1
fi

if ! git -C "$REPO_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: not a git checkout: $REPO_DIR" >&2
  exit 1
fi

if [ -z "$BASE" ]; then
  BASE="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ -z "$BASE" ] || [ "$BASE" = "HEAD" ]; then
    echo "ERROR: could not infer the base branch — pass --base." >&2
    exit 1
  fi
fi

# Fetch the base tip explicitly: a shallow CI checkout has no guarantee of a
# usable remote-tracking ref, and the feed branch must be built on the base
# branch as it is *now*, not as it was when the job started.
if ! out=$(git -C "$REPO_DIR" fetch --quiet --depth 1 "$REMOTE" \
    "+refs/heads/$BASE:refs/remotes/$REMOTE/$BASE" 2>&1); then
  echo "ERROR: could not fetch $BASE from $REMOTE: $out" >&2
  exit 1
fi
BASE_REF="refs/remotes/$REMOTE/$BASE"

# --- has the conformity content actually changed? -------------------------------

semantic() { jq -S 'del(.generated_at, .platform_commit)' "$1" 2>/dev/null; }

new_semantic=$(semantic "$SNAPSHOT")
if [ -z "$new_semantic" ]; then
  echo "ERROR: $SNAPSHOT is not valid JSON." >&2
  exit 1
fi

CHANGED=true
old_file=$(mktemp)
trap 'rm -f "$old_file"' EXIT
if git -C "$REPO_DIR" show "$BASE_REF:$SNAPSHOT_PATH" > "$old_file" 2>/dev/null; then
  if [ "$(semantic "$old_file")" = "$new_semantic" ]; then
    CHANGED=false
  fi
else
  echo "No snapshot at $SNAPSHOT_PATH on $BASE yet — treating this one as new."
fi

if [ "$CHANGED" = true ]; then
  echo "Snapshot changed semantically against $BASE."
else
  echo "No semantic change to the snapshot against $BASE (timestamp churn only)."
fi

# --- 1. force-update the feed branch (every run) --------------------------------

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: would update $REMOTE/$BRANCH with $SNAPSHOT_PATH."
  if [ "$CHANGED" = true ]; then
    echo "DRY RUN: would open or refresh a PR from $BRANCH onto $BASE."
  fi
  exit 0
fi

WORKDIR=$(mktemp -d)
cleanup() {
  git -C "$REPO_DIR" worktree remove --force "$WORKDIR/wt" > /dev/null 2>&1
  rm -rf "$WORKDIR"
  rm -f "$old_file"
}
trap cleanup EXIT

if ! out=$(git -C "$REPO_DIR" worktree add --detach "$WORKDIR/wt" "$BASE_REF" 2>&1); then
  echo "ERROR: could not create a worktree at $BASE: $out" >&2
  exit 1
fi

mkdir -p "$(dirname "$WORKDIR/wt/$SNAPSHOT_PATH")"
cp "$SNAPSHOT" "$WORKDIR/wt/$SNAPSHOT_PATH"
if ! out=$(git -C "$WORKDIR/wt" add -- "$SNAPSHOT_PATH" 2>&1); then
  # Unchecked, this would fall through to the "already byte-identical" branch
  # below and report success for a snapshot that was never staged.
  echo "ERROR: could not stage $SNAPSHOT_PATH: $out" >&2
  exit 1
fi

if git -C "$WORKDIR/wt" diff --cached --quiet; then
  echo "Feed branch is already byte-identical to $BASE — nothing to publish."
  exit 0
fi

generated_at=$(jq -r '.generated_at // "unknown"' "$SNAPSHOT")
total_gaps=$(jq -r '.total_gaps // "?"' "$SNAPSHOT")
total_products=$(jq -r '.total_products_checked // "?"' "$SNAPSHOT")

if ! out=$(git -C "$WORKDIR/wt" \
    -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "chore: update conformity snapshot ($generated_at)" 2>&1); then
  echo "ERROR: could not commit the snapshot: $out" >&2
  exit 1
fi

if ! out=$(git -C "$WORKDIR/wt" push --force "$REMOTE" "HEAD:refs/heads/$BRANCH" 2>&1); then
  echo "ERROR: could not push the feed branch $BRANCH: $out" >&2
  exit 1
fi
echo "Feed branch $BRANCH updated (generated $generated_at)."

# --- 2. open the PR when the conformity content moved ---------------------------

if [ "$CHANGED" = false ]; then
  echo "No PR needed — the committed snapshot on $BASE is still semantically current."
  exit 0
fi

if [ -z "$REPO" ]; then
  echo "ERROR: --repo (or \$GITHUB_REPOSITORY) is required to open the snapshot PR." >&2
  exit 1
fi

# Arm auto-merge so the PR lands the moment it goes green and gets its approval,
# instead of waiting for someone to come back and press the button. This repo's
# protection requires one approving review, so this does NOT make the snapshot
# self-merging — it removes the second human step, not the first.
#
# Best-effort by design: the feed branch is already updated and is the home
# consumers read, so a PR that stays disarmed delays the reviewed copy without
# stalling the feed. Failing the run here would turn a cosmetic problem into a
# red build that suppresses nothing useful.
arm_auto_merge() { # <pr-number-or-url>
  if out=$(gh pr merge "$1" --repo "$REPO" --auto --squash 2>&1); then
    echo "Auto-merge armed on the snapshot PR."
  else
    echo "WARNING: could not arm auto-merge on the snapshot PR: $out" >&2
  fi
}

existing=$(gh pr list --repo "$REPO" --head "$BRANCH" --base "$BASE" --state open \
  --json number --jq '.[0].number' 2>/dev/null || echo "")
if [ -n "$existing" ] && [ "$existing" != "null" ]; then
  echo "PR #$existing already open from $BRANCH — refreshed with the new snapshot."
  # Re-arm rather than assume: an earlier run may have failed to arm, and a
  # push to the head branch can drop auto-merge again.
  arm_auto_merge "$existing"
  exit 0
fi

body="The estate conformity content changed. \`$SNAPSHOT_PATH\` is the machine-readable
contract behind \`checks/create-issues.sh\` and the planned estate dashboard, so the
committed copy needs to move with it.

- **Generated:** $generated_at
- **Gaps:** $total_gaps across $total_products product(s)

Nothing here is hand-written: the branch is rebuilt from \`$BASE\` on every run of the
\`Estate Conformity Check\` workflow, so it is safe to merge or to leave for the next
run to refresh. The always-current copy lives on the \`$BRANCH\` branch either way —
merging this only updates the committed one.

Auto-merge is armed, and this PR is gate-clear (it touches only \`$SNAPSHOT_PATH\`,
which matches no glob in \`standards/review-gates.yaml\`) — so one approval lands it,
with no second trip back to press merge.

<sub>Opened by \`scripts/snapshot-publish.sh\`. This repo's own branch protection is
why the snapshot arrives as a PR rather than a direct push.</sub>"

if ! out=$(gh pr create --repo "$REPO" --base "$BASE" --head "$BRANCH" \
    --title "chore: update conformity snapshot" --body "$body" 2>&1); then
  echo "ERROR: could not open the snapshot PR: $out" >&2
  exit 1
fi
echo "Opened a snapshot PR: $out"

# `gh pr create` prints the PR URL, but 2>&1 above means notices can share the
# capture — take the trailing number off the last URL-shaped line rather than
# trusting the whole blob to be one URL.
pr_number=$(printf '%s\n' "$out" | grep -oE '/pull/[0-9]+' | tail -1 | grep -oE '[0-9]+')
if [ -n "$pr_number" ]; then
  arm_auto_merge "$pr_number"
else
  echo "WARNING: could not read the new PR number from gh output — auto-merge not armed." >&2
fi
