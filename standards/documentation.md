# Documentation Standard

Every project has two front doors: a `README.md` for people and an `AGENTS.md` for agents (and for people who want the full technical picture). Tool-specific files point at `AGENTS.md`; nothing duplicates it.

## README.md — human onboarding

`README.md` is what a person sees first on GitHub, so it is written for someone who has never seen the project. It must:

1. Say what the project is, in one paragraph.
2. List the prerequisites: tool-version manager, Docker, secrets CLI, accounts or access someone has to ask for.
3. Show how to get running locally and how to run the tests.
4. Point to `AGENTS.md` for the technical reference.

Keep it short. The README is an entry point; detail lives in `AGENTS.md` and `docs/`. Scaffold boilerplate left in place (Lovable, `create-next-app`, Vite templates) counts as no README.

## AGENTS.md — technical reference

A project's `AGENTS.md` must include:

1. **Project overview** — one-line description of what the project is.
2. **Tech stack** — framework, database, auth, ORM, UI library.
3. **Commands** — how to run dev, build, lint, test.
4. **Project structure** — directory layout with brief descriptions.
5. **Key conventions** — patterns, rules, and non-obvious decisions specific to the project.
6. **Platform context** — pointer to the platform repo for estate-wide standards and choices.

### Size

`AGENTS.md` is loaded into every agent session, so its size is a cost paid on every task. Keep it under about 48 KB, and keep lines under 2,000 characters — a longer line is a paragraph that has stopped being a convention. A section that has grown into an essay (a per-file inventory, the states a preview gallery covers, an annual operational ritual) moves to a file under `docs/`, leaving a summary and a link. Development history (phases, roadmaps, what shipped when) belongs in a linked doc too, never in `AGENTS.md` — see `standards/agent-context.md`.

## Tool-specific files

- `CLAUDE.md` — `@AGENTS.md`, plus Claude Code-specific instructions only.
- `GEMINI.md`, `.github/copilot-instructions.md`, and whatever comes next — the same shape, using that tool's own include mechanism.

A tool file is a thin pointer: it references `AGENTS.md`, contains none of the sections listed above, and stays short. Facts about the product that happen to name a provider (an API the app calls, the harness it runs) belong in `AGENTS.md`; the tool file is only for how that tool should behave in this repo.

## Enforcement

`checks/check-documentation.sh` fails on: no `AGENTS.md`; a missing required section or platform pointer; no `README.md` or scaffold boilerplate; no `CLAUDE.md`; a tool file that does not reference `AGENTS.md`, repeats one of its sections, or runs past a few dozen lines. It warns, without counting a gap, when `AGENTS.md` is over the size or line-length limits.

## Maintenance

See `standards/agent-context.md` for how `AGENTS.md` is kept current through the development workflow.

When creating a new project, use `templates/AGENTS.md.template` and `templates/CLAUDE.md.template` from the platform repo as starting points.
