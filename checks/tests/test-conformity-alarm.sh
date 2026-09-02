#!/usr/bin/env bash
# Test scripts/conformity-alarm.sh: snapshot age / run failure -> raise, hold,
# or clear one tracking issue, against a stubbed `gh`.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

SCRIPT="$PWD/../../scripts/conformity-alarm.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stub `gh`: records every invocation, answers `issue list` from $GH_STUB_ISSUE
# (the script runs it with --jq '.[0].number', so a bare number or nothing).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_CALLS"
case "$1 $2" in
  "issue list")
    if [ -n "${GH_STUB_LIST_FAIL:-}" ]; then
      echo "API rate limit exceeded" >&2
      exit 1
    fi
    # The script searches by marker first, then falls back to the exact title.
    case "$*" in
      *"in:title"*) printf '%s' "${GH_STUB_ISSUE_BY_TITLE:-}" ;;
      *) printf '%s' "${GH_STUB_ISSUE:-}" ;;
    esac
    ;;
  "issue create")
    if [ -n "${GH_STUB_CREATE_FAIL:-}" ]; then echo "boom" >&2; exit 1; fi
    echo "https://github.com/example/platform/issues/7"
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_STUB_CALLS="$TMP/calls.log"

SNAP="$TMP/snapshot.json"
snapshot_at() { jq -n --arg at "$1" '{generated_at: $at, total_gaps: 3}' > "$SNAP"; }

# run [args...] -> stdout+stderr; resets the call log first.
run() {
  : > "$GH_STUB_CALLS"
  "$SCRIPT" --repo example/platform --now "2026-09-01T06:00:00Z" "$@" 2>&1
}

creates() { grep -c "^issue create" "$GH_STUB_CALLS"; }
closes()  { grep -c "^issue close" "$GH_STUB_CALLS"; }

# --- fresh snapshot: silence ------------------------------------------------------

snapshot_at "2026-09-01T02:00:00Z"
out=$(run --snapshot "$SNAP")
assert_eq "a fresh snapshot is healthy (exit 0)" "0" "$?"
assert_eq "no issue filed while healthy" "0" "$(creates)"
assert_eq "reports the age" "1" "$(echo "$out" | grep -c '4h ago')"

# The default limit is generous enough for one missed daily run.
snapshot_at "2026-08-31T05:00:00Z"
run --snapshot "$SNAP" > /dev/null
assert_eq "a single missed run is not yet an alarm (exit 0)" "0" "$?"
assert_eq "no issue for a one-day-old snapshot" "0" "$(creates)"

# --- stale snapshot: raise the alarm once -----------------------------------------

snapshot_at "2026-07-31T06:00:00Z"
out=$(run --snapshot "$SNAP")
assert_eq "a month-old snapshot raises the alarm (exit 1)" "1" "$?"
assert_eq "one issue filed" "1" "$(creates)"
assert_eq "issue carries the human label" "1" \
  "$(grep -c -- "issue create --repo example/platform --title \[platform\] Estate conformity feed has stopped updating --label ready-for-human" "$GH_STUB_CALLS")"
assert_eq "alarm names the age" "1" "$(echo "$out" | grep -c '768h old (limit: 48h)')"

out=$(GH_STUB_ISSUE=7 run --snapshot "$SNAP")
assert_eq "an already-open alarm stays raised (exit 1)" "1" "$?"
assert_eq "no duplicate issue" "0" "$(creates)"
assert_eq "no comment spam on the open alarm" "0" "$(grep -c '^issue comment' "$GH_STUB_CALLS")"
assert_eq "says the alarm is already open" "1" "$(echo "$out" | grep -c 'Alarm already open as issue #7')"

# The marker is an HTML comment, which GitHub may or may not index. Missing it
# would file a duplicate alarm every single day.
out=$(GH_STUB_ISSUE_BY_TITLE=9 run --snapshot "$SNAP")
assert_eq "the title fallback still holds the alarm (exit 1)" "1" "$?"
assert_eq "an alarm found only by title is not duplicated" "0" "$(creates)"
assert_eq "names the issue found by title" "1" "$(echo "$out" | grep -c 'Alarm already open as issue #9')"

# A search that failed is not a search that found nothing.
out=$(GH_STUB_LIST_FAIL=1 run --snapshot "$SNAP")
assert_eq "an unanswerable dedupe query is a script error (exit 2)" "2" "$?"
assert_eq "no alarm filed while blind" "0" "$(creates)"
assert_eq "says the search failed" "1" "$(echo "$out" | grep -c 'could not search example/platform for an open alarm')"

