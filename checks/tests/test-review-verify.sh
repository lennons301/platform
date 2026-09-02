#!/usr/bin/env bash
# Test scripts/review-verify-lib.sh: the runner's post-pass checks that a pass's
# side effect actually landed — the claimed verdict as a review by the reviewer
# identity on the PR, and, for workflow:research tickets, the finding and the
# verdict as comments on the issue. gh is stubbed; no network.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
# No sleeping in tests; the retry itself is exercised explicitly below.
export REVIEW_VERIFY_SLEEP=0
source ../../scripts/review-verify-lib.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- fake gh -----------------------------------------------------------------
# GH_STUB_PR_JSON is the body `gh pr view --json reviewDecision,latestReviews`
# returns, GH_STUB_ISSUE_JSON the body `gh issue view --comments --json comments`
# returns (the stub routes on the `pr`/`issue` subcommand); GH_STUB_FAIL=yes
# makes every read fail the way a dead token does. The _FIRST variants answer
# only the first call, so retry behaviour (a review that reads stale for a
# moment) is testable. Every call is counted.
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/gh" <<'MOCK'
#!/usr/bin/env bash
N=$(( $(cat "$GH_STUB_COUNT" 2>/dev/null || echo 0) + 1 ))
echo "$N" > "$GH_STUB_COUNT"
[ "${GH_STUB_FAIL:-}" = "yes" ] && { echo "gh: could not read (HTTP 401)" >&2; exit 1; }
KIND=pr
[ "${1:-}" = "issue" ] && KIND=issue
if [ "$N" = "1" ]; then
  [ "${GH_STUB_FAIL_FIRST:-}" = "yes" ] && { echo "gh: upstream timeout (HTTP 502)" >&2; exit 1; }
  if [ "$KIND" = "issue" ]; then
    [ -n "${GH_STUB_ISSUE_JSON_FIRST:-}" ] && { printf '%s' "$GH_STUB_ISSUE_JSON_FIRST"; exit 0; }
  else
    [ -n "${GH_STUB_PR_JSON_FIRST:-}" ] && { printf '%s' "$GH_STUB_PR_JSON_FIRST"; exit 0; }
  fi
fi
[ "$KIND" = "issue" ] && { printf '%s' "${GH_STUB_ISSUE_JSON:-}"; exit 0; }
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
# shellcheck disable=SC2016  # the backticks are literal markdown in the fixture log line
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

# --- research tickets: the finding and its review live on the issue -----------
# Same anti-drift guarantee, one object over: the reviewer posts its verdict as
# an issue comment, and the runner reads it back off the issue.

# issue_json <login>:<body> ... -> the body `gh issue view --comments --json
# comments` returns, comments oldest first.
issue_json() {
  local spec out=""
  for spec in "$@"; do
    out+="${out:+,}$(jq -nc --arg login "${spec%%:*}" --arg body "${spec#*:}" \
      '{author: {login: $login}, body: $body}')"
  done
  printf '{"comments":[%s]}' "$out"
}

IMPLEMENTER="lennons301"
FINDING="Finding: stream-json input does not expand slash commands."

APPROVED_THREAD="$(issue_json "$IMPLEMENTER:🤖 Attempt 1/3 starting." \
                              "$IMPLEMENTER:$FINDING" \
                              "$REVIEWER:Checked the sources cited.
VERDICT: approve")"
NO_VERDICT_THREAD="$(issue_json "$IMPLEMENTER:🤖 Attempt 1/3 starting." \
                                "$IMPLEMENTER:$FINDING")"

# --- whose verdict, and which one ---------------------------------------------

assert_eq "the reviewer's verdict comment is found" "approve" \
  "$(GH_STUB_ISSUE_JSON="$APPROVED_THREAD" reviewer_issue_verdict 59 "$REVIEWER")"
assert_eq "no reviewer comment means no verdict" "" \
  "$(GH_STUB_ISSUE_JSON="$NO_VERDICT_THREAD" reviewer_issue_verdict 59 "$REVIEWER")"
assert_eq "a verdict by another author does not count" "" \
  "$(GH_STUB_ISSUE_JSON="$(issue_json "$IMPLEMENTER:VERDICT: approve")" \
     reviewer_issue_verdict 59 "$REVIEWER")"
assert_eq "the reviewer's latest verdict wins over an earlier run's" "approve" \
  "$(GH_STUB_ISSUE_JSON="$(issue_json "$REVIEWER:VERDICT: request-changes" \
                                      "$IMPLEMENTER:$FINDING (revised)" \
                                      "$REVIEWER:VERDICT: approve")" \
     reviewer_issue_verdict 59 "$REVIEWER")"
assert_eq "a reviewer comment with no verdict line reads as none" "" \
  "$(GH_STUB_ISSUE_JSON="$(issue_json "$REVIEWER:Reading the thread now.")" \
     reviewer_issue_verdict 59 "$REVIEWER")"
