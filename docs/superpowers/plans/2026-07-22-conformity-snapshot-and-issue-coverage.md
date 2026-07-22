# Conformity Snapshot + Full Issue Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `check-estate.sh` emit a machine-readable JSON conformity snapshot, and rewrite `create-issues.sh` to consume that snapshot so *every* failed check dimension (10 total) becomes a GitHub Issue — not just versions and secrets.

**Architecture:** The check scripts' existing human-readable output (`  <dim>: ✓|✗|✓* (details)`) becomes a parsed contract: a new `parse_check_output` helper in `checks/lib.sh` converts it to TSV, and `check-estate.sh --json <path>` assembles a JSON snapshot with `jq`. `create-issues.sh` is rewritten to read only the snapshot (no more duplicated gap-derivation logic), filing one issue per (product, failed dimension). CI emits + commits the snapshot on push and a daily cron, then files issues. The snapshot doubles as the data source for the future estate health dashboard (see `docs/superpowers/specs/2026-06-29-estate-health-dashboard-design.md`).

**Tech Stack:** bash, yq (mikefarah v4, already required), jq (new requirement — preinstalled on GitHub `ubuntu-latest` runners), gh CLI, GitHub Actions.

## Global Constraints

- Shell scripts source `checks/lib.sh`; never `set -e` in check scripts (exit codes signal gap counts and callers count failures).
- Exit code conventions are load-bearing: individual checks exit 0 (conformant) or 1 (gap); `check-all.sh` exits with the count of failed checks; test scripts exit with the count of failed assertions.
- The check output line format `  <dimension>: <symbol>[ (details)]` (two leading spaces) is now a **parsed contract** — any change to it must update `parse_check_output` and its test.
- Status symbols: `✓` = pass, `✗` = fail, `✓*` = documented divergence, `~` = warn. Colors are ANSI codes disabled when stdout is not a TTY (lib.sh checks `[ -t 1 ]`), so captured output is always plain text.
- There are exactly **10 check dimensions**, in `check-all.sh` order: secrets, versions, environments, documentation, architecture, ci-cd, testing, linting, dev-environment, local-development.
- The snapshot lives at `data/conformity-snapshot.json` (repo root `data/` dir), committed by CI.
- Divergences (`✓*`) never generate issues. Archived products are skipped. Products whose repo is not cloned locally appear in the snapshot with `checked: false` and generate no issues.
- All new/changed shell files must be executable (`chmod +x`).
- Run all shell tests with: `./checks/tests/run-tests.sh` (exit 0 = all pass).

---

### Task 1: Test harness + `parse_check_output` in lib.sh

**Files:**
- Create: `checks/tests/helpers.sh`
- Create: `checks/tests/run-tests.sh`
- Create: `checks/tests/test-parse.sh`
- Modify: `checks/lib.sh` (append two functions at end of file)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `parse_check_output` — reads check output on stdin, writes TSV lines `dimension<TAB>status<TAB>details` to stdout (status ∈ pass|fail|divergence|warn; details empty string if none). `require_jq` — exits 1 with install hint if `jq` missing. Test helpers: `assert_eq <desc> <expected> <actual>` (increments `FAILURES` on mismatch) and `finish` (exits with `$FAILURES`).

- [ ] **Step 1: Create the test harness**

Create `checks/tests/helpers.sh`:

```bash
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
```

Create `checks/tests/run-tests.sh`:

```bash
#!/usr/bin/env bash
# Run all shell tests. Exit code = number of failing test scripts.
cd "$(dirname "$0")" || exit 1
FAILURES=0
for t in test-*.sh; do
  echo "== $t"
  if ! bash "$t"; then
    FAILURES=$((FAILURES + 1))
  fi
done
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "All test scripts passed."
else
  echo "$FAILURES test script(s) failed."
fi
exit $FAILURES
```

Run: `chmod +x checks/tests/helpers.sh checks/tests/run-tests.sh`

- [ ] **Step 2: Write the failing test**

Create `checks/tests/test-parse.sh`:

