#!/usr/bin/env bash
# Test check-domain-modelling.sh: enforces standards/domain-modelling.md —
# CONTEXT.md is the conformance signal, ADRs are never required.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CHECK="../check-domain-modelling.sh"

# A product YAML on the ticket-loop workflow with no divergences.
make_product() {
  local path="$1" workflow="${2:-ticket-loop}" divergence="${3:-}"
  {
    echo "name: fixture"
    echo "repo: example/fixture"
    echo "status: active"
    echo "choices:"
    echo "  ai_workflow: $workflow"
    if [ -n "$divergence" ]; then
      echo "divergences:"
      echo "  - standard: domain-modelling"
      echo "    choice: none"
      echo "    reason: no domain vocabulary"
    else
      echo "divergences: []"
    fi
  } > "$path"
}

# A CONTEXT.md in the documented format, with $1 terms.
make_context() {
  local path="$1" terms="${2:-2}"
  {
    echo "# Fixture"
    echo ""
    echo "## Language"
    echo ""
    for i in $(seq 1 "$terms"); do
      echo "**Term$i**:"
      echo "A definition."
      echo ""
    done
  } > "$path"
}

run_check() {
  local repo="$1" product="$2"
  OUTPUT=$("$CHECK" "$repo" "$product" 2>&1)
  STATUS=$?
}

# --- no CONTEXT.md -> fail ----------------------------------------------------
REPO="$TMPDIR/bare"; mkdir -p "$REPO"
make_product "$TMPDIR/bare.yaml"
run_check "$REPO" "$TMPDIR/bare.yaml"
assert_eq "missing CONTEXT.md fails" "1" "$STATUS"
assert_eq "missing CONTEXT.md names the gap" "yes" \
  "$(echo "$OUTPUT" | grep -q "no CONTEXT.md" && echo yes || echo no)"

# --- CONTEXT.md with terms, zero ADRs -> pass ---------------------------------
REPO="$TMPDIR/modelled"; mkdir -p "$REPO"
make_context "$REPO/CONTEXT.md" 2
make_product "$TMPDIR/modelled.yaml"
run_check "$REPO" "$TMPDIR/modelled.yaml"
assert_eq "CONTEXT.md with no docs/adr/ passes" "0" "$STATUS"
assert_eq "reports the term count" "yes" \
  "$(echo "$OUTPUT" | grep -q "2 terms defined" && echo yes || echo no)"

# --- an empty docs/adr/ changes nothing ---------------------------------------
mkdir -p "$REPO/docs/adr"
run_check "$REPO" "$TMPDIR/modelled.yaml"
assert_eq "empty docs/adr/ still passes" "0" "$STATUS"

# --- a stub CONTEXT.md defining no terms -> fail ------------------------------
REPO="$TMPDIR/stub"; mkdir -p "$REPO"
printf '# Fixture\n\nTODO\n' > "$REPO/CONTEXT.md"
make_product "$TMPDIR/stub.yaml"
run_check "$REPO" "$TMPDIR/stub.yaml"
assert_eq "stub CONTEXT.md with no terms fails" "1" "$STATUS"

# --- one term is enough -------------------------------------------------------
make_context "$REPO/CONTEXT.md" 1
run_check "$REPO" "$TMPDIR/stub.yaml"
assert_eq "one term is enough" "0" "$STATUS"

# --- multi-context repo via CONTEXT-MAP.md ------------------------------------
REPO="$TMPDIR/multi"; mkdir -p "$REPO"
printf '# Context Map\n\n- [Ordering](./src/ordering/CONTEXT.md)\n' > "$REPO/CONTEXT-MAP.md"
make_product "$TMPDIR/multi.yaml"
run_check "$REPO" "$TMPDIR/multi.yaml"
assert_eq "CONTEXT-MAP.md satisfies the check" "0" "$STATUS"

# --- documented divergence ----------------------------------------------------
REPO="$TMPDIR/diverged"; mkdir -p "$REPO"
make_product "$TMPDIR/diverged.yaml" "ticket-loop" "yes"
run_check "$REPO" "$TMPDIR/diverged.yaml"
assert_eq "documented divergence passes" "0" "$STATUS"
assert_eq "divergence renders as ✓*" "yes" \
  "$(echo "$OUTPUT" | grep -q "✓\*" && echo yes || echo no)"

# --- superpowers repos are out of scope ---------------------------------------
REPO="$TMPDIR/legacy"; mkdir -p "$REPO"
make_product "$TMPDIR/legacy.yaml" "superpowers"
run_check "$REPO" "$TMPDIR/legacy.yaml"
assert_eq "superpowers workflow is skipped" "0" "$STATUS"
assert_eq "skip says why" "yes" \
  "$(echo "$OUTPUT" | grep -q "n/a: superpowers workflow" && echo yes || echo no)"

# --- output matches the parsed line contract ----------------------------------
# checks/lib.sh parse_check_output requires "  <dim>: <sym>( (details))?"
REPO="$TMPDIR/modelled"
run_check "$REPO" "$TMPDIR/modelled.yaml"
assert_eq "output parses to dimension+status" "domain-modelling	pass" \
  "$(source ../lib.sh; echo "$OUTPUT" | parse_check_output | cut -f1,2)"

finish
