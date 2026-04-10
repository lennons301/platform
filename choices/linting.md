# Linting Choice

**Current defaults:** Biome (JavaScript/TypeScript), ruff (Python)

## Decision

| Ecosystem | Tool | Replaces |
|---|---|---|
| **JavaScript / TypeScript** | Biome | ESLint + Prettier |
| **Python** | ruff | flake8 + isort + black |

Both tools are fast, single-binary linter-and-formatters that replace multiple slower tools. Same philosophy as pnpm/uv — one tool, fewer moving parts.

## Pre-commit hooks

The primary enforcement mechanism is a pre-commit hook using **lint-staged** (JS/TS) or equivalent, triggered by **husky** or **lefthook**.

Recommended setup (JS/TS project):

1. `pnpm add -D husky lint-staged`
2. `pnpm exec husky init`
3. Configure `.husky/pre-commit` to run `pnpm exec lint-staged`
4. Add to `package.json`:

```json
{
  "lint-staged": {
    "*.{js,ts,jsx,tsx,json,css}": "biome check --write"
  }
}
```

## Setup for a new JavaScript/TypeScript project

1. `pnpm add -D @biomejs/biome`
2. `pnpm exec biome init` to create `biome.json`
3. Configure pre-commit hooks as above
4. Add to `justfile`: `lint: pnpm exec biome check --write .`

## Setup for a new Python project

1. `uv add --dev ruff`
2. Add `[tool.ruff]` section to `pyproject.toml`
3. Configure pre-commit hooks (use the `pre-commit` framework or a shell hook calling `ruff check --fix && ruff format`)
4. Add to `justfile`: `lint: uv run ruff check --fix . && uv run ruff format .`

## Canonical values

For use in `products/*.yaml` under `choices.linting`:
- `biome` — Biome (default for JS/TS projects)
- `ruff` — ruff (default for Python projects)
- `biome-ruff` — Both (for mixed-language projects)
- `none` — No linting (non-conformant)
