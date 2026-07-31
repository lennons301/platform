#!/usr/bin/env bash
# Check domain-modelling conformity for a single project.
# Usage: check-domain-modelling.sh <project-path> <product-yaml-path>
#
# See standards/domain-modelling.md. Verifies the repo has a domain model —
# a CONTEXT.md naming the project's terms.
#
# ADRs are deliberately NOT counted. docs/adr/ is created lazily and an ADR
# is only written when a decision is hard to reverse, surprising, and a real
# trade-off — so zero ADRs is a legitimate steady state. What an empty
# docs/adr/ cannot tell you on its own is WHICH zero it is: "nobody ever
# modelled this domain" or "we modelled it and nothing met the ADR bar".
# CONTEXT.md is what disambiguates. Its presence is the assertion that domain
# modelling ran, and therefore that zero ADRs was the right answer at that
# point. So CONTEXT.md is the whole check, and ADRs are never required.

source "$(dirname "$0")/lib.sh"
require_yq

PROJECT_PATH="$1"
PRODUCT_YAML="$2"

if has_divergence "$PRODUCT_YAML" "domain-modelling"; then
  echo -e "  domain-modelling: ${DIVG} (intentional divergence)"
  exit 0
fi

# CONTEXT.md and docs/adr/ are ticket-loop artifacts, and the remedy for a gap
# (/grill-with-docs, /wayfinder) is not part of the superpowers flow — filing
# it against a superpowers repo would be an issue it cannot action.
WORKFLOW=$(yaml_get "$PRODUCT_YAML" '.choices.ai_workflow')
if [ "$WORKFLOW" != "ticket-loop" ]; then
  echo -e "  domain-modelling: ${DIVG} (n/a: ${WORKFLOW:-no} workflow)"
  exit 0
fi

# Multi-context repos keep per-context CONTEXT.md files and index them from a
# root CONTEXT-MAP.md; the map's presence means the modelling has happened.
if [ -f "$PROJECT_PATH/CONTEXT-MAP.md" ]; then
  echo -e "  domain-modelling: ${PASS} (multi-context via CONTEXT-MAP.md)"
  exit 0
fi

if [ ! -f "$PROJECT_PATH/CONTEXT.md" ]; then
  echo -e "  domain-modelling: ${FAIL} (no CONTEXT.md — no domain model has been recorded)"
  exit 1
fi

# CONTEXT.md is created lazily "when the first term is resolved", so a
# conformant one has at least one term by construction. One is the bar: this
# guards against an empty stub without dictating how full a glossary must be.
TERMS=$(grep -cE '^\*\*.+\*\*:' "$PROJECT_PATH/CONTEXT.md" || true)

if [ "$TERMS" -lt 1 ]; then
  echo -e "  domain-modelling: ${FAIL} (CONTEXT.md defines no terms — expected at least one '**Term**:' entry)"
  exit 1
fi

echo -e "  domain-modelling: ${PASS} ($TERMS terms defined; ADRs not required)"
exit 0
