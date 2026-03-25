# Auth Choice

**Current options:** Better Auth, Supabase Auth, Clerk, Auth.js v5

## Decision matrix

| Provider | Free Tier | Best For | Tradeoff |
|---|---|---|---|
| **Better Auth** | Unlimited (OSS) | Full control, data in your DB, Drizzle-native | You own the complexity; newer ecosystem |
| **Supabase Auth** | 50k MAU (bundled) | Apps already on Supabase | Tied to Supabase project |
| **Clerk** | 50k MAU | Fastest DX, drop-in components | Vendor lock-in, users not in your DB |
| **Auth.js v5** | Unlimited (OSS) | Battle-tested, huge community | More manual wiring |

**When to choose which:**
- **Better Auth** when using Neon/Drizzle. Auth data lives alongside app data.
- **Supabase Auth** when already on Supabase. Don't fight the platform.
- **Clerk** when shipping speed matters more than data ownership.
- **Auth.js** when you want the most proven option and don't mind setup.

## Canonical values

For use in `products/*.yaml` under `choices.auth`:
- `better-auth` — Better Auth (OSS, data in your DB)
- `supabase-auth` — Supabase Auth (bundled with Supabase)
- `clerk` — Clerk (managed, drop-in components)
- `authjs` — Auth.js v5
- `none` — No auth required (single-user tools, infrastructure)
