#!/usr/bin/env bash
# Test check-versions.sh: version targets are floors, and a repo outside the
# manifest's ecosystem can document a divergence rather than fail forever.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

P="$TMPDIR/proj"; mkdir -p "$P"

run_check() {
  ../check-versions.sh "$P" "$1" 2>&1
}

# Case 1: versions at or above the manifest floors — passes.
cat > "$TMPDIR/current.yaml" <<'EOF'
name: current
category: product
package_manager: pnpm
versions:
  node: "22"
  next: "16"
  react: "19"
  typescript: "5.7"
  pnpm: "9"
  biome: "1"
  drizzle-kit: "0.30"
divergences: []
EOF
out=$(run_check "$TMPDIR/current.yaml"); code=$?
assert_eq "conformant versions pass" "0" "$code"
assert_eq "conformant output" "  versions: ✓" "$out"

# Case 2: a version below the floor — fails and names the gap.
cat > "$TMPDIR/behind.yaml" <<'EOF'
name: behind
category: product
package_manager: pnpm
versions:
  node: "20"
  next: "16"
  react: "19"
  typescript: "5.7"
  pnpm: "9"
  biome: "1"
  drizzle-kit: "0.30"
divergences: []
EOF
out=$(run_check "$TMPDIR/behind.yaml"); code=$?
assert_eq "version below the floor fails" "1" "$code"
assert_eq "gap names the version" "  versions: ✗ (node: 20 → 22)" "$out"

# Case 3: no versions declared at all — every relevant key is unknown, so fail.
cat > "$TMPDIR/silent.yaml" <<'EOF'
name: silent
category: product
package_manager: npm
divergences: []
EOF
out=$(run_check "$TMPDIR/silent.yaml"); code=$?
assert_eq "undeclared versions fail" "1" "$code"

# Case 4: same YAML plus a documented divergence — the dimension is out of
# scope for this repo, not broken (the platform repo itself: shell and YAML,
# no Node runtime to version).
cat > "$TMPDIR/diverged.yaml" <<'EOF'
name: diverged
category: infrastructure
divergences:
  - standard: versions
    choice: none
    reason: no Node/TypeScript runtime
EOF
out=$(run_check "$TMPDIR/diverged.yaml"); code=$?
assert_eq "documented divergence passes" "0" "$code"
assert_eq "divergence output" "  versions: ✓* (intentional divergence)" "$out"
assert_eq "divergence parses as a divergence dimension" "versions	divergence" \
  "$(source ../lib.sh; echo "$out" | parse_check_output | cut -f1,2)"

finish
