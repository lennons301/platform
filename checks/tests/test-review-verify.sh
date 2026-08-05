#!/usr/bin/env bash
# Test scripts/review-verify-lib.sh: the runner's post-review check that the
# review pass's claimed verdict actually landed on the PR as a review by the
# reviewer identity. gh is stubbed; no network.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
# No sleeping in tests; the retry itself is exercised explicitly below.
export REVIEW_VERIFY_SLEEP=0
source ../../scripts/review-verify-lib.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- fake gh -----------------------------------------------------------------
# GH_STUB_PR_JSON is the body `gh pr view --json reviewDecision,latestReviews`
# returns; GH_STUB_FAIL=yes makes every read fail the way a dead token does.
# The _FIRST variants answer only the first call, so retry behaviour (a review
# that reads stale for a moment) is testable. Every call is counted.
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/gh" <<'MOCK'
#!/usr/bin/env bash
N=$(( $(cat "$GH_STUB_COUNT" 2>/dev/null || echo 0) + 1 ))
echo "$N" > "$GH_STUB_COUNT"
[ "${GH_STUB_FAIL:-}" = "yes" ] && { echo "gh: could not read PR (HTTP 401)" >&2; exit 1; }
if [ "$N" = "1" ]; then
  [ "${GH_STUB_FAIL_FIRST:-}" = "yes" ] && { echo "gh: upstream timeout (HTTP 502)" >&2; exit 1; }
  [ -n "${GH_STUB_PR_JSON_FIRST:-}" ] && { printf '%s' "$GH_STUB_PR_JSON_FIRST"; exit 0; }
fi
printf '%s' "${GH_STUB_PR_JSON:-}"
MOCK
chmod +x "$TMPDIR/bin/gh"
export PATH="$TMPDIR/bin:$PATH"
export GH_STUB_COUNT="$TMPDIR/gh-calls"
gh_calls() { cat "$GH_STUB_COUNT" 2>/dev/null || echo 0; }

REVIEWER="lennons301-reviewer"

# A PR whose only review is $1 (state) by $2 (login), with reviewDecision $3.
pr_json() {
  printf '{"reviewDecision":"%s","latestReviews":[{"author":{"login":"%s"},"state":"%s"}]}' \
    "$3" "$2" "$1"
}
NO_REVIEWS='{"reviewDecision":"REVIEW_REQUIRED","latestReviews":[]}'

# log <text...> -> path to a pass-output log containing those lines
log() {
  local path="$TMPDIR/pass-$RANDOM.log"
  printf '%s\n' "$@" > "$path"
  printf '%s' "$path"
}

# verify <pr-json> <log-path> -> combined output; sets STATUS
verify() {
  : > "$GH_STUB_COUNT"
  OUTPUT=$(GH_STUB_PR_JSON="$1" verify_review_landed 99 "$REVIEWER" "$2" 2>&1)
  STATUS=$?
}

# --- verdict parsing ----------------------------------------------------------

assert_eq "plain verdict line" "approve" \
  "$(claimed_review_verdict "$(log 'VERDICT: approve')")"
assert_eq "markdown around the marker" "approve" \
  "$(claimed_review_verdict "$(log '**VERDICT:** `approve`')")"
assert_eq "trailing reasoning on the line" "approve" \
  "$(claimed_review_verdict "$(log 'VERDICT: approve — the work matches the ticket.')")"
assert_eq "request-changes" "request-changes" \
  "$(claimed_review_verdict "$(log 'VERDICT: request-changes')")"
assert_eq "two-word request changes" "request-changes" \
  "$(claimed_review_verdict "$(log 'Verdict: request changes')")"
assert_eq "comment-type verdict" "comment" \
  "$(claimed_review_verdict "$(log 'VERDICT: comment (recommend human sign-off)')")"
assert_eq "human sign-off phrasing is a comment verdict" "comment" \
  "$(claimed_review_verdict "$(log 'VERDICT: human sign-off recommended')")"
assert_eq "escalate" "escalate" \
  "$(claimed_review_verdict "$(log 'VERDICT: escalate')")"
assert_eq "the last verdict line wins" "request-changes" \
  "$(claimed_review_verdict "$(log 'The vocabulary is VERDICT: approve | request-changes' \
                                   'Reviewing now...' 'VERDICT: request-changes')")"

claimed_review_verdict "$(log 'I approve this PR.')" > /dev/null
assert_eq "prose with no VERDICT marker is not a verdict" "1" "$?"
claimed_review_verdict "$(log 'VERDICT: looks-good-to-me')" > /dev/null
assert_eq "an unrecognised verdict word is not a verdict" "1" "$?"
claimed_review_verdict "$TMPDIR/does-not-exist.log" > /dev/null
assert_eq "a missing log is not a verdict" "1" "$?"

# --- the failure this exists for: claimed approval, nothing submitted ---------

verify "$NO_REVIEWS" "$(log 'VERDICT: approve' 'My approval satisfies branch protection.')"
assert_eq "claimed approve + no review on GitHub fails" "1" "$STATUS"
assert_eq "names what the pass claimed" "1" "$(echo "$OUTPUT" | grep -c "pass claimed:  approve")"
assert_eq "names what GitHub shows" "1" \
  "$(echo "$OUTPUT" | grep -c "no review by $REVIEWER at all")"
assert_eq "reports the reviewDecision GitHub has" "1" \
  "$(echo "$OUTPUT" | grep -c "REVIEW_REQUIRED")"

