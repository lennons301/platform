#!/usr/bin/env bash
# Test scripts/snapshot-publish.sh: fresh snapshot -> feed branch + PR, against
# a real local git remote and a stubbed `gh`.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

SCRIPT="$PWD/../../scripts/snapshot-publish.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stub `gh`: records every invocation, answers `pr list` from $GH_STUB_PR.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_CALLS"
case "$1 $2" in
  # real gh runs `--jq '.[0].number'` here, so this is a bare number or nothing
  "pr list") printf '%s' "${GH_STUB_PR:-}" ;;
  "pr create")
    if [ -n "${GH_STUB_CREATE_FAIL:-}" ]; then
      echo "pull request create failed" >&2
      exit 1
    fi
    echo "https://github.com/example/platform/pull/99"
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_STUB_CALLS="$TMP/calls.log"

snapshot_json() { # <generated_at> <total_gaps>
  jq -n --arg at "$1" --argjson gaps "$2" \
    '{generated_at: $at, platform_commit: "abc1234", total_gaps: $gaps,
      total_products_checked: 2, products: [{name: "alpha", checked: true}]}'
}

# A bare origin with one commit on master carrying the committed snapshot, plus
# a working clone standing in for the CI checkout.
setup() {
  rm -rf "$TMP/origin.git" "$TMP/work"
  git init --quiet --bare -b master "$TMP/origin.git"
  git clone --quiet "$TMP/origin.git" "$TMP/work" 2>/dev/null
  git -C "$TMP/work" config user.email t@example.com
  git -C "$TMP/work" config user.name Test
  mkdir -p "$TMP/work/data"
  snapshot_json "2026-07-31T06:00:00Z" 4 > "$TMP/work/data/conformity-snapshot.json"
  git -C "$TMP/work" add data/conformity-snapshot.json
  git -C "$TMP/work" commit --quiet -m "seed snapshot"
  git -C "$TMP/work" push --quiet origin master
  : > "$GH_STUB_CALLS"
  unset GH_STUB_PR
}

# publish <generated_at> <total_gaps> [extra args...] -> stdout+stderr
publish() {
  local at="$1" gaps="$2"; shift 2
  snapshot_json "$at" "$gaps" > "$TMP/work/data/conformity-snapshot.json"
  "$SCRIPT" --snapshot "$TMP/work/data/conformity-snapshot.json" \
    --repo-dir "$TMP/work" --repo example/platform --base master "$@" 2>&1
}

feed_file() {
  git -C "$TMP/origin.git" show "automation/conformity-snapshot:data/conformity-snapshot.json" 2>/dev/null
}
feed_exists() { git -C "$TMP/origin.git" rev-parse --verify --quiet \
  refs/heads/automation/conformity-snapshot > /dev/null && echo yes || echo no; }
master_tip() { git -C "$TMP/origin.git" rev-parse master; }
pr_creates() { grep -c "^pr create" "$GH_STUB_CALLS"; }

# --- the conformity content moved: feed branch + PR ---------------------------

setup
BEFORE_MASTER="$(master_tip)"
out=$(publish "2026-09-01T06:00:00Z" 7)
assert_eq "a changed snapshot publishes (exit 0)" "0" "$?"
assert_eq "feed branch created on the remote" "yes" "$(feed_exists)"
assert_eq "feed branch carries the fresh snapshot" "7" "$(feed_file | jq '.total_gaps')"
assert_eq "protected base branch is never pushed to" "$BEFORE_MASTER" "$(master_tip)"
assert_eq "one PR opened" "1" "$(pr_creates)"
assert_eq "PR targets base from the feed branch" "1" \
  "$(grep -c -- "pr create --repo example/platform --base master --head automation/conformity-snapshot" "$GH_STUB_CALLS")"
assert_eq "reports the semantic change" "1" "$(echo "$out" | grep -c 'Snapshot changed semantically')"

# The feed branch must be a single-file diff on top of base, not a growing chain.
assert_eq "feed commit sits directly on the base tip" "$BEFORE_MASTER" \
  "$(git -C "$TMP/origin.git" rev-parse 'automation/conformity-snapshot^')"
assert_eq "feed commit touches only the snapshot" "data/conformity-snapshot.json" \
  "$(git -C "$TMP/origin.git" diff --name-only master automation/conformity-snapshot)"

# --- timestamp-only churn: feed refreshed, no PR ------------------------------

