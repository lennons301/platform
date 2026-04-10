# Dependency Management Choice

**Current defaults:** pnpm (JavaScript/TypeScript), uv (Python)

## Decision

Every project uses a single, modern package manager that replaces fragmented legacy tooling.

| Ecosystem | Tool | Replaces | Free Tier |
|---|---|---|---|
| **JavaScript / TypeScript** | pnpm | npm, yarn, npx | Open source |
| **Python** | uv | pip, pip-tools, virtualenv, pyenv, poetry | Open source |

## Why these tools

Both tools share the same philosophy: one fast binary that replaces a collection of slower, overlapping tools.

- **pnpm** uses a content-addressable store — packages are stored once globally and symlinked into each project. This makes installs fast, saves disk space, and means git worktrees don't duplicate hundreds of megabytes of `node_modules`. It also enforces strict dependency resolution by default — you can only import packages you explicitly declared, eliminating phantom dependency bugs.

- **uv** is a single Rust binary that replaces the entire Python packaging stack (pip, pip-tools, virtualenv, pyenv). It resolves and installs dependencies an order of magnitude faster than pip, produces a deterministic `uv.lock`, and manages Python versions directly — no need for pyenv or asdf.

## Setup for a new JavaScript/TypeScript project

1. Ensure pnpm is available (installed via mise — see dev-environment standard)
2. `pnpm init` or migrate from npm: `pnpm import` (reads `package-lock.json`)
3. Delete `package-lock.json` after successful import
4. Add to `.npmrc`: `strict-peer-dependencies=true`
5. Commit `pnpm-lock.yaml`

## Setup for a new Python project

1. Ensure uv is available (installed via mise — see dev-environment standard)
2. `uv init` to create project with `pyproject.toml`
3. `uv add <package>` to add dependencies
4. Commit `uv.lock`

## Conventions

- Lockfiles (`pnpm-lock.yaml`, `uv.lock`) are always committed
- Never use `npm`, `yarn`, `pip install`, or `pip freeze` directly — the chosen tool is the only interface
- Use `pnpm dlx` (not `npx`) for one-off package execution
- Use `uv run` to execute scripts within the managed environment
- CI installs dependencies using the lockfile only (`pnpm install --frozen-lockfile`, `uv sync --frozen`)

## Canonical values

For use in `products/*.yaml` under `package_manager`:
- `pnpm` — pnpm (default for JS/TS projects)
- `uv` — uv (default for Python projects)
- `npm` — npm (legacy, non-conformant — migrate to pnpm)