verify "$(pr_json COMMENTED "$REVIEWER" REVIEW_REQUIRED)" "$(log 'VERDICT: approve')"
assert_eq "claimed approve + only a comment-type review fails" "1" "$STATUS"
assert_eq "names the state GitHub actually has" "1" \
  "$(echo "$OUTPUT" | grep -c "GitHub shows:  $REVIEWER COMMENTED")"

verify "$(pr_json APPROVED someone-else APPROVED)" "$(log 'VERDICT: approve')"
assert_eq "an approval by another identity does not count" "1" "$STATUS"

verify "$(pr_json APPROVED "$REVIEWER" APPROVED)" "$(log 'VERDICT: request-changes')"
assert_eq "claimed request-changes + an approval fails" "1" "$STATUS"

verify "$(pr_json APPROVED "$REVIEWER" APPROVED)" "$(log 'VERDICT: escalate')"
assert_eq "an escalation that approved anyway fails" "1" "$STATUS"
assert_eq "explains the escalation contradiction" "1" \
  "$(echo "$OUTPUT" | grep -c "claimed 'escalate'")"

# --- verdicts that did land ---------------------------------------------------

verify "$(pr_json APPROVED "$REVIEWER" APPROVED)" "$(log 'VERDICT: approve')"
assert_eq "claimed approve + APPROVED by the reviewer passes" "0" "$STATUS"
assert_eq "reports the verified side effect" "1" \
  "$(echo "$OUTPUT" | grep -c "Verified: review pass claimed 'approve'")"

verify "$(pr_json APPROVED "LENNONS301-Reviewer" APPROVED)" "$(log 'VERDICT: approve')"
assert_eq "login comparison is case-insensitive" "0" "$STATUS"

verify "$(pr_json CHANGES_REQUESTED "$REVIEWER" CHANGES_REQUESTED)" \
  "$(log 'VERDICT: request-changes')"
assert_eq "claimed request-changes + CHANGES_REQUESTED passes" "0" "$STATUS"

verify "$(pr_json COMMENTED "$REVIEWER" REVIEW_REQUIRED)" "$(log 'VERDICT: comment')"
assert_eq "claimed comment + COMMENTED passes" "0" "$STATUS"

verify "$NO_REVIEWS" "$(log 'VERDICT: escalate')"
assert_eq "an escalation with no review submitted passes" "0" "$STATUS"

# An approval that landed while another reviewer requested changes is still the
# pass's verdict having landed — reviewDecision belongs to the PR, not the pass.
verify '{"reviewDecision":"CHANGES_REQUESTED","latestReviews":[
          {"author":{"login":"lennons301-reviewer"},"state":"APPROVED"},
          {"author":{"login":"a-human"},"state":"CHANGES_REQUESTED"}]}' \
  "$(log 'VERDICT: approve')"
assert_eq "the reviewer's own review is what is checked, not reviewDecision" "0" "$STATUS"

# --- unverifiable is a failure, distinctly ------------------------------------

verify "$(pr_json APPROVED "$REVIEWER" APPROVED)" "$(log 'The PR looks good to me.')"
assert_eq "no machine-readable verdict is unverifiable (exit 2)" "2" "$STATUS"
assert_eq "says why it could not be verified" "1" \
  "$(echo "$OUTPUT" | grep -c "no machine-readable")"

: > "$GH_STUB_COUNT"
OUTPUT=$(GH_STUB_FAIL=yes verify_review_landed 99 "$REVIEWER" \
  "$(log 'VERDICT: approve')" 2>&1)
assert_eq "a failed API read is unverifiable, not a pass (exit 2)" "2" "$?"
assert_eq "says the claim stays unverified" "1" \
  "$(echo "$OUTPUT" | grep -c "stays unverified")"

# --- retries: a review that reads stale for a moment is not a phantom --------

APPROVED_JSON="$(pr_json APPROVED "$REVIEWER" APPROVED)"

: > "$GH_STUB_COUNT"
GH_STUB_PR_JSON_FIRST="$NO_REVIEWS" GH_STUB_PR_JSON="$APPROVED_JSON" \
  verify_review_landed 99 "$REVIEWER" "$(log 'VERDICT: approve')" > /dev/null 2>&1
assert_eq "an approval that reads stale on the first look still verifies" "0" "$?"
assert_eq "and it took a second read to see it" "2" "$(gh_calls)"

: > "$GH_STUB_COUNT"
GH_STUB_FAIL_FIRST=yes GH_STUB_PR_JSON="$APPROVED_JSON" \
  verify_review_landed 99 "$REVIEWER" "$(log 'VERDICT: approve')" > /dev/null 2>&1
assert_eq "a transient read failure is retried, not fatal" "0" "$?"

: > "$GH_STUB_COUNT"
GH_STUB_PR_JSON="$NO_REVIEWS" verify_review_landed 99 "$REVIEWER" \
  "$(log 'VERDICT: approve')" > /dev/null 2>&1
assert_eq "a genuinely missing review still fails after the retries" "1" "$?"
assert_eq "having looked REVIEW_VERIFY_ATTEMPTS times" "$REVIEW_VERIFY_ATTEMPTS" "$(gh_calls)"

REVIEW_VERIFY_ATTEMPTS=1
: > "$GH_STUB_COUNT"
GH_STUB_PR_JSON="$NO_REVIEWS" verify_review_landed 99 "$REVIEWER" \
  "$(log 'VERDICT: approve')" > /dev/null 2>&1
assert_eq "REVIEW_VERIFY_ATTEMPTS=1 fails on the first look" "1" "$?"
assert_eq "and reads GitHub exactly once" "1" "$(gh_calls)"
REVIEW_VERIFY_ATTEMPTS=3

finish
