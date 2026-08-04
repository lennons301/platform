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
assert_eq "12 dimensions recorded" "12" "$(jq '.products[0].dimensions | length' "$SNAPSHOT")"
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
