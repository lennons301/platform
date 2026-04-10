# Observability Choice

**Current default:** Sentry

## Decision

All production applications report errors and performance data to Sentry.

## Why Sentry

- Generous free tier (5K errors, 10K performance transactions/month) — covers a small estate comfortably.
- First-party SDKs for Next.js, Node, Python — low setup friction.
- Source maps, stack traces, breadcrumbs, and release tracking out of the box.
- Alerts on new/regressing issues without configuration.

## Setup for a new project

1. Create a Sentry project at https://sentry.io
2. Install the SDK (`pnpm add @sentry/nextjs` for Next.js projects)
3. Run the Sentry wizard: `pnpm exec @sentry/wizard@latest -i nextjs`
4. Store the DSN in the secrets provider (Doppler) — never hardcode it
5. Verify errors appear in the Sentry dashboard

## Scope

This choice currently covers **error tracking**. As the estate grows, this document may expand to include:
- Uptime monitoring
- Structured logging
- Performance budgets / Core Web Vitals tracking

For now, the minimum bar is: production errors are captured and visible in Sentry.

## Canonical values

For use in `products/*.yaml` under `choices.observability`:
- `sentry` — Sentry (default)
- `none` — No observability (non-conformant)
