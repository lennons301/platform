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
