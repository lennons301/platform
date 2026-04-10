# Dependency Management Standard

Every project uses a single, modern package manager that is fast, deterministic, and works well in any context — local development, CI, git worktrees, and remote agent environments.

## Principle

Dependency management should be invisible friction. One tool per ecosystem, one lockfile per project, fast installs everywhere. The package manager must work equally well for a human on a laptop, an agent in a container, and a CI runner in the cloud.

Legacy packaging stacks evolved as collections of single-purpose tools (pip + virtualenv + pyenv, npm + nvm + npx). Each tool has its own configuration, its own quirks, and its own failure modes. Modern alternatives collapse this into a single binary with a single lockfile and a single mental model. Fewer tools means fewer things to install, fewer things to break, and less to document.

## Requirements

1. Every project declares its package manager in its product YAML (`package_manager` field).
2. A lockfile is committed and kept up to date. The lockfile is the source of truth for reproducible installs.
3. CI and agent environments install from the lockfile only — no resolution at deploy time.
4. Only the declared package manager is used to add, remove, or update dependencies. No mixing tools (e.g., no `npm install` in a pnpm project).
5. One-off script execution uses the package manager's built-in runner (e.g., `pnpm dlx`, `uv run`), not a separate tool.

## Why these constraints matter

**Speed.** Modern package managers (pnpm, uv) are significantly faster than their predecessors. This compounds — every `npm install` an agent runs, every CI job, every fresh worktree checkout. Faster installs mean faster feedback loops for humans and lower compute costs for agents.

**Worktree compatibility.** Git worktrees are a core workflow for parallel development and agent-driven branches. pnpm's content-addressable store means multiple worktrees share a single package cache via symlinks rather than each duplicating `node_modules`. uv's virtualenvs are lightweight and worktree-local by default.

**Determinism.** A lockfile that is always committed and always used means "works on my machine" is the same as "works everywhere." This is table stakes for agent environments where there is no human to debug a surprising dependency resolution.

**Simplicity.** One tool replaces many. Fewer things to install on a new machine, fewer things for an agent to configure, fewer docs to write.

## How to comply

See `choices/dependency-management.md` for the current tools and setup instructions.
