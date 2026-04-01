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

- Every implementation plan must include a final task: "Update the project's
  CLAUDE.md with any new conventions, patterns, or key files introduced in
  this phase." (The project's CLAUDE.md, not this global one.)
- When creating a new project's CLAUDE.md, include a "Key Conventions" section.

## Architecture Diagram Maintenance

- If an implementation plan changes system boundaries, containers, external
  integrations, or deployment topology, include a task to update the
  project's architecture diagrams in its `docs/architecture/` directory.
- When creating diagrams for a new project, use `~/code/platform/templates/architecture/`
  as a starting point.