assert_eq "issue-thread login comparison is case-insensitive" "approve" \
  "$(GH_STUB_ISSUE_JSON="$(issue_json "LENNONS301-Reviewer:VERDICT: approve")" \
     reviewer_issue_verdict 59 "$REVIEWER")"

# verify_issue <issue-json> <log-path> -> combined output; sets STATUS
verify_issue() {
  : > "$GH_STUB_COUNT"
  OUTPUT=$(GH_STUB_ISSUE_JSON="$1" verify_issue_verdict_landed 59 "$REVIEWER" "$2" 2>&1)
  STATUS=$?
}

verify_issue "$APPROVED_THREAD" "$(log 'VERDICT: approve')"
assert_eq "claimed approve + a matching verdict comment passes" "0" "$STATUS"
assert_eq "reports the verified side effect" "1" \
  "$(echo "$OUTPUT" | grep -c "posted a matching verdict comment on issue #59")"

verify_issue "$NO_VERDICT_THREAD" "$(log 'VERDICT: approve' 'Posted my verdict on the issue.')"
assert_eq "claimed approve + nothing posted fails" "1" "$STATUS"
assert_eq "names what GitHub shows" "1" \
  "$(echo "$OUTPUT" | grep -c "no verdict comment by $REVIEWER")"

verify_issue "$(issue_json "$REVIEWER:VERDICT: request-changes")" "$(log 'VERDICT: approve')"
assert_eq "claimed approve + a request-changes comment fails" "1" "$STATUS"
assert_eq "names the verdict actually posted" "1" \
  "$(echo "$OUTPUT" | grep -c "posted 'request-changes'")"

verify_issue "$(issue_json "$REVIEWER:VERDICT: escalate")" "$(log 'VERDICT: escalate')"
assert_eq "claimed escalate + an escalation comment passes" "0" "$STATUS"

verify_issue "$(issue_json "$REVIEWER:VERDICT: approve")" "$(log 'VERDICT: escalate')"
assert_eq "claimed escalate + an approval comment fails" "1" "$STATUS"

verify_issue "$APPROVED_THREAD" "$(log 'The finding answers the question.')"
assert_eq "no machine-readable verdict is unverifiable (exit 2)" "2" "$STATUS"

: > "$GH_STUB_COUNT"
OUTPUT=$(GH_STUB_FAIL=yes verify_issue_verdict_landed 59 "$REVIEWER" \
  "$(log 'VERDICT: approve')" 2>&1)
assert_eq "a failed issue read is unverifiable, not a pass (exit 2)" "2" "$?"
assert_eq "says the claim stays unverified" "1" \
  "$(echo "$OUTPUT" | grep -c "stays unverified")"

: > "$GH_STUB_COUNT"
GH_STUB_ISSUE_JSON_FIRST="$NO_VERDICT_THREAD" GH_STUB_ISSUE_JSON="$APPROVED_THREAD" \
  verify_issue_verdict_landed 59 "$REVIEWER" "$(log 'VERDICT: approve')" > /dev/null 2>&1
assert_eq "a comment that reads stale on the first look still verifies" "0" "$?"
assert_eq "and it took a second read to see it" "2" "$(gh_calls)"

# --- the finding itself: the research analogue of "no PR after the pass" ------

assert_eq "runner markers are not findings" "0" \
  "$(GH_STUB_ISSUE_JSON="$(issue_json "$IMPLEMENTER:🤖 Attempt 1/3 starting." \
                                      "$IMPLEMENTER:🔧 Repair pass starting.")" \
     issue_finding_count 59)"
assert_eq "comments that are not markers are findings" "2" \
  "$(GH_STUB_ISSUE_JSON="$APPROVED_THREAD" issue_finding_count 59)"

: > "$GH_STUB_COUNT"
OUTPUT=$(GH_STUB_ISSUE_JSON="$NO_VERDICT_THREAD" verify_finding_landed 59 0 2>&1)
assert_eq "a finding posted where there was none passes" "0" "$?"
assert_eq "reports what landed" "1" "$(echo "$OUTPUT" | grep -c "recorded 1 new comment")"

: > "$GH_STUB_COUNT"
OUTPUT=$(GH_STUB_ISSUE_JSON="$NO_VERDICT_THREAD" verify_finding_landed 59 1 2>&1)
assert_eq "a pass that added nothing to the thread fails" "1" "$?"
assert_eq "says the deliverable is the comment" "1" \
  "$(echo "$OUTPUT" | grep -c "deliverable IS the comment")"

: > "$GH_STUB_COUNT"
GH_STUB_ISSUE_JSON_FIRST="$(issue_json "$IMPLEMENTER:🤖 Attempt 1/3 starting.")" \
  GH_STUB_ISSUE_JSON="$NO_VERDICT_THREAD" \
  verify_finding_landed 59 0 > /dev/null 2>&1
assert_eq "a finding that reads stale on the first look still verifies" "0" "$?"

: > "$GH_STUB_COUNT"
GH_STUB_FAIL=yes verify_finding_landed 59 0 > /dev/null 2>&1
assert_eq "a failed read is unverifiable, not a missing finding (exit 2)" "2" "$?"

finish
