#!/usr/bin/env bash
# Test scripts/milestone-autoclose.sh: milestone state + open-issue count ->
# close / no-op / opt-out, against a stubbed `gh`.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

SCRIPT="$PWD/../../scripts/milestone-autoclose.sh"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

# Stub `gh`: records every invocation, answers reads from $GH_STUB_MILESTONE.
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_CALLS"
if [ -n "${GH_STUB_FAIL:-}" ]; then
  echo "HTTP 404: Not Found" >&2
  exit 1
fi
case "$*" in
  *"-X PATCH"*) echo '{}' ;;
  "api repos/"*) printf '%s' "$GH_STUB_MILESTONE" ;;
esac
exit 0
EOF
chmod +x "$STUB_DIR/gh"
export PATH="$STUB_DIR:$PATH"
export GH_STUB_CALLS="$STUB_DIR/calls.log"

# run <milestone-json> [args...] -> stdout+stderr; resets the call log first.
run() {
  local json="$1"; shift
  : > "$GH_STUB_CALLS"
  GH_STUB_MILESTONE="$json" "$SCRIPT" --repo example/alpha --milestone 7 "$@" 2>&1
}

patch_calls() { grep -c -- "-X PATCH" "$GH_STUB_CALLS"; }
comment_calls() { grep -c "^issue comment" "$GH_STUB_CALLS"; }

OPEN_EMPTY='{"state":"open","title":"Game page redesign","description":"","open_issues":0}'
OPEN_REMAINING='{"state":"open","title":"Game page redesign","description":"","open_issues":2}'
ALREADY_CLOSED='{"state":"closed","title":"Game page redesign","description":"","open_issues":0}'
OPTED_OUT='{"state":"open","title":"Rolling","description":"Ongoing [no-autoclose]","open_issues":0}'

# --- the last open issue closed: close the milestone --------------------------

out=$(run "$OPEN_EMPTY")
assert_eq "closing the last issue closes the milestone (exit 0)" "0" "$?"
assert_eq "one PATCH issued" "1" "$(patch_calls)"
assert_eq "PATCH sets state=closed on the right milestone" "1" \
  "$(grep -c -- 'api -X PATCH repos/example/alpha/milestones/7 -f state=closed' "$GH_STUB_CALLS")"
assert_eq "reports the closure" "1" "$(echo "$out" | grep -c 'Closed milestone #7 (Game page redesign)')"
assert_eq "no comment unless asked" "0" "$(comment_calls)"

# --- no-op while open issues remain -------------------------------------------

out=$(run "$OPEN_REMAINING")
assert_eq "open issues remaining is a no-op (exit 0)" "0" "$?"
assert_eq "no PATCH when issues remain" "0" "$(patch_calls)"
assert_eq "reports the remaining count" "1" "$(echo "$out" | grep -c 'still has 2 open issue(s)')"

# --- idempotent on an already-closed milestone --------------------------------

out=$(run "$ALREADY_CLOSED")
assert_eq "already-closed milestone is a no-op (exit 0)" "0" "$?"
assert_eq "no PATCH when already closed" "0" "$(patch_calls)"
assert_eq "reports it was already closed" "1" "$(echo "$out" | grep -c 'is already closed')"

# --- opt-out guard -------------------------------------------------------------

out=$(run "$OPTED_OUT")
assert_eq "opt-out marker leaves the milestone open (exit 0)" "0" "$?"
assert_eq "no PATCH when opted out" "0" "$(patch_calls)"
assert_eq "reports the opt-out" "1" "$(echo "$out" | grep -c 'opts out')"

run "$OPTED_OUT" --opt-out-marker "[hands off]" > /dev/null
assert_eq "a different marker does not match the default text" "1" "$(patch_calls)"

# --- dry run -------------------------------------------------------------------

out=$(run "$OPEN_EMPTY" --dry-run)
assert_eq "dry run exits 0" "0" "$?"
assert_eq "dry run issues no PATCH" "0" "$(patch_calls)"
assert_eq "dry run reports the intent" "1" "$(echo "$out" | grep -c 'DRY RUN: would close milestone #7')"

# --- optional comment on the closing issue ------------------------------------

run "$OPEN_EMPTY" --comment-issue 136 > /dev/null
assert_eq "comments on the closing issue when asked" "1" "$(comment_calls)"
assert_eq "comment targets the right issue and repo" "1" \
  "$(grep -c '^issue comment 136 --repo example/alpha' "$GH_STUB_CALLS")"

run "$OPEN_REMAINING" --comment-issue 136 > /dev/null
assert_eq "no comment when the milestone was not closed" "0" "$(comment_calls)"

# --- errors --------------------------------------------------------------------

out=$(GH_STUB_FAIL=1 run "$OPEN_EMPTY")
assert_eq "unreadable milestone is an error (exit 1)" "1" "$?"
assert_eq "error names the milestone" "1" "$(echo "$out" | grep -c 'could not read milestone 7 of example/alpha')"

out=$("$SCRIPT" --repo example/alpha 2>&1)
assert_eq "missing --milestone is an error (exit 1)" "1" "$?"
assert_eq "usage names the required flags" "1" "$(echo "$out" | grep -c -- '--repo and --milestone are required')"

out=$("$SCRIPT" --repo example/alpha --milestone 7 --bogus 2>&1)
assert_eq "unknown argument is an error (exit 1)" "1" "$?"

finish
