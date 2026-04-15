# Hosting Choice

**Current default:** Vercel (Hobby tier)

## Decision

All web projects deploy to Vercel. Hobby tier provides 200 projects with shared limits (100 GB bandwidth, 1M function invocations, 4 CPU-hrs/mo, 6k build mins/mo).

**Non-commercial restriction** — upgrade to Pro ($20/mo) if a project generates revenue.

## Hobby Tier Limitations

- **Cron jobs:** Once per day maximum. No sub-daily schedules (hourly, every 15 min, etc.). Vercel may invoke within a 1-hour window of the scheduled time. Upgrade to Pro for more frequent cron.

## When to diverge

- Self-hosted (e.g., Hetzner VPS) when the project needs Docker daemon access, persistent processes, or is infrastructure tooling rather than an end-user app.
- Document the divergence in the product YAML with a reason.

## Canonical values

For use in `products/*.yaml` under `choices.hosting`:
- `vercel-hobby` — Vercel Hobby tier (default)
- `vercel-pro` — Vercel Pro tier (revenue-generating)
- `self-hosted-hetzner` — Hetzner VPS with Docker Compose
