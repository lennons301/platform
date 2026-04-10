# Linting Standard

Every project enforces consistent code style through automated linting and formatting, checked before code leaves the developer's machine.

## Principle

Code style debates are settled once, encoded in configuration, and enforced automatically. Linting runs before every commit via a pre-commit hook — by the time code reaches CI, it has already been checked. CI runs linting too, but as a backstop, not the primary gate.

## Requirements

1. Every project has a linter and formatter configured for its language(s).
2. A pre-commit hook runs the linter and formatter on staged files before every commit. Commits that fail linting are blocked.
3. The linting command is available via the project's command runner (e.g., `just lint`).
4. CI runs the same linting check on every PR as a backstop.
5. Linter configuration is checked into the repo — no reliance on editor settings or developer preference.

## How to comply

See `choices/linting.md` for the current tools and setup instructions.
