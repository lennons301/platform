# Secrets Provider Choice

**Current default:** Doppler

## Decision

All projects use Doppler as the canonical secrets store.

## Setup for a new project

1. Create a Doppler project at https://dashboard.doppler.com
2. Add secrets for each config: `dev` (local services), `stg` (remote non-prod), `prd` (production)
3. For local development: `doppler setup` once per repo, then `doppler run -- <dev command>`
4. For Interlude agents: generate a service token scoped to `stg`, set it on the project in Interlude
5. For Vercel production: sync Doppler `prd` to Vercel env vars (or use Doppler's Vercel integration)

## Conventions

- `.env.local` is gitignored and ephemeral — Doppler is the source of truth
- Use `doppler run -- <command>` to inject secrets at runtime
- Service tokens (for CI/agents) are scoped to a single environment — never use a personal token in automation
- If a project needs secrets, it must have a Doppler project. No exceptions.

## Canonical values

For use in `products/*.yaml` under `choices.secrets`:
- `doppler` — Doppler (default, fully configured)
- `env-file` — Manual .env file (for intentional divergences only)
- `pending-migration` — Not yet migrated to Doppler (non-conformant)
