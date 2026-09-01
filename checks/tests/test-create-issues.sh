#!/usr/bin/env bash
# Test create-issues.sh dry-run against a fixture snapshot.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

# stderr is silenced here: the fixture is deliberately old, and its staleness
# warning has its own assertions below.
output=$(../create-issues.sh --dry-run --snapshot fixtures/snapshot.json 2>/dev/null)

assert_eq "plans exactly 4 issues" "4" \
  "$(echo "$output" | grep -c 'DRY RUN: would create issue')"
assert_eq "secrets issue on alpha" "1" \
  "$(echo "$output" | grep -c 'would create issue on example/alpha \[platform-upgrade\]: \[platform\] alpha: fix secrets conformity')"
assert_eq "versions issue on alpha" "1" \
  "$(echo "$output" | grep -c 'would create issue on example/alpha \[platform-upgrade\]: \[platform\] alpha: fix versions conformity')"

# Gaps needing a human decision route to ready-for-human, which also keeps them
# out of ticket-loop.sh's ready-for-agent auto-pick.
assert_eq "domain-modelling routes to ready-for-human" "1" \
  "$(echo "$output" | grep -c 'would create issue on example/alpha \[ready-for-human\]: \[platform\] alpha: fix domain-modelling conformity')"
assert_eq "domain-modelling is never ready-for-agent" "0" \
  "$(echo "$output" | grep -c 'ready-for-agent')"

# Reviewer onboarding is admin-scoped API work plus a Doppler-held PAT: an agent
# cannot close it, so it must never carry the mechanical platform-upgrade label.
assert_eq "review-gate routes to ready-for-human" "1" \
  "$(echo "$output" | grep -c 'would create issue on example/alpha \[ready-for-human\]: \[platform\] alpha: fix review-gate conformity')"
assert_eq "review-gate is never platform-upgrade" "0" \
  "$(echo "$output" | grep -c 'platform-upgrade\]: \[platform\] alpha: fix review-gate')"
assert_eq "no issue for divergence" "0" \
  "$(echo "$output" | grep -c 'fix environments conformity')"
assert_eq "repo-less product is skipped with message" "1" \
  "$(echo "$output" | grep -c 'SKIP: beta/secrets (no repo configured)')"
assert_eq "missing snapshot is an error" "1" \
  "$(../create-issues.sh --dry-run --snapshot /nonexistent.json 2>&1 > /dev/null | grep -c 'snapshot not found'; true)"

# A stale snapshot describes an estate that has moved on — filing from it
# silently is how a dead feed keeps looking alive.
assert_eq "an old snapshot warns about its age" "1" \
  "$(../create-issues.sh --dry-run --snapshot fixtures/snapshot.json 2>&1 > /dev/null | grep -c 'this snapshot is .*h old')"
assert_eq "a fresh snapshot warns about nothing" "0" \
  "$(SNAPSHOT_STALE_HOURS=999999 ../create-issues.sh --dry-run --snapshot fixtures/snapshot.json 2>&1 > /dev/null | grep -c 'WARNING')"

UNDATED=$(mktemp)
jq 'del(.generated_at)' fixtures/snapshot.json > "$UNDATED"
assert_eq "an undated snapshot warns too" "1" \
  "$(../create-issues.sh --dry-run --snapshot "$UNDATED" 2>&1 > /dev/null | grep -c 'no readable generated_at')"
rm -f "$UNDATED"

finish
