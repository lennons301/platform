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
