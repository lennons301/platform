# Hosting Choice

**Current default:** Vercel (Hobby tier)

## Decision

All web projects deploy to Vercel. Hobby tier provides 200 projects with shared limits (100 GB bandwidth, 1M function invocations, 4 CPU-hrs/mo, 6k build mins/mo).

**Non-commercial restriction** — upgrade to Pro ($20/mo) if a project generates revenue.

## Hobby Tier Limitations

These are hard platform limits — deployments will fail or features will be unavailable if exceeded.

- **Non-commercial only.** Revenue-generating projects must be on Pro. This is a terms-of-service restriction.
- **Cron jobs: once per day maximum.** No sub-daily schedules (hourly, every 15 min, etc.). Deployment fails with invalid cron expressions. Vercel may invoke within a 1-hour window of the scheduled time.
- **Function duration: 60s max** (default 10s, configurable up to 60s). Pro allows up to 300s.
- **100 deployments per day.** Pro allows 6,000.
- **No git org repos.** Cannot connect to repositories owned by GitHub/GitLab organisations. Personal repos only.
- **No email support.** Community support only.
- **No log drains.** Cannot export logs to external services.
- **Runtime logs: 1 hour retention, 4,000 rows.** Pro gets 1 day and 100,000 rows.
- **Build limits:** 6,000 build minutes, 4 vCPUs, 8 GB memory. Pro gets 24,000 mins, 30 vCPUs, 60 GB.
- **Usage hard stop:** If monthly limits are exceeded, features are paused until the next 30-day cycle. No ability to purchase additional usage.

## When to diverge

- Self-hosted (e.g., Hetzner VPS) when the project needs Docker daemon access, persistent processes, or is infrastructure tooling rather than an end-user app.
- Document the divergence in the product YAML with a reason.

## Canonical values

For use in `products/*.yaml` under `choices.hosting`:
- `vercel-hobby` — Vercel Hobby tier (default)
- `vercel-pro` — Vercel Pro tier (revenue-generating)
- `self-hosted-hetzner` — Hetzner VPS with Docker Compose
