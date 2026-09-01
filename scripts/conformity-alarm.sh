#!/usr/bin/env bash
# Raise (and clear) the alarm when the estate conformity feed stops updating.
#
# The estate's own invariant — "the coordinator verifies side effects, never a
# pass's narration" (choices/ai-dev-workflow.md, "Verified side effects") — was
# never applied to the job that watches every product: the Estate Conformity
# Check failed silently on every scheduled run for a month and the only place
# that said so was the Actions tab. This is the thing that says so out loud.
#
#   ./scripts/conformity-alarm.sh --repo lennons301/platform \
#       --snapshot /tmp/feed-snapshot.json
#
# It files exactly one open tracking issue while the feed is broken (repeat
# runs are a no-op, not a comment stream) and closes it as soon as a fresh
# snapshot shows up. Exit code: 0 = feed healthy, 1 = alarm raised or error, so
# the watchdog run is red for as long as the feed is.
set -uo pipefail

REPO="${GITHUB_REPOSITORY:-}"
SNAPSHOT=""
MAX_AGE_HOURS=48
FAILED_RUN=""
LABEL="ready-for-human"
NOW=""
DRY_RUN=false

MARKER="<!-- platform-alarm:conformity-feed -->"
TITLE="[platform] Estate conformity feed has stopped updating"

usage() {
  cat <<'EOF'
Usage: conformity-alarm.sh --repo <owner/name> [options]

Options:
  --repo <owner/name>    Repository the alarm issue lives on
                         (default: $GITHUB_REPOSITORY)
  --snapshot <path>      Snapshot whose generated_at is checked for staleness
  --max-age-hours <n>    Age at which the snapshot is stale (default: 48)
  --failed-run <url>     Raise the alarm for a failed workflow run instead of
                         judging snapshot age; the URL goes in the issue
  --label <name>         Label for the alarm issue (default: ready-for-human)
  --now <iso8601>        Treat this as the current time (for tests)
  --dry-run              Report the decision without touching GitHub
  -h, --help             Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --snapshot) SNAPSHOT="${2:-}"; shift 2 ;;
    --max-age-hours) MAX_AGE_HOURS="${2:-}"; shift 2 ;;
    --failed-run) FAILED_RUN="${2:-}"; shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --now) NOW="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$REPO" ]; then
  echo "ERROR: --repo (or \$GITHUB_REPOSITORY) is required." >&2
  usage >&2
  exit 1
fi
if [ -z "$FAILED_RUN" ] && [ -z "$SNAPSHOT" ]; then
  echo "ERROR: pass --snapshot (staleness check) or --failed-run (failure alarm)." >&2
  usage >&2
  exit 1
