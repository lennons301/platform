# Documentation Standard

Every project maintains an `AGENTS.md` as its primary technical reference, with tool-specific files referencing it.

## Requirements

A project's `AGENTS.md` must include:

1. **Project overview** — one-line description of what the project is.
2. **Tech stack** — framework, database, auth, ORM, UI library.
3. **Commands** — how to run dev, build, lint, test.
4. **Project structure** — directory layout with brief descriptions.
5. **Key conventions** — patterns, rules, and non-obvious decisions specific to the project.
6. **Platform context** — pointer to the platform repo for estate-wide standards and choices.

## File structure

- `AGENTS.md` — the single source of truth for project context (see the agent context standard for maintenance requirements).
- `CLAUDE.md` — contains `@AGENTS.md` plus any Claude Code-specific instructions.
- Other tool-specific files as needed (see `standards/agent-context.md`).

## Maintenance

See `standards/agent-context.md` for how `AGENTS.md` is kept current via hooks and the development workflow.

When creating a new project, use `templates/AGENTS.md.template` and `templates/CLAUDE.md.template` from the platform repo as starting points.
