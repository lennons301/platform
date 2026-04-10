# Development Environment Standard

Every project's development environment is reproducible from a single checkout.

## Principle

A developer — human or agent — should be able to go from a fresh clone to a working environment in minutes, on any machine, with no tribal knowledge. The same setup works on a laptop, in a devcontainer, on a remote VPS, or inside an agent runtime like Interlude. If the machine dies, nothing is lost — the environment definition lives in the repo.

## Requirements

1. Every project declares its required runtimes and tool versions in a version manager config file checked into the repo root. No tool versions are assumed to be pre-installed globally.
2. Every project has a command runner config in the repo root with named commands for common operations (dev, test, lint, setup, db:migrate, db:seed).
3. A fresh clone can reach a working environment by installing tool versions and running a single setup command. The fewer steps, the better.
4. The command runner is self-documenting — a list command shows every available operation without reading source files.
5. Each project documents any additional setup steps in its CLAUDE.md — but the goal is that the version manager and command runner cover everything.

## Why this matters

- **Reproducibility.** Pinned tool versions in the repo mean two developers (or an agent) checking out the same commit get the same environment. No "works on my machine."
- **Portability.** The setup must work on a fresh laptop, inside a container, or on a remote agent runtime. No dependency on a specific developer's machine state.
- **Discoverability.** A single list command shows every available operation. No need to grep through package.json scripts, read a README, or ask someone.
- **Agent compatibility.** Remote agents and CI runners have no human to debug a broken setup. The environment must bootstrap reliably with minimal assumptions — ideally just the version manager and Docker.

## Devcontainers (optional)

Projects may include a `.devcontainer/` configuration for remote development environments. When present, the devcontainer should use the same version manager config and command runner as local development — not a parallel setup path.

## How to comply

See `choices/dev-environment.md` for the current tools and setup instructions.
