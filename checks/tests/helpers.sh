#!/usr/bin/env bash
# Shared test helpers. Source from test scripts:
#   source "$(dirname "$0")/helpers.sh"

# Scripts under test fall back to $GITHUB_REPOSITORY when --repo is omitted, and
# GitHub Actions always sets it — so a test for "no repo given" passed locally
# and failed in CI, the one place the suite has to be trusted. The suite decides
# what a script does with its arguments, never what the runner happens to
# export: unset it so every test sees the same environment.
unset GITHUB_REPOSITORY

FAILURES=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# Call at end of every test script: exit code = failed assertion count.
finish() { exit "$FAILURES"; }
