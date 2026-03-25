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
| **Neon** | Local Postgres container | Neon branch (ephemeral — seed, use, delete) | `main` branch |
| **Supabase** | `supabase start` (local stack) | Share prd credentials (anon key is RLS-protected) | Production project |

**Rationale:** Neon branching is free — stg branches cost nothing when idle. Supabase free tier only allows 2 projects, so stg piggybacks on prd via the anon key (already public/RLS-safe by design).

## Canonical values

For use in `products/*.yaml` under `choices.database`:
- `neon` — Neon serverless Postgres
- `supabase` — Supabase (Postgres + auth + storage + realtime)
- `sqlite` — SQLite (for simple/single-instance apps)