```bash
#!/usr/bin/env bash
# Test parse_check_output (lib.sh): check output text -> TSV.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
source ../lib.sh

input=$(cat <<'EOF'
lemons:
  secrets: ✗ (not yet migrated to Doppler)
  versions: ✓
  environments: ✓* (intentional divergence)
  documentation: ✗ (missing section: command)
this line is noise and must be ignored
EOF
)

actual=$(echo "$input" | parse_check_output)
expected=$(printf 'secrets\tfail\tnot yet migrated to Doppler\nversions\tpass\t\nenvironments\tdivergence\tintentional divergence\ndocumentation\tfail\tmissing section: command')

assert_eq "parses statuses and details into TSV" "$expected" "$actual"

finish
```

Run: `chmod +x checks/tests/test-parse.sh`

- [ ] **Step 3: Run test to verify it fails**

Run: `./checks/tests/run-tests.sh`
Expected: FAIL — `parse_check_output: command not found`, exit code 1.

- [ ] **Step 4: Implement `parse_check_output` and `require_jq` in lib.sh**

Append to the end of `checks/lib.sh`:

```bash
# Check that jq is available
require_jq() {
  if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed." >&2
    echo "Install: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

# Parse check output into TSV: dimension<TAB>status<TAB>details
# Reads stdin, writes stdout. Non-matching lines are ignored.
# Symbol mapping: ✓ -> pass, ✗ -> fail, ✓* -> divergence, ~ -> warn.
# NOTE: this makes the check output line format a contract. If a check
# script changes its output shape, update this parser and test-parse.sh.
parse_check_output() {
  local line dim sym details status
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]][[:space:]]([a-z-]+):[[:space:]](✓\*|✓|✗|~)([[:space:]]\((.*)\))?$ ]]; then
      dim="${BASH_REMATCH[1]}"
      sym="${BASH_REMATCH[2]}"
      details="${BASH_REMATCH[4]:-}"
      case "$sym" in
        "✓*") status="divergence" ;;
        "✓")  status="pass" ;;
        "✗")  status="fail" ;;
        "~")  status="warn" ;;
      esac
      printf '%s\t%s\t%s\n' "$dim" "$status" "$details"
    fi
  done
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./checks/tests/run-tests.sh`
Expected: `PASS: parses statuses and details into TSV`, `All test scripts passed.`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add checks/lib.sh checks/tests/
git commit -m "feat(checks): add parse_check_output + shell test harness"
```

---

### Task 2: `--json` snapshot emission in check-estate.sh

**Files:**
- Modify: `checks/check-estate.sh` (full rewrite shown below)
- Create: `checks/tests/fixtures/products/testproj.yaml`
- Create: `checks/tests/fixtures/repos/testproj/.gitkeep`
- Create: `checks/tests/test-snapshot.sh`

**Interfaces:**
- Consumes: `parse_check_output`, `require_jq` from Task 1.
- Produces: `check-estate.sh --json <path>` writes a snapshot with this schema (the contract for Task 3 and the future dashboard):

```json
{
  "generated_at": "2026-07-22T10:00:00Z",
  "platform_commit": "f4a5e2d",
  "total_gaps": 9,
  "total_products_checked": 4,
  "products": [
    {
      "name": "lemons", "repo": "lennons301/lemons",
      "category": "product", "status": "active",
      "checked": true, "gap_count": 2,
      "dimensions": [
        {"dimension": "secrets", "status": "fail", "details": "not yet migrated to Doppler"}
      ]
    },
    {
      "name": "other", "repo": "lennons301/other",
      "category": "product", "status": "active",
      "checked": false, "skip_reason": "repo not found"
    }
  ]
}
```

Also produces a `--products-dir <path>` flag (needed for fixture testing; mirrors `--repos-dir`).

- [ ] **Step 1: Create fixtures**

Create `checks/tests/fixtures/products/testproj.yaml`:

```yaml
name: testproj
description: Fixture project for snapshot tests
category: product
repo: example/testproj
status: active
package_manager: npm

choices:
  secrets: doppler

versions:
  node: "22"
  next: "16"
  react: "19"
  typescript: "5.7"

