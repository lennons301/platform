#!/usr/bin/env bash
# Test check-documentation.sh: enforces standards/agent-context.md —
# AGENTS.md is the context file, CLAUDE.md is a thin @AGENTS.md reference.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PRODUCT_YAML="fixtures/products/testproj.yaml"

# A context file body satisfying all required sections + platform pointer.
sections_body() {
  cat <<'EOF'
# Test Project

## Commands
run stuff

## Tech Stack
things

## Key Conventions
rules

## Platform Context
see the platform repo
EOF
}

run_check() {
  ../check-documentation.sh "$1" "$PRODUCT_YAML" 2>&1
}

# Case 1: monolithic CLAUDE.md (old-style, all sections present) — must now fail
P="$TMPDIR/monolith"; mkdir -p "$P"
sections_body > "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "monolithic CLAUDE.md fails" "1" "$code"
assert_eq "monolithic CLAUDE.md names the gap" \
  "  documentation: ✗ (no AGENTS.md — see standards/agent-context.md)" "$out"

# Case 2: AGENTS.md with all sections + thin CLAUDE.md referencing it — passes
P="$TMPDIR/compliant"; mkdir -p "$P"
sections_body > "$P/AGENTS.md"
echo "@AGENTS.md" > "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "compliant layout passes" "0" "$code"
assert_eq "compliant layout output" "  documentation: ✓" "$out"

# Case 3: AGENTS.md present but CLAUDE.md does not reference it — fails
P="$TMPDIR/no-ref"; mkdir -p "$P"
sections_body > "$P/AGENTS.md"
echo "# Claude notes, no reference" > "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "CLAUDE.md without @AGENTS.md reference fails" "1" "$code"
assert_eq "missing reference named in details" \
  "  documentation: ✗ (CLAUDE.md does not reference @AGENTS.md)" "$out"

# Case 4: AGENTS.md present but no CLAUDE.md at all — fails
P="$TMPDIR/no-claude"; mkdir -p "$P"
sections_body > "$P/AGENTS.md"
out=$(run_check "$P"); code=$?
assert_eq "missing CLAUDE.md fails" "1" "$code"
assert_eq "missing CLAUDE.md named in details" \
  "  documentation: ✗ (no CLAUDE.md (should reference @AGENTS.md))" "$out"

# Case 5: AGENTS.md missing required sections — fails and lists them
P="$TMPDIR/thin-agents"; mkdir -p "$P"
printf '# Test Project\n\n## Platform Context\nsee platform repo\n' > "$P/AGENTS.md"
echo "@AGENTS.md" > "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "AGENTS.md missing sections fails" "1" "$code"
assert_eq "missing sections listed" \
  "  documentation: ✗ (missing section: command missing section: stack|tech missing section: convention)" "$out"

# Case 6: sections checked in AGENTS.md, not CLAUDE.md — sections in CLAUDE.md don't count
P="$TMPDIR/sections-in-claude"; mkdir -p "$P"
printf '# Test Project\n\n## Platform Context\nsee platform repo\n' > "$P/AGENTS.md"
sections_body > "$P/CLAUDE.md"
echo "@AGENTS.md" >> "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "sections in CLAUDE.md do not satisfy the check" "1" "$code"

finish
