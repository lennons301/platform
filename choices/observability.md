# Observability Choice

**Current default:** Sentry (errors, traces, releases) + Better Stack (uptime, heartbeats)

## Decision

All production applications use a two-tool observability stack:

| Tool | Responsibility |
|------|----------------|
| **Sentry** | Errors and exceptions (frontend + backend), traces, releases, source maps |
| **Better Stack Uptime** | External uptime monitoring + cron heartbeat monitors |

The two are complementary: Sentry only sees what runs inside the app, so it cannot detect outages, DNS failures, SSL expiry, or a cron that never fires. Better Stack pings from outside and tracks heartbeats. Sentry alerts on what broke; Better Stack alerts on what didn't run at all.

## Why this split

- **Sentry alone is insufficient.** If the app is unreachable, Sentry has nothing to report.
- **Better Stack heartbeats over Sentry Cron Monitors.** Sentry's free tier limits cron monitors per organisation, which constrains adding more services. Better Stack's free tier lets each heartbeat count as one of ten monitors, scaling cleanly to several apps in the estate.
- **One alerting destination per tool.** Both tools push to email + their own mobile apps; route customer-impacting alerts to all stakeholders, code-only alerts to engineers.

## Free-tier capacity (estate-wide)

| Tool | Free tier | Pooling |
|------|-----------|---------|
| Sentry Developer | 5K errors / 10K perf units / 50 replays / month, 1 user, 1 cron monitor | Quotas pooled across all projects in the org. |
| Better Stack Uptime | 10 monitors, 3-min cadence, status pages, heartbeats | Per workspace. Heartbeats count toward the 10. |

The first free-tier ceiling we'll hit as the estate grows: Sentry's 1-user limit (any second collaborator forces Team plan, currently $26/mo). Performance units are a softer ceiling — keep `tracesSampleRate` ≤ 0.1.

## Setup for a new project

1. **Sentry**
   - Create a project at https://sentry.io under the existing organisation
   - Install: `pnpm add @sentry/nextjs` (or framework equivalent)
   - Run wizard: `pnpm exec @sentry/wizard@latest -i nextjs`
   - Store secrets in Doppler: `SENTRY_DSN` (all configs), `SENTRY_AUTH_TOKEN` (build only)
   - Set `tracesSampleRate: 0.1`, `sendDefaultPii: false`
   - Tie releases to commit SHA via the platform's deploy env var (e.g. `VERCEL_GIT_COMMIT_SHA`)
   - Upload source maps on every deploy
   - Exclude internal/admin routes (e.g. CMS Studio) from tracing

2. **Better Stack**
   - Add an HTTP monitor for the public homepage (3-min cadence)
   - Add an HTTP monitor for `/api/health` returning 200 only when the database round-trips (3-min cadence)
   - For each cron job, add a heartbeat monitor; have the cron handler `POST` to its heartbeat URL on success
   - Configure on-call/escalation via the Better Stack mobile app

3. **Alert routing**
   - Define which alerts are "customer-impacting" (e.g. paid-flow 5xx, site down, email-send failure for a real customer) and route to business stakeholders + engineers
   - Code-only errors and infrastructure noise route to engineers only
   - In Sentry, tag customer-impacting code paths explicitly (e.g. `Sentry.setTag('severity', 'customer')` in payment / checkout / email handlers) and use that tag in alert rules

## Failure-mode coverage

| Failure mode | Detected by |
|--------------|-------------|
| Unhandled exception (FE or BE) | Sentry |
| Frontend JS error breaking a flow | Sentry (FE SDK) |
| Webhook 5xx during paid flow | Sentry, tagged `severity:customer` |
| Email send failed (third-party API error) | Sentry, tagged `severity:customer` |
| Cron didn't run on schedule | Better Stack heartbeat (missing check-in) |
| Cron threw inside the handler | Sentry |
| Site unreachable / DNS / SSL expiry | Better Stack uptime monitor |
| Database round-trip failure | Better Stack uptime monitor on `/api/health` |

## Scope

This choice covers **error tracking, uptime, and cron reliability**. It does not yet cover:

- Structured log retention beyond the host's default (Vercel's runtime log retention is 1 hour on Hobby — log forwarding to Axiom or Better Stack Logs is a future expansion)
- Real-user monitoring / Web Vitals beyond what the host provides natively
- Business metrics / product analytics (PostHog, Mixpanel, or simple SQL queries against the operational database)
- Distributed tracing across multiple services (single-service estates don't need it yet)

These are documented as "future expansion" rather than required.

## Canonical values

For use in `products/*.yaml` under `choices.observability`:

- `sentry-betterstack` — Sentry + Better Stack (default)
- `sentry-only` — Sentry only (legacy / minimal — does not detect outages)
- `none` — No observability (non-conformant)
