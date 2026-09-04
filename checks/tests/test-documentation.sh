#!/usr/bin/env bash
# Test check-documentation.sh: enforces standards/documentation.md +
# standards/agent-context.md — README.md for people, AGENTS.md as the context
# file, tool files (CLAUDE.md etc.) as thin @AGENTS.md pointers, and a size
# warning once AGENTS.md outgrows what every session should pay to load.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PRODUCT_YAML="fixtures/products/testproj.yaml"

# A context file body satisfying all required sections + platform pointer.
sections_body() {
  cat <<'BODY'
# Test Project

## Commands
run stuff

## Tech Stack
things

## Key Conventions
rules

## Platform Context
see the platform repo
BODY
}

# A README a human could start from.
readme_body() {
  printf '# Test Project\n\nWhat it is, how to run it, where the details live.\n'
}

# The compliant layout every other case is a one-change variation of.
compliant() {
  mkdir -p "$1"
  sections_body > "$1/AGENTS.md"
  echo "@AGENTS.md" > "$1/CLAUDE.md"
  readme_body > "$1/README.md"
}

run_check() {
  ../check-documentation.sh "$1" "$PRODUCT_YAML" 2>&1
}

contains() { [[ "$1" == *"$2"* ]] && echo yes || echo no; }

# Case 1: monolithic CLAUDE.md (old-style, all sections present) — must now fail
P="$TMPDIR/monolith"; mkdir -p "$P"
sections_body > "$P/CLAUDE.md"
readme_body > "$P/README.md"
out=$(run_check "$P"); code=$?
assert_eq "monolithic CLAUDE.md fails" "1" "$code"
assert_eq "monolithic CLAUDE.md names the gap" \
  "  documentation: ✗ (no AGENTS.md — see standards/agent-context.md)" "$out"

# Case 2: AGENTS.md with all sections + thin CLAUDE.md + README — passes
P="$TMPDIR/compliant"; compliant "$P"
out=$(run_check "$P"); code=$?
assert_eq "compliant layout passes" "0" "$code"
assert_eq "compliant layout output" "  documentation: ✓" "$out"

# Case 3: AGENTS.md present but CLAUDE.md does not reference it — fails
P="$TMPDIR/no-ref"; compliant "$P"
echo "# Claude notes, no reference" > "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "CLAUDE.md without @AGENTS.md reference fails" "1" "$code"
assert_eq "missing reference named in details" \
  "  documentation: ✗ (CLAUDE.md does not reference @AGENTS.md)" "$out"

# Case 4: AGENTS.md present but no CLAUDE.md at all — fails
P="$TMPDIR/no-claude"; compliant "$P"
rm "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "missing CLAUDE.md fails" "1" "$code"
assert_eq "missing CLAUDE.md named in details" \
  "  documentation: ✗ (no CLAUDE.md (should reference @AGENTS.md))" "$out"

# Case 5: AGENTS.md missing required sections — fails and lists them
P="$TMPDIR/thin-agents"; compliant "$P"
printf '# Test Project\n\n## Platform Context\nsee platform repo\n' > "$P/AGENTS.md"
out=$(run_check "$P"); code=$?
assert_eq "AGENTS.md missing sections fails" "1" "$code"
assert_eq "missing sections listed" \
  "  documentation: ✗ (missing section: command missing section: stack|tech missing section: convention)" "$out"

# Case 6: sections checked in AGENTS.md, not CLAUDE.md — sections in CLAUDE.md don't count
P="$TMPDIR/sections-in-claude"; compliant "$P"
printf '# Test Project\n\n## Platform Context\nsee platform repo\n' > "$P/AGENTS.md"
sections_body > "$P/CLAUDE.md"
echo "@AGENTS.md" >> "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "sections in CLAUDE.md do not satisfy the check" "1" "$code"
assert_eq "sections in CLAUDE.md are reported as duplication" "yes" \
  "$(contains "$out" "CLAUDE.md duplicates AGENTS.md sections (should be a thin pointer)")"

# Case 7: no README — fails (AGENTS.md alone does not onboard a person)
P="$TMPDIR/no-readme"; compliant "$P"
rm "$P/README.md"
out=$(run_check "$P"); code=$?
assert_eq "missing README fails" "1" "$code"
assert_eq "missing README named in details" "  documentation: ✗ (no README.md)" "$out"

