#!/usr/bin/env bash
# Test check-review-gate.sh: enforces standards/review-gates.md — a
# ticket-loop repo must be onboarded (scripts/setup-reviewer.sh) before
# ticket-loop.sh tries to arm auto-merge on it. gh is mocked; no network.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CHECK="../check-review-gate.sh"

# --- fake gh -------------------------------------------------------------
# Driven entirely by env vars set per-scenario:
#   FAKE_GH_REPO             expected "owner/name" for the bare repo lookup
#   FAKE_GH_REPO_JSON        body for `gh api repos/<repo>` (unset -> 404)
#   FAKE_GH_COLLAB_LOGIN     login that IS a collaborator (unset -> none is)
#   FAKE_GH_PROTECTION       body for the branch protection endpoint (unset -> 404)
#   FAKE_GH_LABEL            "yes" if human-signoff label exists
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  auth) exit 0 ;;
  api)
    path="$2"
    case "$path" in
      */collaborators/*)
        [ "$path" = "repos/$FAKE_GH_REPO/collaborators/$FAKE_GH_COLLAB_LOGIN" ] && exit 0 || exit 1
        ;;
      */branches/*/protection)
        if [ -z "${FAKE_GH_PROTECTION:-}" ]; then
          # Real gh prints the error body to stdout even on 404 — mimic that
          # so the check under test can't accidentally treat it as success.
          echo '{"message":"Branch not protected"}'
          exit 1
        fi
        echo "$FAKE_GH_PROTECTION"
        ;;
      */labels/human-signoff)
        [ "${FAKE_GH_LABEL:-}" = "yes" ] && exit 0 || exit 1
        ;;
      repos/*)
        if [ -z "${FAKE_GH_REPO_JSON:-}" ]; then
          echo '{"message":"Not Found"}'
          exit 1
        fi
        echo "$FAKE_GH_REPO_JSON"
        ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$TMPDIR/bin/gh"
export PATH="$TMPDIR/bin:$PATH"

# A product YAML on the given workflow, repo, and optional divergence.
# workflow/repo have no defaults: an empty string means "key present but
# blank" (as opposed to omitting the key), and callers must be explicit.
make_product() {
  local path="$1" workflow="$2" repo="$3" divergence="${4:-}"
  {
    echo "name: fixture"
    echo "repo: $repo"
    echo "status: active"
    echo "choices:"
    echo "  ai_workflow: $workflow"
    if [ -n "$divergence" ]; then
      echo "divergences:"
      echo "  - standard: review-gate"
      echo "    choice: none"
      echo "    reason: solo hobby project, no reviewer needed"
    else
      echo "divergences: []"
    fi
  } > "$path"
}

# A fully onboarded repo's gh responses.
onboard_gh_env() {
  export FAKE_GH_REPO="example/fixture"
  export FAKE_GH_REPO_JSON='{"default_branch":"main","allow_auto_merge":true}'
  export FAKE_GH_COLLAB_LOGIN="lennons301-reviewer"
  export FAKE_GH_PROTECTION='{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true}}'
  export FAKE_GH_LABEL="yes"
}

reset_gh_env() {
  unset FAKE_GH_REPO FAKE_GH_REPO_JSON FAKE_GH_COLLAB_LOGIN FAKE_GH_PROTECTION FAKE_GH_LABEL REVIEWER_LOGIN
}

run_check() {
  local repo="$1" product="$2"
  OUTPUT=$("$CHECK" "$repo" "$product" 2>&1)
  STATUS=$?
}

REPO_DIR="$TMPDIR/repo"
mkdir -p "$REPO_DIR/docs/agents"
echo "human_signoff: {}" > "$REPO_DIR/docs/agents/review-gates.yaml"

# --- not on ticket-loop -> skipped, not failed --------------------------------
reset_gh_env
make_product "$TMPDIR/other.yaml" "superpowers" "example/fixture"
run_check "$REPO_DIR" "$TMPDIR/other.yaml"
assert_eq "superpowers workflow is skipped" "0" "$STATUS"
assert_eq "skip says why" "yes" \
  "$(echo "$OUTPUT" | grep -q "n/a: superpowers workflow" && echo yes || echo no)"

make_product "$TMPDIR/none.yaml" "" "example/fixture"
run_check "$REPO_DIR" "$TMPDIR/none.yaml"
assert_eq "no ai_workflow is skipped" "0" "$STATUS"

# --- documented divergence -----------------------------------------------------
reset_gh_env
make_product "$TMPDIR/diverged.yaml" "ticket-loop" "example/fixture" "yes"
run_check "$REPO_DIR" "$TMPDIR/diverged.yaml"
assert_eq "documented divergence passes without calling gh" "0" "$STATUS"
assert_eq "divergence renders as ✓*" "yes" \
  "$(echo "$OUTPUT" | grep -q "✓\*" && echo yes || echo no)"

# --- ticket-loop, no repo configured -------------------------------------------
reset_gh_env
make_product "$TMPDIR/norepo.yaml" "ticket-loop" ""
run_check "$REPO_DIR" "$TMPDIR/norepo.yaml"
assert_eq "missing repo fails" "1" "$STATUS"
assert_eq "missing repo names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "no repo configured" && echo yes || echo no)"

# --- fully onboarded -> pass ---------------------------------------------------
onboard_gh_env
make_product "$TMPDIR/ok.yaml" "ticket-loop" "example/fixture"
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "fully onboarded repo passes" "0" "$STATUS"
assert_eq "pass output" "  review-gate: ✓" "$OUTPUT"

# --- reviewer login override ---------------------------------------------------
onboard_gh_env
export FAKE_GH_COLLAB_LOGIN="custom-reviewer"
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "default login not seen as collaborator when only custom login is" "1" "$STATUS"
assert_eq "names the default login" "yes" \
  "$(echo "$OUTPUT" | grep -q "lennons301-reviewer is not a collaborator" && echo yes || echo no)"

export REVIEWER_LOGIN="custom-reviewer"
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "REVIEWER_LOGIN override is honoured" "0" "$STATUS"
unset REVIEWER_LOGIN

# --- missing collaborator ------------------------------------------------------
onboard_gh_env
unset FAKE_GH_COLLAB_LOGIN
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "missing collaborator fails" "1" "$STATUS"
assert_eq "names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "is not a collaborator" && echo yes || echo no)"

# --- no branch protection ------------------------------------------------------
onboard_gh_env
unset FAKE_GH_PROTECTION
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "missing branch protection fails" "1" "$STATUS"
assert_eq "names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "no branch protection" && echo yes || echo no)"

# --- branch protection without enough approvals --------------------------------
onboard_gh_env
export FAKE_GH_PROTECTION='{"required_pull_request_reviews":{"required_approving_review_count":0,"dismiss_stale_reviews":true}}'
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "zero required approvals fails" "1" "$STATUS"
assert_eq "names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "does not require an approving review" && echo yes || echo no)"

# --- branch protection without dismiss_stale_reviews ---------------------------
onboard_gh_env
export FAKE_GH_PROTECTION='{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":false}}'
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "no dismiss_stale_reviews fails" "1" "$STATUS"
assert_eq "names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "does not dismiss stale reviews" && echo yes || echo no)"

# --- auto-merge disabled --------------------------------------------------------
onboard_gh_env
export FAKE_GH_REPO_JSON='{"default_branch":"main","allow_auto_merge":false}'
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "auto-merge disabled fails" "1" "$STATUS"
assert_eq "names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "allow_auto_merge is not enabled" && echo yes || echo no)"

# --- missing human-signoff label ------------------------------------------------
onboard_gh_env
unset FAKE_GH_LABEL
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "missing label fails" "1" "$STATUS"
assert_eq "names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "human-signoff label missing" && echo yes || echo no)"

# --- missing docs/agents/review-gates.yaml --------------------------------------
onboard_gh_env
BARE_REPO="$TMPDIR/bare-repo"; mkdir -p "$BARE_REPO"
run_check "$BARE_REPO" "$TMPDIR/ok.yaml"
assert_eq "missing gate-extension file fails" "1" "$STATUS"
assert_eq "names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "docs/agents/review-gates.yaml missing" && echo yes || echo no)"

# --- output matches the parsed line contract ------------------------------------
onboard_gh_env
run_check "$REPO_DIR" "$TMPDIR/ok.yaml"
assert_eq "output parses to dimension+status" "review-gate	pass" \
  "$(source ../lib.sh; echo "$OUTPUT" | parse_check_output | cut -f1,2)"

reset_gh_env
finish
