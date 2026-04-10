# Development Environment Choice

**Current defaults:** mise (version manager), just (command runner)

## Decision

Every project uses mise to manage runtime/tool versions and just as its command runner.

## Why these tools

**mise** — runtime and tool version manager. Replaces nvm, pyenv, asdf. Reads `.mise.toml` from the project root and activates the correct versions of Node, pnpm, Python, uv, and any other tools. Auto-activates on `cd` when the shell hook is installed. Fast, single binary, works in containers.

**just** — command runner. Replaces Makefiles, npm scripts-as-documentation, and ad-hoc shell scripts. A `justfile` provides a consistent interface across all projects. Commands are self-documenting (`just --list`), support arguments and dependencies, and use normal shell syntax (no tab sensitivity).

## Setup for a new project

1. Add a `.mise.toml` to the project root pinning required tools:

```toml
[tools]
node = "22"
pnpm = "9"
```

2. Add a `justfile` with at least the standard commands:

| Command | Purpose |
|---|---|
| `just setup` | Full first-time setup (install deps, start services, migrate, seed) |
| `just dev` | Start the development server |
| `just test` | Run the test suite |
| `just lint` | Run linters and formatters |
| `just db:migrate` | Apply database migrations |
| `just db:seed` | Seed the local database |

Additional project-specific commands are encouraged.

3. Verify that `mise install && just setup` works from a fresh clone.

## Canonical values

For use in `products/*.yaml` under `choices.dev_environment`:
- `mise-just` — mise + just (default)
