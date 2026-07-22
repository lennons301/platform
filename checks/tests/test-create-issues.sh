#!/usr/bin/env bash
# Test create-issues.sh dry-run against a fixture snapshot.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

output=$(../create-issues.sh --dry-run --snapshot fixtures/snapshot.json)

assert_eq "plans exactly 2 issues" "2" \
  "$(echo "$output" | grep -c 'DRY RUN: would create issue')"
assert_eq "secrets issue on alpha" "1" \
  "$(echo "$output" | grep -c 'would create issue on example/alpha: \[platform\] alpha: fix secrets conformity')"
assert_eq "versions issue on alpha" "1" \
  "$(echo "$output" | grep -c 'would create issue on example/alpha: \[platform\] alpha: fix versions conformity')"
assert_eq "no issue for divergence" "0" \
  "$(echo "$output" | grep -c 'fix environments conformity')"
assert_eq "repo-less product is skipped with message" "1" \
  "$(echo "$output" | grep -c 'SKIP: beta/secrets (no repo configured)')"
assert_eq "missing snapshot is an error" "1" \
  "$(../create-issues.sh --dry-run --snapshot /nonexistent.json 2>&1 > /dev/null | grep -c 'snapshot not found'; true)"

finish