setup
out=$(publish "2026-09-01T06:00:00Z" 4)
assert_eq "timestamp-only churn still exits 0" "0" "$?"
assert_eq "feed branch still refreshed" "2026-09-01T06:00:00Z" "$(feed_file | jq -r '.generated_at')"
assert_eq "no PR for timestamp churn" "0" "$(pr_creates)"
assert_eq "says why no PR was opened" "1" "$(echo "$out" | grep -c 'No PR needed')"

# --- an already-open PR is refreshed, not duplicated --------------------------

setup
GH_STUB_PR=42 publish "2026-09-01T06:00:00Z" 7 > /dev/null
assert_eq "no second PR when one is open" "0" "$(pr_creates)"

setup
out=$(GH_STUB_PR=42 publish "2026-09-01T06:00:00Z" 7)
assert_eq "names the open PR" "1" "$(echo "$out" | grep -c 'PR #42 already open')"

# --- repeat runs converge -----------------------------------------------------

setup
BEFORE_MASTER="$(master_tip)"
publish "2026-09-01T06:00:00Z" 7 > /dev/null
FIRST_FEED="$(git -C "$TMP/origin.git" rev-parse automation/conformity-snapshot)"
publish "2026-09-02T06:00:00Z" 7 > /dev/null
assert_eq "a later run replaces the feed tip rather than stacking" "$BEFORE_MASTER" \
  "$(git -C "$TMP/origin.git" rev-parse 'automation/conformity-snapshot^')"
assert_eq "the feed tip actually moved" "1" \
  "$([ "$FIRST_FEED" != "$(git -C "$TMP/origin.git" rev-parse automation/conformity-snapshot)" ] && echo 1 || echo 0)"

# --- no committed snapshot on base yet ----------------------------------------

setup
git -C "$TMP/work" rm --quiet data/conformity-snapshot.json
git -C "$TMP/work" commit --quiet -m "drop snapshot"
git -C "$TMP/work" push --quiet origin master
mkdir -p "$TMP/work/data"
out=$(publish "2026-09-01T06:00:00Z" 7)
assert_eq "a missing base snapshot is treated as new (exit 0)" "0" "$?"
assert_eq "says the base has no snapshot yet" "1" "$(echo "$out" | grep -c 'No snapshot at data/conformity-snapshot.json on master yet')"
assert_eq "PR opened for the first snapshot" "1" "$(pr_creates)"

# --- dry run -------------------------------------------------------------------

setup
out=$(publish "2026-09-01T06:00:00Z" 7 --dry-run)
assert_eq "dry run exits 0" "0" "$?"
assert_eq "dry run pushes nothing" "no" "$(feed_exists)"
assert_eq "dry run opens no PR" "0" "$(pr_creates)"
assert_eq "dry run reports both intents" "2" \
  "$(echo "$out" | grep -c 'DRY RUN')"

# --- errors --------------------------------------------------------------------

setup
out=$("$SCRIPT" --repo-dir "$TMP/work" --repo example/platform 2>&1)
assert_eq "missing --snapshot is an error (exit 1)" "1" "$?"
assert_eq "names the required flag" "1" "$(echo "$out" | grep -c -- '--snapshot is required')"

out=$("$SCRIPT" --snapshot "$TMP/nope.json" --repo-dir "$TMP/work" 2>&1)
assert_eq "missing snapshot file is an error (exit 1)" "1" "$?"

echo '{not json' > "$TMP/bad.json"
out=$("$SCRIPT" --snapshot "$TMP/bad.json" --repo-dir "$TMP/work" --base master 2>&1)
assert_eq "invalid snapshot JSON is an error (exit 1)" "1" "$?"
assert_eq "says the snapshot is not JSON" "1" "$(echo "$out" | grep -c 'not valid JSON')"

setup
out=$(GH_STUB_CREATE_FAIL=1 publish "2026-09-01T06:00:00Z" 7)
assert_eq "a failed PR creation is an error (exit 1)" "1" "$?"
assert_eq "feed branch still landed before the PR failed" "yes" "$(feed_exists)"

out=$("$SCRIPT" --snapshot "$TMP/work/data/conformity-snapshot.json" \
  --repo-dir "$TMP/work" --repo example/platform --base master --bogus 2>&1)
assert_eq "unknown argument is an error (exit 1)" "1" "$?"

finish