fi
if ! [[ "$MAX_AGE_HOURS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --max-age-hours must be a whole number of hours." >&2
  exit 1
fi

for cmd in jq date; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "ERROR: $cmd is required." >&2
    exit 1
  fi
done
if [ "$DRY_RUN" = false ] && ! command -v gh > /dev/null 2>&1; then
  echo "ERROR: gh is required (or pass --dry-run)." >&2
  exit 1
fi

if [ -n "$NOW" ]; then
  now_epoch=$(date -u -d "$NOW" +%s 2>/dev/null)
  if [ -z "$now_epoch" ]; then
    echo "ERROR: --now is not a parseable timestamp: $NOW" >&2
    exit 1
  fi
else
  now_epoch=$(date -u +%s)
fi

# --- decide: is the feed broken, and how? ---------------------------------------

PROBLEM=""       # empty = healthy
DETAIL=""

if [ -n "$FAILED_RUN" ]; then
  PROBLEM="The \`Estate Conformity Check\` workflow run failed."
  DETAIL="- **Failed run:** $FAILED_RUN"
elif [ ! -f "$SNAPSHOT" ]; then
  PROBLEM="No conformity snapshot could be found at all."
  DETAIL="- **Expected at:** \`$SNAPSHOT\`"
else
  generated_at=$(jq -r '.generated_at // empty' "$SNAPSHOT" 2>/dev/null)
  generated_epoch=""
  if [ -n "$generated_at" ]; then
    generated_epoch=$(date -u -d "$generated_at" +%s 2>/dev/null)
  fi
  if [ -z "$generated_epoch" ]; then
    PROBLEM="The conformity snapshot has no readable \`generated_at\`."
    DETAIL="- **Snapshot:** \`$SNAPSHOT\`"
  else
    age_hours=$(( (now_epoch - generated_epoch) / 3600 ))
    if [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
      PROBLEM="The conformity snapshot is ${age_hours}h old (limit: ${MAX_AGE_HOURS}h)."
      DETAIL="- **Snapshot generated:** $generated_at"
    else
      echo "Conformity feed is fresh: snapshot generated $generated_at (${age_hours}h ago, limit ${MAX_AGE_HOURS}h)."
    fi
  fi
fi

# --- find the open alarm issue, if any -------------------------------------------

find_alarm_issue() {
  # Search without the HTML comment tags — GitHub may not index comments.
  local search_text
  search_text=$(printf '%s' "$MARKER" | sed 's/<!-- //;s/ -->//')
  gh issue list --repo "$REPO" --state open --search "$search_text" \
    --json number --jq '.[0].number' 2>/dev/null || echo ""
}

if [ "$DRY_RUN" = true ]; then
  if [ -n "$PROBLEM" ]; then
    echo "DRY RUN: would raise the conformity alarm on $REPO: $PROBLEM"
    exit 1
  fi
  echo "DRY RUN: feed is healthy; would clear any open alarm on $REPO."
  exit 0
fi

existing=$(find_alarm_issue)
[ "$existing" = "null" ] && existing=""

# --- healthy: clear the alarm -----------------------------------------------------

if [ -z "$PROBLEM" ]; then
  if [ -z "$existing" ]; then
    exit 0
  fi
  gh issue comment "$existing" --repo "$REPO" \
    --body "The conformity feed is producing fresh snapshots again — closing this alarm.

<sub>Automated by \`scripts/conformity-alarm.sh\`.</sub>" > /dev/null 2>&1 \
    || echo "WARN: could not comment on alarm issue #$existing." >&2
  if ! out=$(gh issue close "$existing" --repo "$REPO" 2>&1); then
    echo "ERROR: could not close alarm issue #$existing: $out" >&2
    exit 1
  fi
  echo "Cleared the conformity alarm (closed issue #$existing)."
  exit 0
fi

# --- broken: raise the alarm once -------------------------------------------------

echo "ALARM: $PROBLEM" >&2

if [ -n "$existing" ]; then
  # One open issue is the whole signal. Commenting on every scheduled run
  # would train the reader to mute it, which is how the last month happened.
  echo "Alarm already open as issue #$existing — leaving it alone." >&2
  exit 1
fi

body="## The estate is not being measured

$PROBLEM

$DETAIL

Nothing downstream of the conformity feed is trustworthy while this holds:
\`checks/create-issues.sh\` files no gap issues, and the planned estate
dashboard is reading a frozen picture.

## How to close this

1. Look at the most recent \`Estate Conformity Check\` runs:
   \`gh run list --repo $REPO --workflow conformity.yml\`
2. Fix the cause, then re-run: \`gh workflow run conformity.yml --repo $REPO\`
3. This issue closes itself on the next watchdog run once a fresh snapshot lands.

The snapshot is published by \`scripts/snapshot-publish.sh\` onto the
\`automation/conformity-snapshot\` feed branch, and onto the default branch via
PR when the conformity content changes — see \"Estate conformity feed\" in
\`choices/ci-cd.md\`.

$MARKER"

gh label create "$LABEL" --repo "$REPO" --color "D93F0B" \
  --description "Needs a human decision or human implementation" --force > /dev/null 2>&1 || true

if ! out=$(gh issue create --repo "$REPO" --title "$TITLE" --label "$LABEL" --body "$body" 2>&1); then
  echo "ERROR: could not file the alarm issue: $out" >&2
  exit 1
fi
echo "Raised the conformity alarm: $out" >&2
exit 1