# Case 8: README is scaffold boilerplate nobody replaced — fails
P="$TMPDIR/boilerplate"; compliant "$P"
printf '# Welcome to your Lovable project\n\n## Project info\n' > "$P/README.md"
out=$(run_check "$P"); code=$?
assert_eq "boilerplate README fails" "1" "$code"
assert_eq "boilerplate README named in details" \
  "  documentation: ✗ (README.md is scaffold boilerplate)" "$out"

# Case 9: CLAUDE.md references AGENTS.md but re-states one of its sections — fails
P="$TMPDIR/dup-section"; compliant "$P"
printf '@AGENTS.md\n\n## Commands\nrun stuff again\n' > "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "CLAUDE.md duplicating a section fails" "1" "$code"
assert_eq "duplication named in details" \
  "  documentation: ✗ (CLAUDE.md duplicates AGENTS.md sections (should be a thin pointer))" "$out"

# Case 10: CLAUDE.md references AGENTS.md but runs long — not a thin pointer
P="$TMPDIR/long-claude"; compliant "$P"
{ echo "@AGENTS.md"; for i in {1..45}; do echo "Claude-specific note $i"; done; } > "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "long CLAUDE.md fails" "1" "$code"
assert_eq "length named in details" \
  "  documentation: ✗ (CLAUDE.md is not a thin pointer (46 non-blank lines))" "$out"

# Case 11: a thin CLAUDE.md with a few tool-specific lines is fine
P="$TMPDIR/thin-with-notes"; compliant "$P"
printf '@AGENTS.md\n\nUse the tdd skill for bug fixes.\n' > "$P/CLAUDE.md"
out=$(run_check "$P"); code=$?
assert_eq "thin CLAUDE.md with tool notes passes" "0" "$code"

# Case 12: another tool's file present without a reference — fails
P="$TMPDIR/gemini"; compliant "$P"
echo "# Gemini notes" > "$P/GEMINI.md"
out=$(run_check "$P"); code=$?
assert_eq "GEMINI.md without reference fails" "1" "$code"
assert_eq "GEMINI.md named in details" \
  "  documentation: ✗ (GEMINI.md does not reference @AGENTS.md)" "$out"

# Case 13: oversized AGENTS.md — warns, exit 0, and no ✓ line
P="$TMPDIR/big-agents"; compliant "$P"
{ sections_body; for i in {1..40}; do echo "filler line $i: $(printf 'x%.0s' {1..40})"; done; } > "$P/AGENTS.md"
out=$(AGENTS_MD_MAX_BYTES=1024 run_check "$P"); code=$?
assert_eq "oversized AGENTS.md still exits 0" "0" "$code"
assert_eq "oversized AGENTS.md warns" "yes" \
  "$(contains "$out" "  documentation: ~ (AGENTS.md is 2KB, over 1KB — move reference detail into linked docs/)")"
assert_eq "oversized AGENTS.md prints no pass line" "no" "$(contains "$out" "documentation: ✓")"

# Case 14: a paragraph-length line in AGENTS.md — warns, exit 0
P="$TMPDIR/long-line"; compliant "$P"
{ sections_body; printf '%s\n' "$(printf 'y%.0s' {1..150})"; } > "$P/AGENTS.md"
out=$(AGENTS_MD_MAX_LINE=100 run_check "$P"); code=$?
assert_eq "long line still exits 0" "0" "$code"
assert_eq "long line warns" \
  "  documentation: ~ (AGENTS.md has 1 line(s) over 100 chars — break them up or move them out)" "$out"

# Case 15: warnings and a gap together — the gap still fails, the warning still prints
P="$TMPDIR/warn-and-fail"; compliant "$P"
rm "$P/README.md"
{ sections_body; printf '%s\n' "$(printf 'y%.0s' {1..150})"; } > "$P/AGENTS.md"
out=$(AGENTS_MD_MAX_LINE=100 run_check "$P"); code=$?
assert_eq "gap beside a warning fails" "1" "$code"
assert_eq "warning printed before the gap" "yes" "$(contains "$out" "documentation: ~ (AGENTS.md has 1 line(s)")"
assert_eq "gap printed last" "  documentation: ✗ (no README.md)" "${out##*$'\n'}"

finish
