#!/usr/bin/env bash
# Test the wiring of the PR gate. `shell-checks` is the required status check on
# master, so what it runs is the definition of "checked before merge": if the
# suite or the linter silently drops out of this workflow, changes land with
# nothing having run on them — the gap this workflow was added to close.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

WF="../../.github/workflows/pr-checks.yml"

if ! command -v yq > /dev/null 2>&1; then
  echo "  FAIL: yq is required to parse the workflow"
  exit 1
fi

assert_eq "pr-checks.yml parses" "0" \
  "$(yq '.' "$WF" > /dev/null 2>&1; echo $?)"

assert_eq "it triggers on pull_request" "true" \
  "$(yq -r '.on | has("pull_request")' "$WF")"

# The required-check context is the job's name as GitHub reports it. Renaming it
# silently un-gates the branch: protection keeps requiring a context nothing
# reports any more, which GitHub treats as pending — see the header comment in
# the workflow for the setup-reviewer.sh command that (re)applies it.
assert_eq "the gating job is still named shell-checks" "shell-checks" \
  "$(yq -r '.jobs.shell-checks.name' "$WF")"

RUNS="$(yq -r '.jobs.shell-checks.steps[].run // ""' "$WF")"

assert_eq "it runs the shell test suite" "1" \
  "$(echo "$RUNS" | grep -c '^\./checks/tests/run-tests\.sh$')"
# Via scripts/lint.sh, not an inline shellcheck invocation: one definition of
# "lint" for CI and `just lint`.
assert_eq "it lints via scripts/lint.sh" "1" \
  "$(echo "$RUNS" | grep -c '^\./scripts/lint\.sh$')"

# An unpinned linter turns an unrelated PR red the day shellcheck adds a check.
assert_eq "shellcheck is pinned to a release" "1" \
  "$(yq -r '.jobs.shell-checks.env.SHELLCHECK_VERSION // ""' "$WF" \
    | grep -cE '^v[0-9]+\.[0-9]+\.[0-9]+$')"

# The gate is only as wide as the linter's own reach.
assert_eq "lint.sh covers both shell directories" "1" \
  "$(grep -c "^find checks scripts -name '\*\.sh'" ../../scripts/lint.sh)"

finish
