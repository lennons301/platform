#!/usr/bin/env bash
# Test the lib.sh helpers: parse_check_output (check output text -> TSV) and
# iso_to_epoch (snapshot timestamp -> age).
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

# Snapshot ages are only as trustworthy as the timestamp parse. The BSD branch
# cannot run here, but a garbage timestamp must not silently become an epoch.
assert_eq "parses a snapshot timestamp" "1785477600" \
  "$(iso_to_epoch "2026-07-31T06:00:00Z")"
assert_eq "an unparseable timestamp yields nothing" "" \
  "$(iso_to_epoch "not a timestamp" 2>/dev/null)"
assert_eq "an unparseable timestamp reports failure" "1" \
  "$(iso_to_epoch "not a timestamp" > /dev/null 2>&1; echo $?)"

finish
