# Database Choice

**Current options:** Neon (serverless Postgres) or Supabase (full BaaS)

## Decision matrix

| Provider | Free Tier | Best For | Tradeoff |
|---|---|---|---|
| **Neon** | 10 projects, 0.5 GB each, branching | Pure Postgres apps, lightweight | No auth/storage/realtime — just a database |
| **Supabase** | 2 active projects, 500 MB each | Full BaaS (auth, storage, realtime, edge functions) | Heavy local dev (10 Docker containers), tight project limit |

**When to choose which:**
- **Neon** when you only need a database and will handle auth/storage separately. More projects, lighter footprint.
- **Supabase** when you need the full platform (auth, storage, realtime, RLS). Accept the 2-project limit and heavier local dev.

## Environment strategy per provider

| Provider | dev | stg | prd |
|---|---|---|---|
| **Neon** | Local Postgres container **or** Neon `dev` branch | Neon branch (ephemeral — seed, use, delete) | `main` branch |
| **Supabase** | `supabase start` (local stack) | Share prd credentials (anon key is RLS-protected) | Production project |

**Rationale:** Neon branching is free — branches cost nothing when idle. Local Postgres is preferred for dev when practical (offline-capable, zero latency). A Neon dev branch is acceptable when local services are impractical (see `standards/local-development.md`). Supabase free tier only allows 2 projects, so stg piggybacks on prd via the anon key (already public/RLS-safe by design).

## Driver guidance (Neon)

Use `postgres` (postgres.js) as the underlying driver, **not** `@neondatabase/serverless`.

- `postgres` speaks standard Postgres wire protocol — works with both local containers and Neon connection strings, keeping all dev options open.
- `@neondatabase/serverless` uses Neon's websocket proxy, which **cannot connect to local Postgres**. It locks you out of local dev entirely.
- The websocket driver only matters for Edge Functions (no TCP). Since we use Fluid Compute (Node.js), standard TCP connections work fine.
- When using Drizzle, pass the `postgres` client as the driver — Drizzle handles the rest identically for local and Neon.

## Canonical values

For use in `products/*.yaml` under `choices.database`:
- `neon` — Neon serverless Postgres
- `supabase` — Supabase (Postgres + auth + storage + realtime)
- `sqlite` — SQLite (for simple/single-instance apps)
