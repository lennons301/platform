#!/usr/bin/env bash
# Shared test helpers. Source from test scripts:
#   source "$(dirname "$0")/helpers.sh"
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
