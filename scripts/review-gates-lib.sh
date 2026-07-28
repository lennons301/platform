#!/usr/bin/env bash
# Deterministic human-sign-off gate evaluation for the ticket-loop workflow
# (see choices/ai-dev-workflow.md). Source this file:
#   source "$(dirname "$0")/review-gates-lib.sh"
#
# Gate config shape (standards/review-gates.yaml, plus optional per-repo
# docs/agents/review-gates.yaml extension — additive only):
#
#   human_signoff:
#     <category>:
#       - "<glob>"
#
# Glob semantics are bash [[ == ]] patterns: '*' matches across '/' (so '**'
# and '*' are equivalent), and a leading '**/' also matches at the repo root.
# Paths are compared as printed by `gh pr diff --name-only` (repo-relative,
# no leading ./).

set -uo pipefail
# NOTE: no set -e — callers branch on exit codes (see below).

# evaluate_review_gates <platform-yaml> <repo-extension-yaml|""> <path>...
#   stdout: one "category<TAB>glob<TAB>path" line per match
#   exit:   0 = gated (at least one match)
#           1 = ungated
#           2 = config error — fail closed, do NOT arm auto-merge
# A missing platform config is an error; a missing repo extension is fine.
evaluate_review_gates() {
  local platform_yaml="$1" repo_yaml="$2"
  shift 2
  local paths=("$@")
  local matched=1

  if ! command -v yq &> /dev/null; then
    echo "ERROR: yq is required for review-gate evaluation." >&2
    return 2
  fi

  if [ ! -f "$platform_yaml" ]; then
    echo "ERROR: review-gates config not found: $platform_yaml" >&2
    return 2
  fi

  local files=("$platform_yaml")
  if [ -n "$repo_yaml" ] && [ -f "$repo_yaml" ]; then
    files+=("$repo_yaml")
  fi

  local file
  for file in "${files[@]}"; do
    if ! yq eval '.' "$file" > /dev/null 2>&1; then
      echo "ERROR: unparseable review-gates config: $file" >&2
      return 2
    fi
  done

  local category glob path
  for file in "${files[@]}"; do
    while IFS= read -r category; do
      [ -z "$category" ] && continue
      while IFS= read -r glob; do
        [ -z "$glob" ] && continue
        for path in "${paths[@]}"; do
          if _review_gates_path_matches "$path" "$glob"; then
            printf '%s\t%s\t%s\n' "$category" "$glob" "$path"
            matched=0
          fi
        done
      done <<< "$(yq eval ".human_signoff.\"$category\"[]" "$file" 2>/dev/null)"
    done <<< "$(yq eval '.human_signoff // {} | keys | .[]' "$file" 2>/dev/null)"
  done

  return "$matched"
}

# _review_gates_path_matches <path> <glob>
_review_gates_path_matches() {
  local path="$1" glob="$2"
  # shellcheck disable=SC2053  # unquoted RHS is intentional: glob match
  [[ "$path" == $glob ]] && return 0
  # a leading '**/' also matches files at the repo root
  if [[ "$glob" == "**/"* ]]; then
    [[ "$path" == ${glob#\*\*/} ]] && return 0
  fi
  return 1
}