# --- the threshold is configurable -------------------------------------------------

snapshot_at "2026-08-31T00:00:00Z"
run --snapshot "$SNAP" --max-age-hours 6 > /dev/null
assert_eq "a tighter limit catches a younger snapshot" "1" "$(creates)"

# --- unusable snapshots are just as broken as stale ones ---------------------------

out=$(run --snapshot "$TMP/absent.json")
assert_eq "a missing snapshot raises the alarm (exit 1)" "1" "$?"
assert_eq "issue filed for the missing snapshot" "1" "$(creates)"
assert_eq "alarm says the snapshot is missing" "1" "$(echo "$out" | grep -c 'No conformity snapshot could be found')"

echo '{"total_gaps": 3}' > "$SNAP"
out=$(run --snapshot "$SNAP")
assert_eq "a snapshot without generated_at raises the alarm (exit 1)" "1" "$?"
assert_eq "alarm says generated_at is unreadable" "1" "$(echo "$out" | grep -c 'no readable .generated_at')"

echo 'not json at all' > "$SNAP"
out=$(run --snapshot "$SNAP")
assert_eq "an unparseable snapshot raises the alarm (exit 1)" "1" "$?"

# --- workflow failure raises the same alarm ---------------------------------------

snapshot_at "2026-09-01T02:00:00Z"
out=$(run --failed-run "https://github.com/example/platform/actions/runs/42")
assert_eq "a failed run raises the alarm even with a fresh snapshot (exit 1)" "1" "$?"
assert_eq "issue filed for the failed run" "1" "$(creates)"
assert_eq "alarm names the workflow" "1" "$(echo "$out" | grep -c 'Estate Conformity Check')"

# --- recovery clears the alarm -----------------------------------------------------

snapshot_at "2026-09-01T02:00:00Z"
out=$(GH_STUB_ISSUE=7 run --snapshot "$SNAP")
assert_eq "a recovered feed exits 0" "0" "$?"
assert_eq "the open alarm is closed" "1" "$(closes)"
assert_eq "closes the right issue" "1" \
  "$(grep -c '^issue close 7 --repo example/platform' "$GH_STUB_CALLS")"
assert_eq "explains the closure in a comment" "1" "$(grep -c '^issue comment 7' "$GH_STUB_CALLS")"
assert_eq "reports the recovery" "1" "$(echo "$out" | grep -c 'Cleared the conformity alarm')"

run --snapshot "$SNAP" > /dev/null
assert_eq "nothing to close when no alarm is open" "0" "$(closes)"

# --- dry run -------------------------------------------------------------------------

snapshot_at "2026-07-31T06:00:00Z"
out=$(run --snapshot "$SNAP" --dry-run)
assert_eq "dry run on a stale feed exits 1" "1" "$?"
assert_eq "dry run files nothing" "0" "$(creates)"
assert_eq "dry run reports the intent" "1" "$(echo "$out" | grep -c 'DRY RUN: would raise')"

# --- errors ---------------------------------------------------------------------------
#
# Exit 2, not 1: "the alarm could not do its job" is a different fact from "the
# alarm is raised", and the conformity job's failure handler tolerates only the
# latter.

out=$("$SCRIPT" --repo example/platform 2>&1)
assert_eq "neither --snapshot nor --failed-run is a script error (exit 2)" "2" "$?"
assert_eq "says which flags are needed" "1" "$(echo "$out" | grep -c -- 'pass --snapshot .* or --failed-run')"

out=$("$SCRIPT" --snapshot "$SNAP" 2>&1)
assert_eq "missing --repo is a script error (exit 2)" "2" "$?"

out=$("$SCRIPT" --repo example/platform --snapshot "$SNAP" --max-age-hours soon 2>&1)
assert_eq "a non-numeric age limit is a script error (exit 2)" "2" "$?"

out=$("$SCRIPT" --repo example/platform --snapshot "$SNAP" --bogus 2>&1)
assert_eq "unknown argument is a script error (exit 2)" "2" "$?"

snapshot_at "2026-07-31T06:00:00Z"
out=$(GH_STUB_CREATE_FAIL=1 run --snapshot "$SNAP")
assert_eq "an unfileable alarm is a script error (exit 2)" "2" "$?"
assert_eq "says the alarm could not be filed" "1" "$(echo "$out" | grep -c 'could not file the alarm issue')"

finish
