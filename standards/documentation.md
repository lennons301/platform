# Documentation Standard

Every project maintains a CLAUDE.md (or equivalent agent-readable file) as its primary technical reference.

## Requirements

A project's CLAUDE.md must include:

1. **Project overview** — one-line description of what the project is.
2. **Tech stack** — framework, database, auth, ORM, UI library.
3. **Commands** — how to run dev, build, lint, test.
4. **Project structure** — directory layout with brief descriptions.
5. **Key conventions** — patterns, rules, and non-obvious decisions specific to the project. Updated with each implementation phase.
6. **Platform context** — pointer to the platform repo for estate-wide standards and choices.

## Maintenance

Every implementation plan must include a final task: "Update the project's CLAUDE.md with any new conventions, patterns, or key files introduced in this phase."

When creating a new project's CLAUDE.md, use `templates/CLAUDE.md.template` from the platform repo as a starting point.
