#!/usr/bin/env bash
# Close a GitHub milestone once its last open issue closes.
#
# GitHub tracks milestone progress ("X of Y closed") but never flips the
# milestone's own state — it stays `open` at 100% until a human closes it.
# This script is the capstone step, run by the estate's reusable workflow
# (.github/workflows/milestone-autoclose.yml) on every `issues: closed` event.
#
#   ./scripts/milestone-autoclose.sh --repo owner/name --milestone 1
#
# It is a no-op when open issues remain and idempotent when the milestone is
# already closed, so re-running it is always safe.
#
# Exit codes: 0 = handled (closed, or deliberately left alone), 1 = error.
set -uo pipefail

REPO=""
MILESTONE=""
COMMENT_ISSUE=""
OPT_OUT_MARKER="[no-autoclose]"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: milestone-autoclose.sh --repo <owner/name> --milestone <number> [options]

Options:
  --repo <owner/name>      Repository owning the milestone (required)
  --milestone <number>     Milestone number (required)
  --comment-issue <number> Comment on this issue when the milestone is closed
  --opt-out-marker <text>  Skip milestones whose description contains this
                           text (default: "[no-autoclose]")
  --dry-run                Report the decision without closing anything
  -h, --help               Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --milestone) MILESTONE="${2:-}"; shift 2 ;;
    --comment-issue) COMMENT_ISSUE="${2:-}"; shift 2 ;;
    --opt-out-marker) OPT_OUT_MARKER="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$REPO" ] || [ -z "$MILESTONE" ]; then
  echo "ERROR: --repo and --milestone are required." >&2
  usage >&2
  exit 1
fi

for cmd in gh jq; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "ERROR: $cmd is required." >&2
    exit 1
  fi
done

if ! milestone_json=$(gh api "repos/$REPO/milestones/$MILESTONE" 2>&1); then
  echo "ERROR: could not read milestone $MILESTONE of $REPO: $milestone_json" >&2
  exit 1
fi

state=$(printf '%s' "$milestone_json" | jq -r '.state // ""')
title=$(printf '%s' "$milestone_json" | jq -r '.title // ""')
description=$(printf '%s' "$milestone_json" | jq -r '.description // ""')
# open_issues counts open PRs assigned to the milestone too — deliberate: work
# in review is not finished work.
open_issues=$(printf '%s' "$milestone_json" | jq -r '.open_issues // 0')

if [ -z "$state" ]; then
  echo "ERROR: milestone $MILESTONE of $REPO returned no state." >&2
  exit 1
fi

label="milestone #$MILESTONE ($title)"

if [ "$state" = "closed" ]; then
  echo "$label is already closed — nothing to do."
  exit 0
fi

if [ -n "$OPT_OUT_MARKER" ] && [[ "$description" == *"$OPT_OUT_MARKER"* ]]; then
  echo "$label opts out via \"$OPT_OUT_MARKER\" in its description — leaving it open."
  exit 0
fi

if [ "$open_issues" != "0" ]; then
  echo "$label still has $open_issues open issue(s) — leaving it open."
  exit 0
fi

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: would close $label (0 open issues)."
  exit 0
fi

if ! out=$(gh api -X PATCH "repos/$REPO/milestones/$MILESTONE" -f state=closed 2>&1); then
  echo "ERROR: failed to close $label: $out" >&2
  exit 1
fi
echo "Closed $label — its last open issue is done."

if [ -n "$COMMENT_ISSUE" ]; then
  body="Closing this issue emptied **$title**, so the milestone was closed automatically.

<sub>Automated by the platform's \`milestone-autoclose\` workflow. Add \`$OPT_OUT_MARKER\` to a milestone description to opt out.</sub>"
  if ! out=$(gh issue comment "$COMMENT_ISSUE" --repo "$REPO" --body "$body" 2>&1); then
    # A missing comment is cosmetic; the milestone is already closed.
    echo "WARN: could not comment on issue #$COMMENT_ISSUE: $out" >&2
  fi
fi
