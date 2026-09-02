#!/usr/bin/env bash
# Test scripts/setup-reviewer.sh's branch-protection payload against a stubbed
# `gh`. A protection PUT replaces the whole object, so every field this script
# does not restate is switched off — and the script's promise is that it only
# ever adds ("required status checks and enforce_admins are preserved"). The
# assertions below are that promise: re-running it on an already-protected repo
# must never come back with less protection than it found.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

SCRIPT="$PWD/../../scripts/setup-reviewer.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A repo for the script to cd into: it insists on a git dir and seeds a gate
# stub inside it.
mkdir -p "$TMP/work"
git -C "$TMP/work" init -q

# Stub `gh`: records every invocation, answers the two reads the payload is
# built from, and captures the body PUT to the protection endpoint.
#   $GH_STUB_PROTECTION — existing protection JSON; empty = no protection (the
#   real `gh api` prints the 404 body to stdout and exits non-zero).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_CALLS"
case "$*" in
  "repo view --json nameWithOwner"*) echo "example/platform" ;;
  "repo view --json defaultBranchRef"*) echo "master" ;;
  *"-X PUT"*protection*) cat > "$GH_STUB_PAYLOAD" ;;
  *collaborators/*) ;;  # already a collaborator: skips the Doppler path
  *protection*)
    if [ -z "${GH_STUB_PROTECTION:-}" ]; then
      echo '{"message":"Branch not protected"}'
      exit 1
    fi
    printf '%s' "$GH_STUB_PROTECTION"
    ;;
  *"-X PATCH"*) echo '{}' ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_STUB_CALLS="$TMP/calls.log"
export GH_STUB_PAYLOAD="$TMP/payload.json"

# run <existing-protection-json> [args...] -> the script's stdout+stderr;
# leaves the PUT body in $GH_STUB_PAYLOAD.
run() {
  local existing="$1"; shift
  : > "$GH_STUB_CALLS"
  : > "$GH_STUB_PAYLOAD"
  GH_STUB_PROTECTION="$existing" "$SCRIPT" --repo-dir "$TMP/work" "$@" 2>&1
}

# sent [jq-flags] <filter> -> that field of the captured PUT body.
sent() { jq -r "$@" "$GH_STUB_PAYLOAD"; }

PROTECTED_NO_CONTEXTS='{
  "required_status_checks": {"strict": true, "contexts": []},
  "enforce_admins": {"enabled": true},
  "required_pull_request_reviews": {"required_approving_review_count": 2}
}'
PROTECTED_WITH_CONTEXTS='{
  "required_status_checks": {"strict": false, "contexts": ["build"]},
  "enforce_admins": {"enabled": false},
  "required_pull_request_reviews": {"required_approving_review_count": 1}
}'

# --- an unprotected branch: ask for nothing, require nothing ---------------------

out=$(run "" )
assert_eq "an unprotected branch is onboarded (exit 0)" "0" "$?"
assert_eq "one protection PUT issued" "1" \
  "$(grep -c -- '-X PUT repos/example/platform/branches/master/protection' "$GH_STUB_CALLS")"
assert_eq "no checks required where there were none" "null" "$(sent '.required_status_checks')"
assert_eq "reports no required checks" "1" \
  "$(echo "$out" | grep -c 'Required status checks: none')"
assert_eq "one approving review required" "1" \
  "$(sent '.required_pull_request_reviews.required_approving_review_count')"
assert_eq "stale approvals dismissed" "true" \
  "$(sent '.required_pull_request_reviews.dismiss_stale_reviews')"

# --- status checks required with an empty context list --------------------------
#
# A reachable configuration — the GitHub UI enables "require branches to be up
# to date before merging" with nothing selected. Gating the block on the context
# count would send `null` here and turn that toggle off behind the operator's
# back on a re-run that was asked to change nothing.

run "$PROTECTED_NO_CONTEXTS" > /dev/null
assert_eq "an empty-context requirement survives a re-run" "true" \
  "$(sent '.required_status_checks.strict')"
assert_eq "and it stays empty rather than disappearing" "[]" \
  "$(sent -c '.required_status_checks.contexts')"
assert_eq "enforce_admins is preserved" "true" "$(sent '.enforce_admins')"
assert_eq "a stricter approval count is not lowered" "2" \
  "$(sent '.required_pull_request_reviews.required_approving_review_count')"

# --- --require-check adds to the existing contexts ------------------------------

out=$(run "$PROTECTED_WITH_CONTEXTS" --require-check shell-checks)
assert_eq "requested and existing contexts are unioned" '["build","shell-checks"]' \
  "$(sent -c '.required_status_checks.contexts')"
assert_eq "an existing strict setting is preserved" "false" \
  "$(sent '.required_status_checks.strict')"
assert_eq "reports what is required now" "1" \
  "$(echo "$out" | grep -c 'Required status checks: build, shell-checks')"

# Asking twice for what is already required changes nothing.
run "$PROTECTED_WITH_CONTEXTS" --require-check build > /dev/null
assert_eq "re-requiring an existing context does not duplicate it" '["build"]' \
  "$(sent -c '.required_status_checks.contexts')"

# --- --require-check on an unprotected branch -----------------------------------

run "" --require-check shell-checks > /dev/null
assert_eq "a first requirement creates the block" '["shell-checks"]' \
  "$(sent -c '.required_status_checks.contexts')"
assert_eq "strict defaults off rather than null" "false" \
  "$(sent '.required_status_checks.strict')"

finish
