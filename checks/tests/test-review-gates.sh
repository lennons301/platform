#!/usr/bin/env bash
# Test evaluate_review_gates (scripts/review-gates-lib.sh):
# changed paths + gate YAML(s) -> gated verdict (exit 0), ungated (1), config error (2).
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
source ../../scripts/review-gates-lib.sh

FIXTURES="$(mktemp -d)"
trap 'rm -rf "$FIXTURES"' EXIT

cat > "$FIXTURES/platform.yaml" <<'EOF'
human_signoff:
  visual-ui:
    - "**/*.css"
    - "**/components/**"
    - "**/app/**/page.*"
  data-migrations:
    - "**/migrations/**"
    - "**/*.sql"
  ci-secrets:
    - ".github/workflows/**"
    - "**/.env*"
EOF

cat > "$FIXTURES/repo-ext.yaml" <<'EOF'
human_signoff:
  content:
    - "docs/**"
EOF

cat > "$FIXTURES/empty.yaml" <<'EOF'
human_signoff: {}
EOF

printf 'human_signoff: [\n  broken' > "$FIXTURES/malformed.yaml"

# --- gated: platform config only ---------------------------------------------

out=$(evaluate_review_gates "$FIXTURES/platform.yaml" "" "src/components/Button.tsx")
assert_eq "nested components path is gated (exit 0)" "0" "$?"
assert_eq "match reports category, glob, path" \
  "$(printf 'visual-ui\t**/components/**\tsrc/components/Button.tsx')" "$out"

evaluate_review_gates "$FIXTURES/platform.yaml" "" "README.md" > /dev/null
assert_eq "non-matching path is ungated (exit 1)" "1" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "" "styles.css" > /dev/null
assert_eq "**/ glob also matches at repo root" "0" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "" "a/b/c/deep.css" > /dev/null
assert_eq "**/ glob matches deeply nested path" "0" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "" ".github/workflows/ci.yml" > /dev/null
assert_eq "dotfile-rooted glob matches workflow file" "0" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "" "apps/web/.env.local" > /dev/null
assert_eq "dotfile leaf glob matches .env variants" "0" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "" "db/migrations/0001_init.sql" > /dev/null
assert_eq "path matching several globs is gated once per glob" "0" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "" "src/app/dashboard/page.tsx" > /dev/null
assert_eq "app router page file is gated" "0" "$?"

# one gated path among many ungated ones gates the set
out=$(evaluate_review_gates "$FIXTURES/platform.yaml" "" "README.md" "lib/util.ts" "seed.sql")
assert_eq "any matching path gates the whole set (exit 0)" "0" "$?"
assert_eq "only the matching path is reported" \
  "$(printf 'data-migrations\t**/*.sql\tseed.sql')" "$out"

# --- repo extension is additive -----------------------------------------------

evaluate_review_gates "$FIXTURES/platform.yaml" "$FIXTURES/repo-ext.yaml" "docs/adr/0001.md" > /dev/null
assert_eq "repo extension gates paths the platform config does not" "0" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "$FIXTURES/repo-ext.yaml" "src/index.ts" > /dev/null
assert_eq "extension does not gate unrelated paths" "1" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "$FIXTURES/nonexistent.yaml" "src/index.ts" > /dev/null
assert_eq "missing repo extension is fine (exit 1 for ungated path)" "1" "$?"

# --- degenerate configs ---------------------------------------------------------

evaluate_review_gates "$FIXTURES/empty.yaml" "" "src/components/Button.tsx" > /dev/null
assert_eq "empty gate map means ungated (exit 1)" "1" "$?"

evaluate_review_gates "$FIXTURES/nonexistent.yaml" "" "anything.css" > /dev/null 2>&1
assert_eq "missing platform config fails closed (exit 2)" "2" "$?"

evaluate_review_gates "$FIXTURES/malformed.yaml" "" "anything.css" > /dev/null 2>&1
assert_eq "malformed platform config fails closed (exit 2)" "2" "$?"

evaluate_review_gates "$FIXTURES/platform.yaml" "$FIXTURES/malformed.yaml" "anything.md" > /dev/null 2>&1
assert_eq "malformed repo extension fails closed (exit 2)" "2" "$?"

finish