divergences: []
```

Create the fixture repo as an empty directory (no CLAUDE.md, so the `documentation` dimension deterministically fails):

```bash
mkdir -p checks/tests/fixtures/repos/testproj
touch checks/tests/fixtures/repos/testproj/.gitkeep
```

- [ ] **Step 2: Write the failing test**

Create `checks/tests/test-snapshot.sh`:

```bash
#!/usr/bin/env bash
# Test check-estate.sh --json snapshot emission against fixtures.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

SNAPSHOT=$(mktemp)
trap 'rm -f "$SNAPSHOT"' EXIT

../check-estate.sh \
  --products-dir fixtures/products \
  --repos-dir fixtures/repos \
  --json "$SNAPSHOT" > /dev/null

assert_eq "one product checked" "1" "$(jq '.total_products_checked' "$SNAPSHOT")"
assert_eq "product name" "testproj" "$(jq -r '.products[0].name' "$SNAPSHOT")"
assert_eq "product repo" "example/testproj" "$(jq -r '.products[0].repo' "$SNAPSHOT")"
assert_eq "product checked" "true" "$(jq '.products[0].checked' "$SNAPSHOT")"
assert_eq "10 dimensions recorded" "10" "$(jq '.products[0].dimensions | length' "$SNAPSHOT")"
assert_eq "documentation dimension fails" "fail" \
  "$(jq -r '.products[0].dimensions[] | select(.dimension == "documentation") | .status' "$SNAPSHOT")"
assert_eq "gap_count equals failed-dimension count" \
  "$(jq '[.products[0].dimensions[] | select(.status == "fail")] | length' "$SNAPSHOT")" \
  "$(jq '.products[0].gap_count' "$SNAPSHOT")"
assert_eq "total_gaps equals gap_count sum" \
  "$(jq '[.products[] | select(.checked) | .gap_count] | add' "$SNAPSHOT")" \
  "$(jq '.total_gaps' "$SNAPSHOT")"
assert_eq "no unknown status values" "0" \
  "$(jq '[.products[0].dimensions[].status | select(. != "pass" and . != "fail" and . != "divergence" and . != "warn")] | length' "$SNAPSHOT")"
assert_eq "generated_at present" "true" "$(jq '.generated_at | length > 0' "$SNAPSHOT")"

finish
```

Run: `chmod +x checks/tests/test-snapshot.sh`

- [ ] **Step 3: Run test to verify it fails**

Run: `./checks/tests/run-tests.sh`
Expected: test-snapshot.sh FAILS — `check-estate.sh` rejects `--products-dir`/`--json` with `Unknown arg`, so `jq` reads an empty file and assertions mismatch. test-parse.sh still passes.

- [ ] **Step 4: Rewrite check-estate.sh**

Replace the full contents of `checks/check-estate.sh` with:

```bash
#!/usr/bin/env bash
# Run conformity checks across the entire estate.
# Usage: check-estate.sh [--repos-dir <path>] [--products-dir <path>]
#                        [--include-archived] [--json <output-path>]
#
# --json writes a machine-readable snapshot consumed by create-issues.sh
# and the (planned) estate health dashboard.

source "$(dirname "$0")/lib.sh"
require_yq

SCRIPT_DIR="$(dirname "$0")"
PRODUCTS_DIR="$SCRIPT_DIR/../products"
REPOS_DIR="$HOME/code"
INCLUDE_ARCHIVED=""
JSON_OUT=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --repos-dir) REPOS_DIR="$2"; shift 2 ;;
    --products-dir) PRODUCTS_DIR="$2"; shift 2 ;;
    --include-archived) INCLUDE_ARCHIVED="--include-archived"; shift ;;
    --json) JSON_OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$JSON_OUT" ]; then
  require_jq
fi

echo ""
echo "Estate Conformity Report — $(date +%Y-%m-%d)"
echo "═══════════════════════════════════════"

TOTAL_PRODUCTS=0
TOTAL_GAPS=0
PRODUCT_DOCS=()

