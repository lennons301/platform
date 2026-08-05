#!/usr/bin/env bash
# review-verify-lib.sh — did the review pass actually submit its verdict?
# Source this file:
#   source "$(dirname "$0")/review-verify-lib.sh"
#
# The review pass narrates its verdict; GitHub records what it submitted. Those
# two drifted live (interlude PR #99, 2026-08-05: a complete `VERDICT: approve`
# with reasoning, `reviews: []` / `reviewDecision: REVIEW_REQUIRED` on GitHub,
# runner exit 0 "success"). Same shape as the capability-contract failures in
# choices/ai-dev-workflow.md: the pass's claims outran its side effects, and the
# runner echoed the claim as fact.
#
# So the runner verifies before it reports: read the claimed verdict out of the
# pass's own output, read the reviewer's actual review off the PR, and require
# them to agree. A pass that says nothing machine-readable is unverifiable, and
# unverifiable is a failure — never a pass.

set -uo pipefail
# NOTE: no set -e — callers branch on exit codes (see below).

# How hard to look before calling a claimed review missing (env-overridable so
# tests don't sleep): GitHub reads review data back through GraphQL, so a review
# submitted seconds ago can read stale for a moment.
REVIEW_VERIFY_ATTEMPTS="${REVIEW_VERIFY_ATTEMPTS:-3}"
REVIEW_VERIFY_SLEEP="${REVIEW_VERIFY_SLEEP:-3}"

# claimed_review_verdict <log-file>
#   stdout: the normalised verdict — approve | request-changes | comment | escalate
#   exit:   0 = found, 1 = no recognisable verdict in the log
# The LAST `VERDICT: <word>` line wins: the pass relays the reviewer's verdict
# at the end, after any quoting of the agent definition's own vocabulary.
claimed_review_verdict() {
  local log="$1"
  [ -f "$log" ] || return 1

  local line word rest
  # Tolerate markdown around the marker: **VERDICT:** `approve`, ## VERDICT: …
  line="$(grep -iE 'verdict[^a-z0-9]{0,4}:' "$log" | tail -1 || true)"
  [ -n "$line" ] || return 1

  # Lowercase, drop markdown punctuation, keep the first word after the colon.
  line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' | tr -d '*`_"#')"
  word="${line#*verdict}"
  word="${word#*:}"
  read -r word rest <<< "$word" || true
  word="${word%%[!a-z0-9-]*}"   # trailing punctuation: "approve." -> "approve"

  # Single-token match, so two-word phrasings ("request changes", "human
  # sign-off") reduce to their first word rather than failing to parse.
  case "$word" in
    approve|approved|approval)                          printf 'approve' ;;
    request|request-changes|requesting|changes|changes-requested)
                                                        printf 'request-changes' ;;
    comment|commented|comment-only|human|human-signoff|recommend)
                                                        printf 'comment' ;;
    escalate|escalated|escalation)                      printf 'escalate' ;;
    *) return 1 ;;
  esac
}

# reviewer_review_state <pr> <reviewer-login>
#   stdout: the reviewer's own latest review state on the PR (APPROVED,
#           CHANGES_REQUESTED, COMMENTED, …), or "" if they never reviewed;
#           a TAB then the PR's overall reviewDecision follows.
#   exit:   0 = read, 2 = the API read itself failed (never "no review")
# Logins are compared case-insensitively — GitHub treats them that way.
reviewer_review_state() {
  local pr="$1" login="$2" json
  json="$(gh pr view "$pr" --json reviewDecision,latestReviews 2>/dev/null)" || return 2
  [ -n "$json" ] || return 2
  printf '%s' "$json" | jq -r --arg login "$login" '
    ([.latestReviews[]? | select((.author.login // "" | ascii_downcase)
                                 == ($login | ascii_downcase))] | last | .state // "")
    + "\t" + (.reviewDecision // "")' 2>/dev/null || return 2
}

# expected_review_state <verdict>
#   stdout: the review state that verdict must have produced on GitHub
#           ("" for escalate — it submits a PR comment, not a review)
expected_review_state() {
  case "$1" in
    approve)         printf 'APPROVED' ;;
    request-changes) printf 'CHANGES_REQUESTED' ;;
    comment)         printf 'COMMENTED' ;;
    escalate)        printf '' ;;
  esac
}

# verify_review_landed <pr> <reviewer-login> <log-file>
#   Diagnosis on stdout (mismatch detail on stderr).
#   exit: 0 = the claimed verdict is on the PR as a review by <reviewer-login>
#         1 = mismatch — claim and GitHub disagree
#         2 = unverifiable — no machine-readable verdict, or the API read failed
verify_review_landed() {
  local pr="$1" login="$2" log="$3"

  local verdict
  if ! verdict="$(claimed_review_verdict "$log")"; then
    echo "ERROR: the review pass emitted no machine-readable 'VERDICT: <approve|request-changes|comment|escalate>' line," >&2
    echo "       so what it did to PR #$pr cannot be verified. Treating an unverifiable review as a failure." >&2
    return 2
  fi

  local want
  want="$(expected_review_state "$verdict")"

  # A mismatch is retried a couple of times: GitHub's review data is read back
  # through GraphQL, so a review submitted seconds ago can briefly read stale,
  # and failing a real approval is as wrong as passing a phantom one. Only the
  # verdicts that expect a review retry — an escalation that approved anyway
  # cannot improve with time.
  local try state="" decision="" read_out
  for (( try = 1; try <= REVIEW_VERIFY_ATTEMPTS; try++ )); do
    if read_out="$(reviewer_review_state "$pr" "$login")"; then
      state="${read_out%%$'\t'*}"
      decision="${read_out#*$'\t'}"

      # Escalation submits a PR comment rather than a review; the one thing it
      # must never have done is approve.
      if [ "$verdict" = "escalate" ]; then
        if [ "$state" = "APPROVED" ]; then
          echo "ERROR: the review pass claimed 'escalate' on PR #$pr, but GitHub shows $login APPROVED it." >&2
          return 1
        fi
        echo "Verified: review pass escalated PR #$pr; no approval by $login (review state: ${state:-none}, reviewDecision: ${decision:-none})."
        return 0
      fi

      if [ "$state" = "$want" ]; then
        echo "Verified: review pass claimed '$verdict' and GitHub shows $login $state on PR #$pr (reviewDecision: ${decision:-none})."
        return 0
      fi
    elif [ "$try" -eq "$REVIEW_VERIFY_ATTEMPTS" ]; then
      echo "ERROR: could not read reviews on PR #$pr (gh pr view --json reviewDecision,latestReviews failed)." >&2
      echo "       The review pass claimed '$verdict'; that claim stays unverified." >&2
      return 2
    fi
    if [ "$try" -lt "$REVIEW_VERIFY_ATTEMPTS" ]; then sleep "$REVIEW_VERIFY_SLEEP"; fi
  done

  echo "ERROR: review pass claim and GitHub disagree on PR #$pr — the pass's narration is not evidence." >&2
  echo "       pass claimed:  $verdict (expected a $want review by $login)" >&2
  if [ -z "$state" ]; then
    echo "       GitHub shows:  no review by $login at all (reviewDecision: ${decision:-none})" >&2
  else
    echo "       GitHub shows:  $login $state (reviewDecision: ${decision:-none})" >&2
  fi
  return 1
}
