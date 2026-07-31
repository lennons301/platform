# Global Instructions

## Platform Standards

This machine's projects are governed by the platform repo at ~/code/platform/.
Read the relevant files there for standards, choices, and version targets.

Key entry points:
- standards/ — principles that apply to all projects
- choices/ — current tool selections and decision matrices
- products/<project>.yaml — this project's specific configuration
- versions/manifest.yaml — target versions for the estate

When working on a specific project, read that project's products/<name>.yaml
to understand its current choices and any intentional divergences.

## Development Workflow

- The AI dev workflow is **ticket-loop**, estate-wide: work items are generated
  with the mattpocock-skills plugin (`/grill-me`, `/to-spec`, `/to-tickets`)
  and published as GitHub issues; execution is one agent per ticket in its
  own worktree, reviewed by the separate `ticket-reviewer` agent. See
  `~/code/platform/choices/ai-dev-workflow.md` for the full flow, labels,
  and the `scripts/ticket-loop.sh` runner.
- A generated ticket is the spec — don't run a second planning ceremony on
  top of it.
- Per-ticket workflows are selected by a `workflow:<skill>` label whose name is
  the skill's own name — `workflow:tdd` runs `/tdd`. No label means use your
  judgement.
- The legacy Superpowers flow is **retired** (2026-07-31) and its plugin is
  disabled. `choices.ai_workflow: superpowers` survives only on archived
  products as a record of what they used.

## Documentation Maintenance

- Every project's technical context lives in `AGENTS.md` (agent-agnostic).
  `CLAUDE.md` references it with `@AGENTS.md` and adds only Claude-specific
  instructions if needed.
- `AGENTS.md` should be kept current via hooks as part of the development
  process — see `standards/agent-context.md` for details.
- When creating a new project, use `templates/AGENTS.md.template` and
  `templates/CLAUDE.md.template` from the platform repo.

## Architecture Diagram Maintenance

- If an implementation plan changes system boundaries, containers, external
  integrations, or deployment topology, include a task to update the
  project's architecture diagrams in its `docs/architecture/` directory.
- When creating diagrams for a new project, use `~/code/platform/templates/architecture/`
  as a starting point.
