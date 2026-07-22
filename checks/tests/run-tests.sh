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
