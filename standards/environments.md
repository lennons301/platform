# Environment Standard

Every project maintains three isolated environments.

## Principle

Code runs in exactly one of: dev, stg, or prd. Each environment has its own secrets, its own data, and its own deployment target. No environment's credentials should be usable in another.

## Requirements

- **dev**: Local services only. Disposable. If the machine dies, recreate by starting local services again.
- **stg**: Remote non-production services. Safe to wipe and reset. Used by CI, remote agents, and PR reviewers.
- **prd**: Production. Only production deployments read from it. Never use production credentials in dev or stg.

## Rules

1. Each environment has its own set of secrets, managed by the chosen secrets provider.
2. Dev always points to local services (localhost). Stg and prd point to remote services.
3. Never use prd secrets in dev or stg. Never use dev (localhost) secrets in deployed environments.
4. Environment-specific configuration is injected at runtime, not hardcoded.

## How to comply

See `choices/secrets-provider.md` for the current secrets management solution.
See `choices/databases.md` for per-provider environment strategy (how each database provider maps to dev/stg/prd).
