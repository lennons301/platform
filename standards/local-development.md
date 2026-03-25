# Local Development Standard

Every project uses local services for development.

## Principle

Local development never depends on remote databases or services. If your laptop is offline, you can still develop. Local services are disposable — the setup to recreate them is documented and scripted.

## Requirements

1. Every project has a `docker-compose.yml` (or equivalent) in the project root that defines local service dependencies.
2. The dev environment secrets point to local services (localhost).
3. Schema migrations and seed data can be applied against the local database: `<package-manager> run db:migrate` and `<package-manager> run db:seed`.
4. Remote databases are never used for local development.
5. Each project documents its local setup in its own CLAUDE.md.
