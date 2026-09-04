# Agent Context Standard

Every project maintains an `AGENTS.md` file as its primary technical reference for AI agents and developers.

## Principle

Agent context is the single file an AI agent (or a new developer) reads to understand a project. It must be accurate, current, and agent-agnostic. The file is called `AGENTS.md` — not tied to any specific tool — so it works with Claude Code, GitHub Copilot, Gemini, Cursor, and whatever comes next. Tool-specific files (e.g., `CLAUDE.md`) reference `AGENTS.md` rather than duplicating its content.

## Requirements

1. Every project has an `AGENTS.md` in the project root containing the project's technical context (see the documentation standard for required sections).
2. `AGENTS.md` is kept up to date as part of the normal development process — not as an afterthought or a periodic cleanup task.
3. Updates to `AGENTS.md` are incorporated into the existing structure of the file. New conventions replace or extend existing sections — they are never appended as a changelog or development log at the bottom.
4. Tool-specific files (`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, etc.) use their tool's include mechanism to reference `AGENTS.md` and add only tool-specific configuration.

## Keeping AGENTS.md current

The goal is that `AGENTS.md` always reflects the project as it is right now — not as it was when someone last remembered to update the docs.

**The ticket-loop is the enforcement mechanism.** Every implement pass reads `AGENTS.md` before writing code and is instructed to fold any relevant change back into it in the same PR; the ticket-reviewer checks that a PR which changed structure, commands, dependencies, conventions or configuration left `AGENTS.md` describing the repo as it now is, and requests changes if it did not. Work done outside the loop carries the same duty, by hand. Hooks (post-commit, pre-push, or an agent hook) are optional — a repo may add one as a reminder, but none is required and none is checked. "Relevant" typically means changes to:

- Project structure (new directories, moved files)
- Commands (new scripts, changed build steps)
- Dependencies (new libraries, changed tools)
- Conventions (new patterns, architectural decisions)
- Configuration (new environment variables, changed providers)

The update **rewrites the affected sections** of `AGENTS.md` to reflect current state. It must not append a dated entry, add a changelog section, or leave stale content above with corrections below. The file should read as if it was written today. Development history — phases, roadmaps, what shipped when — belongs in a linked doc, not in `AGENTS.md`. Size limits and the README requirement are in the documentation standard.

## What goes where

| File | Contains | Updated |
|---|---|---|
| `AGENTS.md` | Project overview, tech stack, commands, structure, conventions, platform context | Continuously, by the ticket-loop implement pass (reviewer-checked) |
| `CLAUDE.md` | `@AGENTS.md` reference + any Claude Code-specific instructions | Rarely — only when Claude-specific behaviour changes |
| `GEMINI.md` | `@AGENTS.md` reference + any Gemini-specific instructions | Rarely |
| `.github/copilot-instructions.md` | Copilot-specific instructions, referencing AGENTS.md content | Rarely |

## How to comply

1. Use `templates/AGENTS.md.template` from the platform repo as a starting point for new projects.
2. Nothing to install: the ticket-loop prompts carry the requirement. Working outside the loop, update it yourself in the same change.
3. Ensure tool-specific files reference `AGENTS.md` rather than duplicating content.
