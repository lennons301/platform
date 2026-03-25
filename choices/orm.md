# ORM Choice

**Current options:** Drizzle or Supabase client

## Decision matrix

| ORM | Best For | Tradeoff |
|---|---|---|
| **Drizzle** | Neon/plain Postgres apps, type-safe queries | More setup, you write your own queries |
| **Supabase client** | Supabase apps, auto-generated types from schema | Tied to Supabase, less query flexibility |

**When to choose which:**
- **Drizzle** when using Neon or plain Postgres. Pairs with Better Auth.
- **Supabase client** when using Supabase. Types generated from `supabase gen types`.

## Canonical values

For use in `products/*.yaml` under `choices.orm`:
- `drizzle` — Drizzle ORM
- `supabase-client` — Supabase JavaScript client
