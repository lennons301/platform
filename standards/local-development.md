# Local Development Standard

Every project has a dedicated, isolated dev environment that is disposable and reproducible.

## Principle

**Environment separation is non-negotiable.** Dev data never touches staging or production. Dev environments are disposable — the setup to recreate them is documented and scripted.

**Offline-capable is preferred but not required.** Local services (Docker containers, native installs) give the best experience when practical. When local services are impractical (resource-constrained hosts, WSL2, CI) or the project already depends heavily on remote services, a dedicated remote dev environment (e.g. Neon branch) is acceptable.

## Requirements

1. Dev has its own isolated data store — either a local service or a dedicated remote instance (e.g. Neon dev branch). Never share a database with staging or production.
2. The dev environment secrets are managed in Doppler (or equivalent) and point to the dev data store.
3. Schema migrations and seed data can be applied against the dev database: `<package-manager> run db:migrate` and `<package-manager> run db:seed`.
4. Each project documents its dev setup in its own CLAUDE.md.

## Local services (when used)

- A `docker-compose.yml` (or equivalent) in the project root defines local service dependencies.
- Dev secrets point to localhost.

## Remote dev environments (when used)

- The remote dev instance is clearly separated from stg/prd (e.g. a named Neon branch, a separate project).
- Connection strings live in Doppler's dev config, not committed to the repo.
- The instance is disposable — it can be deleted and recreated from migrations + seed.
