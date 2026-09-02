#!/usr/bin/env bash
# Lint every shell script in the repo with shellcheck.
# Usage: ./scripts/lint.sh [extra shellcheck args]
#
# One definition of "lint" for both CI (.github/workflows/pr-checks.yml) and
# a developer running `just lint`, so the two cannot drift apart.
#
# -x follows sourced files; -P SCRIPTDIR resolves `source "$(dirname "$0")/lib.sh"`
# relative to the script rather than the caller's cwd. Both make shellcheck see
# more, not less: without them every source line is an unresolved SC1091.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v shellcheck > /dev/null 2>&1; then
  echo "ERROR: shellcheck is required but not installed." >&2
  echo "Install: mise install (see .mise.toml) or https://github.com/koalaman/shellcheck#installing" >&2
  exit 1
fi

find checks scripts -name '*.sh' -print0 \
  | sort -z \
  | xargs -0 shellcheck -x -P SCRIPTDIR "$@"

echo "shellcheck: clean"
