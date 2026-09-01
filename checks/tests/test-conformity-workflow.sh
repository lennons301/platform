#!/usr/bin/env bash
# Test the wiring of the conformity workflows. These assertions exist because
# the wiring itself was the bug: a bookkeeping push to a protected branch
# aborted the job before gap-filing, every scheduled run, for a month.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

WF="../../.github/workflows/conformity.yml"
WATCHDOG="../../.github/workflows/conformity-watchdog.yml"

if ! command -v yq > /dev/null 2>&1; then
  echo "  FAIL: yq is required to parse the workflows"
  exit 1
fi

assert_eq "conformity.yml parses" "0" \
  "$(yq '.' "$WF" > /dev/null 2>&1; echo $?)"
assert_eq "conformity-watchdog.yml parses" "0" \
  "$(yq '.' "$WATCHDOG" > /dev/null 2>&1; echo $?)"

steps() { yq -r '.jobs.check.steps[].name // ""' "$WF"; }
step_index() { steps | grep -n "^$1\$" | cut -d: -f1; }
step_if() { yq -r ".jobs.check.steps[] | select(.name == \"$1\") | .if // \"\"" "$WF"; }

# --- the snapshot never goes near the protected branch ---------------------------

assert_eq "no step pushes with bare git" "0" \
  "$(yq -r '.jobs.check.steps[].run // ""' "$WF" | grep -c 'git push')"
assert_eq "the snapshot is published by the tested script" "1" \
  "$(yq -r '.jobs.check.steps[].run // ""' "$WF" | grep -c 'scripts/snapshot-publish.sh')"

# The snapshot PR merging is a push to the default branch, which would re-trigger
# this same workflow. `[skip ci]` guarded the old direct push; it cannot guard a
# merge commit this job does not compose, so the guard lives on the path.
assert_eq "the job ignores its own snapshot echo" "1" \
  "$(yq -r '.on.push.paths-ignore[]' "$WF" | grep -c '^data/\*\*$')"

# --- gap-filing is not collateral damage of the snapshot bookkeeping -------------

GAPS="$(step_index 'Create issues for gaps')"
PUBLISH="$(step_index 'Publish snapshot')"
assert_eq "both steps exist" "1" \
  "$([ -n "$GAPS" ] && [ -n "$PUBLISH" ] && echo 1 || echo 0)"
assert_eq "gap-filing runs before the snapshot is persisted" "1" \
  "$([ "$GAPS" -lt "$PUBLISH" ] && echo 1 || echo 0)"
assert_eq "persisting runs even if gap-filing failed" "1" \
  "$(step_if 'Publish snapshot' | grep -c 'always()')"
assert_eq "persisting is skipped when there is no snapshot to persist" "1" \
  "$(step_if 'Publish snapshot' | grep -c "steps.snapshot.outcome == 'success'")"
assert_eq "gap-filing is skipped when there is no snapshot" "1" \
  "$(step_if 'Create issues for gaps' | grep -c "steps.snapshot.outcome == 'success'")"

# A bare `if:` carries an implicit success(), so any earlier step's failure
# would skip gap-filing — the original bug, at smaller scale.
assert_eq "gap-filing survives a failed bookkeeping step" "1" \
  "$(step_if 'Create issues for gaps' | grep -c 'always()')"

# Nothing that merely records the snapshot may sit between the checks and
# gap-filing, whatever its guard says.
ARTIFACT="$(step_index 'Upload snapshot artifact')"
assert_eq "gap-filing precedes every persistence step" "1" \
  "$([ "$GAPS" -lt "$ARTIFACT" ] && [ "$GAPS" -lt "$PUBLISH" ] && echo 1 || echo 0)"

# A persist failure must still turn the run red — no continue-on-error escape.
assert_eq "a persist failure fails the run" "false" \
  "$(yq -r '.jobs.check.steps[] | select(.name == "Publish snapshot") | .continue-on-error // false' "$WF")"

# --- a failed run says so out loud ------------------------------------------------

assert_eq "a failed run raises the alarm" "1" \
  "$(step_if 'Raise the feed alarm' | grep -c 'failure()')"
assert_eq "the alarm step calls the tested script" "1" \
  "$(yq -r '.jobs.check.steps[] | select(.name == "Raise the feed alarm") | .run' "$WF" | grep -c 'scripts/conformity-alarm.sh')"
# Exit 1 is "alarm raised" and expected in an already-red run; exit 2 is the
# alarm failing to file, which must not be swallowed.
assert_eq "the alarm step tolerates exit 1 only" "1" \
  "$(yq -r '.jobs.check.steps[] | select(.name == "Raise the feed alarm") | .run' "$WF" | grep -c '\[ "$?" -eq 1 \]')"

# --- permissions match what the steps actually do ---------------------------------

assert_eq "feed branch push is permitted" "write" "$(yq -r '.permissions.contents' "$WF")"
assert_eq "snapshot PR is permitted" "write" "$(yq -r '.permissions.pull-requests' "$WF")"
assert_eq "alarm issue is permitted" "write" "$(yq -r '.permissions.issues' "$WF")"

# --- the watchdog is independent of the job it watches ----------------------------

assert_eq "watchdog is scheduled" "1" \
  "$(yq -r '.on.schedule | length' "$WATCHDOG")"
assert_eq "watchdog runs the alarm script" "1" \
  "$(yq -r '.jobs.watchdog.steps[].run // ""' "$WATCHDOG" | grep -c 'scripts/conformity-alarm.sh')"
assert_eq "watchdog reads the feed branch, not just the committed copy" "1" \
  "$(yq -r '.jobs.watchdog.steps[] | select(.env.FEED_BRANCH) | .env.FEED_BRANCH' "$WATCHDOG" | grep -c 'automation/conformity-snapshot')"
assert_eq "watchdog may file issues" "write" "$(yq -r '.permissions.issues' "$WATCHDOG")"

finish