for product_yaml in "$PRODUCTS_DIR"/*.yaml; do
  name=$(product_name "$product_yaml")
  status=$(product_status "$product_yaml")
  category=$(product_category "$product_yaml")
  repo=$(yaml_get "$product_yaml" '.repo')

  if [ "$status" = "archived" ] && [ -z "$INCLUDE_ARCHIVED" ]; then
    continue
  fi

  project_path="$REPOS_DIR/$name"

  if [ ! -d "$project_path" ]; then
    echo "$name: skipped (repo not found at $project_path)"
    if [ -n "$JSON_OUT" ]; then
      PRODUCT_DOCS+=("$(jq -n \
        --arg name "$name" --arg repo "$repo" \
        --arg category "$category" --arg status "$status" \
        '{name: $name, repo: $repo, category: $category, status: $status,
          checked: false, skip_reason: "repo not found"}')")
    fi
    continue
  fi

  TOTAL_PRODUCTS=$((TOTAL_PRODUCTS + 1))

  # Run check-all and capture output + exit code (which is the gap count)
  output=$("$SCRIPT_DIR/check-all.sh" "$project_path" "$product_yaml" $INCLUDE_ARCHIVED 2>&1)
  gaps=$?
  echo "$output"
  TOTAL_GAPS=$((TOTAL_GAPS + gaps))

  if [ -n "$JSON_OUT" ]; then
    dims=$(echo "$output" | parse_check_output | jq -R -s '
      split("\n")
      | map(select(length > 0) | split("\t")
        | {dimension: .[0], status: .[1], details: .[2]})')
    PRODUCT_DOCS+=("$(jq -n \
      --arg name "$name" --arg repo "$repo" \
      --arg category "$category" --arg status "$status" \
      --argjson gaps "$gaps" --argjson dims "$dims" \
      '{name: $name, repo: $repo, category: $category, status: $status,
        checked: true, gap_count: $gaps, dimensions: $dims}')")
  fi

  echo ""
done

echo "═══════════════════════════════════════"
echo "$TOTAL_GAPS gap(s) found across $TOTAL_PRODUCTS product(s)."

if [ -n "$JSON_OUT" ]; then
  platform_commit=$(git -C "$SCRIPT_DIR/.." rev-parse --short HEAD 2>/dev/null || echo "unknown")
  { for doc in "${PRODUCT_DOCS[@]:-}"; do echo "$doc"; done; } | jq -s \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg platform_commit "$platform_commit" \
    --argjson total_gaps "$TOTAL_GAPS" \
    --argjson total_products "$TOTAL_PRODUCTS" \
    '{generated_at: $generated_at, platform_commit: $platform_commit,
      total_gaps: $total_gaps, total_products_checked: $total_products,
      products: (. | map(select(. != "")))}' > "$JSON_OUT"
  echo "Snapshot written to $JSON_OUT"
fi

if [ "$TOTAL_GAPS" -gt 0 ]; then
  echo "Run checks/create-issues.sh to file GitHub Issues."
fi
```

Note on `map(select(. != ""))`: with an empty `PRODUCT_DOCS` array, the `${PRODUCT_DOCS[@]:-}` expansion emits one empty line; `jq -s` over whitespace-only input yields `[]`, and the filter is a no-op safeguard. Human-readable output is byte-identical to before when `--json` is not passed.

- [ ] **Step 5: Run test to verify it passes**

Run: `./checks/tests/run-tests.sh`
Expected: both test scripts PASS, exit 0.

- [ ] **Step 6: Verify human output is unchanged without --json**

Run: `./checks/check-estate.sh --products-dir checks/tests/fixtures/products --repos-dir checks/tests/fixtures/repos`
Expected: the familiar human report (testproj with ✗ marks), no snapshot file created, no jq requirement triggered.

- [ ] **Step 7: Commit**

```bash
git add checks/check-estate.sh checks/tests/
git commit -m "feat(checks): emit JSON conformity snapshot via check-estate --json"
```

---

### Task 3: Rewrite create-issues.sh to consume the snapshot (all 10 dimensions)

**Files:**
- Modify: `checks/create-issues.sh` (full rewrite shown below)
- Create: `checks/tests/fixtures/snapshot.json`
- Create: `checks/tests/test-create-issues.sh`

**Interfaces:**
- Consumes: the snapshot schema from Task 2; `require_jq` from Task 1.
- Produces: `create-issues.sh [--dry-run] [--snapshot <path>]` (default snapshot path `data/conformity-snapshot.json`). One issue per (product, failed dimension), marker `<!-- platform-check:<dimension>/<product> -->`, title `[platform] <product>: fix <dimension> conformity`, label `platform-upgrade` (unchanged, to keep existing label continuity).

**Behavior changes vs the old script (intentional):**
1. Gaps come from the snapshot, not re-derived from YAMLs — the duplicated version-comparison logic is deleted.
2. Issue granularity is per dimension, not per version key. Old-style open issues with markers like `platform-check:versions/next/lemons` will NOT be deduplicated against new markers — after first real run, close any stale old-style issues manually (there is at most a handful).
3. `--dry-run` is now fully offline: it skips label creation AND the gh dedupe search (the old script called `gh issue list` even in dry-run). This makes tests hermetic.

- [ ] **Step 1: Create the fixture snapshot**

Create `checks/tests/fixtures/snapshot.json`:

```json
{
  "generated_at": "2026-07-22T00:00:00Z",
  "platform_commit": "abc1234",
  "total_gaps": 3,
  "total_products_checked": 2,
  "products": [
    {
      "name": "alpha",
      "repo": "example/alpha",
      "category": "product",
      "status": "active",
      "checked": true,
      "gap_count": 2,
      "dimensions": [
        {"dimension": "secrets", "status": "fail", "details": "not yet migrated to Doppler"},
        {"dimension": "versions", "status": "fail", "details": "next: 15 → 16"},
        {"dimension": "environments", "status": "divergence", "details": "intentional divergence"},
        {"dimension": "documentation", "status": "pass", "details": ""}
      ]
    },
    {
      "name": "beta",
      "repo": null,
      "category": "product",
      "status": "active",
      "checked": true,
      "gap_count": 1,
      "dimensions": [
        {"dimension": "secrets", "status": "fail", "details": "no doppler.yaml found"}
      ]
    },
    {
      "name": "gamma",
      "repo": "example/gamma",
      "category": "product",
      "status": "active",
      "checked": false,
      "skip_reason": "repo not found"
    }
  ]
}
```

This exercises: two real gaps (alpha/secrets, alpha/versions), a divergence (no issue), a pass (no issue), a repo-less product (skipped with message), and an unchecked product (ignored).

- [ ] **Step 2: Write the failing test**

Create `checks/tests/test-create-issues.sh`:

```bash
#!/usr/bin/env bash
# Test create-issues.sh dry-run against a fixture snapshot.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh

output=$(../create-issues.sh --dry-run --snapshot fixtures/snapshot.json)

assert_eq "plans exactly 2 issues" "2" \
  "$(echo "$output" | grep -c 'DRY RUN: would create issue')"
assert_eq "secrets issue on alpha" "1" \
  "$(echo "$output" | grep -c 'would create issue on example/alpha: \[platform\] alpha: fix secrets conformity')"
assert_eq "versions issue on alpha" "1" \
  "$(echo "$output" | grep -c 'would create issue on example/alpha: \[platform\] alpha: fix versions conformity')"
assert_eq "no issue for divergence" "0" \
  "$(echo "$output" | grep -c 'fix environments conformity')"
assert_eq "repo-less product is skipped with message" "1" \
  "$(echo "$output" | grep -c 'SKIP: beta/secrets (no repo configured)')"
assert_eq "missing snapshot is an error" "1" \
  "$(../create-issues.sh --dry-run --snapshot /nonexistent.json 2>&1 > /dev/null | grep -c 'snapshot not found'; true)"

finish
```

Run: `chmod +x checks/tests/test-create-issues.sh`

- [ ] **Step 3: Run test to verify it fails**

Run: `./checks/tests/run-tests.sh`
Expected: test-create-issues.sh FAILS (`Unknown arg: --snapshot`); the other two test scripts still pass.

- [ ] **Step 4: Rewrite create-issues.sh**

Replace the full contents of `checks/create-issues.sh` with:

```bash
#!/usr/bin/env bash
# Create GitHub Issues for conformity gaps recorded in a snapshot.
# Usage: create-issues.sh [--dry-run] [--snapshot <path>]
#
# Consumes the JSON snapshot emitted by `check-estate.sh --json` and files
# one issue per (product, failed dimension). Passing dimensions, documented
# divergences, and unchecked products generate no issues.
# Requires: jq; gh CLI authenticated with repo scope (not needed for --dry-run).

source "$(dirname "$0")/lib.sh"
require_jq

SCRIPT_DIR="$(dirname "$0")"
SNAPSHOT="$SCRIPT_DIR/../data/conformity-snapshot.json"
DRY_RUN=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN="true"; shift ;;
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ ! -f "$SNAPSHOT" ]; then
  echo "ERROR: snapshot not found: $SNAPSHOT" >&2
  echo "Generate one: ./checks/check-estate.sh --json $SNAPSHOT" >&2
  exit 1
fi

if [ -z "$DRY_RUN" ] && ! command -v gh &> /dev/null; then
  echo "ERROR: gh CLI is required." >&2
  exit 1
fi

CREATED=0
SKIPPED=0

# Map a check dimension to the platform doc that defines the standard.
standard_doc() {
  case "$1" in
    versions) echo "versions/manifest.yaml" ;;
    architecture) echo "standards/architecture-diagrams.md" ;;
    *) echo "standards/$1.md" ;;
  esac
}

create_issue_if_needed() {
  local repo="$1" title="$2" body="$3" marker="$4"

  if [ -n "$DRY_RUN" ]; then
    echo "  DRY RUN: would create issue on $repo: $title"
    CREATED=$((CREATED + 1))
    return
  fi

  # Ensure label exists
  gh label create "platform-upgrade" --repo "$repo" --color "0E8A16" \
    --description "Automated platform conformity upgrade" --force 2>/dev/null || true

  # Dedupe: search for the marker text without HTML comment tags
  # (GitHub may not index HTML comments).
  local search_text existing
  search_text=$(echo "$marker" | sed 's/<!-- //;s/ -->//')
  existing=$(gh issue list --repo "$repo" --state open --search "$search_text" \
    --json number --jq '.[0].number' 2>/dev/null || echo "")

  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    echo "  SKIP: issue #$existing already open on $repo"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  gh issue create --repo "$repo" --title "$title" --label "platform-upgrade" --body "$body"
  echo "  CREATED: $title on $repo"
  CREATED=$((CREATED + 1))
}

echo "Reading snapshot: $SNAPSHOT (generated $(jq -r '.generated_at' "$SNAPSHOT"))"

while IFS=$'\t' read -r name repo dimension details; do
  if [ -z "$repo" ] || [ "$repo" = "null" ]; then
    echo "  SKIP: $name/$dimension (no repo configured)"
    continue
  fi

  marker="<!-- platform-check:$dimension/$name -->"
  title="[platform] $name: fix $dimension conformity"
  body="## Conformity gap

- **Product:** $name
- **Dimension:** $dimension
- **Details:** $details

## Definition of done

From the platform repo, this exits 0:

\`\`\`bash
./checks/check-$dimension.sh <path-to-$name-checkout> products/$name.yaml
\`\`\`

## Context

- Standard: $(standard_doc "$dimension")
- Product config: products/$name.yaml
- If this gap is intentional, document a divergence in products/$name.yaml instead of fixing.

$marker"

  create_issue_if_needed "$repo" "$title" "$body" "$marker"
done < <(jq -r '
  .products[]
  | select(.checked == true)
  | .name as $n | .repo as $r
  | .dimensions[]
  | select(.status == "fail")
  | [$n, $r, .dimension, .details]
  | @tsv' "$SNAPSHOT")

echo ""
echo "Done. Created: $CREATED, Skipped (already open): $SKIPPED"
```

Note: `jq @tsv` renders a `null` repo as an empty field, which the `[ -z "$repo" ]` guard catches. The `< <(...)` process substitution keeps `CREATED`/`SKIPPED` in the main shell.

- [ ] **Step 5: Run test to verify it passes**

Run: `./checks/tests/run-tests.sh`
Expected: all three test scripts PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
git add checks/create-issues.sh checks/tests/
git commit -m "feat(checks): create-issues consumes snapshot, covers all 10 dimensions"
```

---

### Task 4: CI wiring + docs

**Files:**
- Modify: `.github/workflows/conformity.yml` (full rewrite shown below)
- Modify: `README.md` (Quick start section)
- Modify: `AGENTS.md` (Commands section)

**Interfaces:**
- Consumes: `check-estate.sh --json` (Task 2), `create-issues.sh --snapshot` (Task 3), `run-tests.sh` (Task 1).
- Produces: CI that (a) runs shell tests, (b) emits + commits `data/conformity-snapshot.json` when semantically changed, (c) files issues — on push, daily cron, and manual dispatch.

- [ ] **Step 1: Rewrite the workflow**

Replace the full contents of `.github/workflows/conformity.yml` with:

```yaml
name: Estate Conformity Check
on:
  push:
    branches: [main, master]
  schedule:
    - cron: '0 6 * * *'   # daily 06:00 UTC — catches drift without a platform push
  workflow_dispatch:

permissions:
  contents: write

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq \
            https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq
        # jq is preinstalled on ubuntu-latest runners

      - name: Run shell tests
        run: ./checks/tests/run-tests.sh

      - name: Clone product repos
        run: |
          mkdir -p /tmp/repos
          for f in products/*.yaml; do
            name=$(yq '.name' "$f")
            repo=$(yq '.repo' "$f")
            status=$(yq '.status' "$f")
            if [ "$status" = "archived" ]; then continue; fi
            gh repo clone "$repo" "/tmp/repos/$name" -- --depth 1 || echo "WARN: failed to clone $repo"
          done
        env:
          GH_TOKEN: ${{ secrets.GH_TOKEN }}

      - name: Run conformity checks and emit snapshot
        run: |
          mkdir -p data
          ./checks/check-estate.sh --repos-dir /tmp/repos --json data/conformity-snapshot.json

      - name: Commit snapshot if semantically changed
        run: |
          # Ignore generated_at/platform_commit churn — only commit when the
          # conformity content actually changed.
          if git show HEAD:data/conformity-snapshot.json > /tmp/old-snapshot.json 2>/dev/null && \
             [ "$(jq -S 'del(.generated_at, .platform_commit)' /tmp/old-snapshot.json)" = \
               "$(jq -S 'del(.generated_at, .platform_commit)' data/conformity-snapshot.json)" ]; then
            echo "No semantic change to snapshot; skipping commit."
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add data/conformity-snapshot.json
          git commit -m "chore: update conformity snapshot [skip ci]"
          git push

      - name: Create issues for gaps
        run: ./checks/create-issues.sh --snapshot data/conformity-snapshot.json
        env:
          GH_TOKEN: ${{ secrets.GH_TOKEN }}
```

- [ ] **Step 2: Update README.md Quick start**

In `README.md`, replace the Quick start code block with:

```bash
# Run conformity checks against all local projects
./checks/check-estate.sh

# ...and also emit the machine-readable snapshot
./checks/check-estate.sh --json data/conformity-snapshot.json

# Check a single project
./checks/check-all.sh ~/code/lemons products/lemons.yaml

# Create GitHub Issues for gaps (reads the snapshot)
./checks/create-issues.sh --dry-run   # preview
./checks/create-issues.sh             # file them

# Run the shell test suite
./checks/tests/run-tests.sh
```

And add to the Structure list after the `checks/` line:

```markdown
- `data/conformity-snapshot.json` — Machine-readable conformity snapshot (CI-committed; consumed by create-issues and the planned estate dashboard)
```

- [ ] **Step 3: Update AGENTS.md Commands**

In `AGENTS.md`, in the Commands code block, replace:

```bash
# Run conformity checks across the entire estate
./checks/check-estate.sh [--repos-dir <path>]
```

with:

```bash
# Run conformity checks across the entire estate
./checks/check-estate.sh [--repos-dir <path>] [--json <snapshot-path>]

# File GitHub Issues for gaps recorded in the snapshot
./checks/create-issues.sh [--dry-run] [--snapshot <path>]

# Run the shell test suite for the check tooling
./checks/tests/run-tests.sh
```

And add to Key Conventions:

```markdown
- Check output line format (`  <dim>: ✓|✗|✓* (details)`) is a parsed contract — changes require updating `parse_check_output` in checks/lib.sh and checks/tests/test-parse.sh
- `data/conformity-snapshot.json` is the machine-readable contract between checks, create-issues.sh, and the planned estate dashboard
```

- [ ] **Step 4: Validate workflow syntax**

Run: `yq eval '.jobs.check.steps | length' .github/workflows/conformity.yml`
Expected: `6` (parses cleanly as YAML with six steps).

- [ ] **Step 5: Run full test suite**

Run: `./checks/tests/run-tests.sh`
Expected: all PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/conformity.yml README.md AGENTS.md
git commit -m "feat(ci): daily conformity snapshot + full-coverage issue creation"
```

---

### Task 5: First real snapshot + end-to-end verification

**Files:**
- Create: `data/conformity-snapshot.json` (generated, then committed)

**Interfaces:**
- Consumes: everything above, run against the real estate in `~/code`.
- Produces: the first committed snapshot — the baseline the dashboard and loop work build on.

- [ ] **Step 1: Generate the real snapshot**

Run: `./checks/check-estate.sh --json data/conformity-snapshot.json`
Expected: the human report for all active products, then `Snapshot written to data/conformity-snapshot.json`. (Products without a local clone in `~/code` appear with `checked: false` — that is expected locally; CI clones everything.)

- [ ] **Step 2: Sanity-check the snapshot**

Run: `jq '{total_gaps, total_products_checked, products: [.products[] | {name, checked, gap_count}]}' data/conformity-snapshot.json`
Expected: valid JSON summarizing every non-archived product; `total_gaps` matches the human report's count.

- [ ] **Step 3: Preview issue creation (no writes)**

Run: `./checks/create-issues.sh --dry-run`
Expected: one `DRY RUN: would create issue …` line per (product, failed dimension); count equals the number of `fail` dimensions for products with a repo. Review titles for sanity.

- [ ] **Step 4: Commit the snapshot**

```bash
git add data/conformity-snapshot.json
git commit -m "chore: commit first conformity snapshot (baseline)"
```

- [ ] **Step 5: Housekeeping note (manual, post-merge)**

After the first real (non-dry-run) CI run, check product repos for stale old-format issues (markers like `platform-check:versions/<key>/<name>`) and close them in favor of the new per-dimension issues:

```bash
gh search issues --owner lennons301 --label platform-upgrade --state open
```

---

## Self-Review Notes

- **Spec coverage:** the dashboard spec's only prerequisite from this plan is the `--json` emitter with per-product/per-dimension status + gap details — Task 2's schema covers it (statuses pass/fail/divergence, details, gap counts, skip reasons, metadata). Issue-coverage widening (roadmap Phase 0) is Task 3. CI cadence + snapshot commit (spec: "CI commits the snapshot; daily scheduled run") is Task 4.
- **Type consistency:** snapshot field names (`generated_at`, `platform_commit`, `total_gaps`, `total_products_checked`, `products[].{name,repo,category,status,checked,gap_count,skip_reason,dimensions[].{dimension,status,details}}`) are identical in Task 2 (producer), Task 2 test, Task 3 fixture, and Task 3 jq filter.
- **Known trade-offs recorded:** per-dimension issue granularity replaces per-version-key issues (coarser but a better agent work unit); dry-run no longer dedupes (hermetic tests); old-style issue markers need a one-time manual sweep (Task 5 Step 5).
