# Estate Health Dashboard — Design Spec

- **Date:** 2026-06-29
- **Status:** Scoped, parked — not scheduled. Captures agreed direction; no
  implementation plan yet. Build on an explicit future "go".

## Where this fits in the platform ambition

The platform repo is the **brain** of the estate: it defines standards, choices,
version targets, and conformity checks, and (with Interlude as the **hands**)
drives an intended loop — *define → check → file issue → agent fixes → re-check →
converge*.

Today that state is legible only by running shell scripts. This dashboard makes
the estate's health **visible**: a single private pane showing, per project, both
**governance conformity** (the output of the checks) and **operational health**
(is it deployed, up, and error-free). It is the read-only "health" face of the
estate.

**Boundary (deliberate):**
- **Platform owns *health*** — conformity + operational status. This dashboard.
- **Interlude owns the *agentic* layer** — the task DAG, in-flight agent fixes,
  multi-agent workflow state. The dashboard only **deep-links** to it per project;
  it does not embed or duplicate it.

## Goal / non-goals

**Goal:** one private dashboard giving an at-a-glance, drill-downable view of
every registered product's conformity and live operational health, driven
entirely by the existing product registry.

**Non-goals (v1):**
- Historical trends / time-series (current-state only; snapshot history in git is
  a later path to it).
- Multi-user accounts or roles (single private viewer).
- Any control actions — it is read-only. Triggering fixes stays in the loop /
  Interlude.
- Embedding the agentic DAG (Interlude's job).

## Architecture

A small **Next.js 16 app** at `apps/dashboard/` in this repo, deployed to
**Vercel (Hobby)**, **private** behind **Cloudflare Access**, secrets from
**Doppler**. Two data planes:

**Plane 1 — Conformity (snapshot, CI-refreshed).** A `--json` emitter on
`check-estate.sh` writes `conformity-snapshot.json` — per project, per dimension:
pass / fail / divergence, plus version drift and the gap list. CI (extending
`.github/workflows/conformity.yml`) commits the snapshot after running checks; a
daily scheduled run keeps it fresh without a platform push. The app renders this
JSON. **The snapshot is the contract** between the checks and the dashboard — the
app never executes shell.

**Plane 2 — Operational health (live, request-time).** Server-side route handlers
(`/api/ops`) fetch from the estate's chosen providers, with tokens from
Doppler-synced env, cached ~60s to respect rate limits; a client component
refreshes on an interval. Signals:
- **Vercel** — latest production deploy state (ready/error/building), commit, when.
- **Better Stack** — up/down + recent uptime %.
- **Sentry** — unresolved error volume (last 24h).
- Plus the cheap freebies: production URL and last commit/SHA.

## Registry extension — the correlation map

The product registry stays the single source of truth. Each `products/*.yaml`
gains an optional `monitoring:` block mapping the project to provider identifiers:

```yaml
monitoring:
  vercel_project: lemons
  sentry_project: lemons
  betterstack_monitor: "123456"
  production_url: https://lemons.app
  interlude_url: https://interludes.co.uk/projects/lemons   # cross-link only
```

The dashboard renders whatever is registered — nothing hard-coded. A product with
no `monitoring:` block shows conformity only.

## Components & structure

```
apps/dashboard/
  app/
    page.tsx                 # Estate overview — grid of project cards
    projects/[name]/page.tsx # Project detail — full breakdown
    api/ops/route.ts         # Server-side: fan out to ops clients, merge, cache
  lib/
    registry.ts              # products/*.yaml -> typed Product[] (pure, no network)
    conformity.ts            # snapshot JSON -> typed ConformityReport (pure)
    ops/{vercel,sentry,betterstack}.ts  # token + id -> normalized status (server-only)
  components/                # ProjectCard, OpsBadge, ConformityGrid, StatusPill
  data/conformity-snapshot.json         # committed by CI
checks/
  check-estate.sh            # + a --json emitter (the snapshot contract)
```

Boundaries: two **pure loaders** (registry, conformity) with no network; three
**thin ops clients** that are the only network-touching, server-only modules;
`/api/ops` composes them. The app is mostly composition and rendering.

## Secrets & access

- **Doppler** project/config holds `VERCEL_API_TOKEN`, `SENTRY_API_TOKEN` +
  `SENTRY_ORG`, `BETTERSTACK_API_TOKEN`. Doppler → Vercel sync provides prod env;
  local dev uses `doppler run`.
- **Cloudflare Access** (free tier) fronts a custom domain on the Vercel project
  with an email allowlist (just the owner). Edge-level gate; app carries no auth
  of its own. Optional defense-in-depth: verify the Access JWT header in
  middleware.

## Error handling & freshness

- Ops fetches are **per-provider isolated**: one provider failing (timeout, 401,
  rate limit) degrades only its badge to "unavailable", never blanks the page.
- **Stale-while-revalidate**: show last cached ops value with a "stale" marker on
  refresh failure.
- Missing/old conformity snapshot: render with a "snapshot from <timestamp>"
  banner; warn if older than a threshold.
- Missing token: surface a clear config error scoped to that provider's section.

## Testing & local-first

- Unit tests (Vitest) for `registry.ts`, `conformity.ts`, and each ops client
  against recorded fixture responses — no live calls in CI.
- A `MOCK_OPS=1` mode serves fixture ops data so `dev` runs fully **offline**
  against the committed snapshot — satisfies the local-development standard.
- CI: Biome lint + typecheck + unit tests on PR.

## Dogfooding — the monitor monitors itself

Register the dashboard as its own product (`products/dashboard.yaml`, path
`apps/dashboard/`) so it is held to the same standards it displays: hosting
vercel-hobby, secrets doppler, ui shadcn-tailwind, linting biome, ci_cd
github-actions, observability sentry, target versions Node 22 / Next 16 / React
19 / TS 5.7. Adds C4 context + containers diagrams under its architecture dir.

*Note:* this introduces the first Node/TypeScript app into a so-far shell+YAML
repo. It stays isolated under `apps/dashboard/` with its own package manifest and
tooling so the governance tooling at the repo root is unaffected.

## Sequencing / dependencies

The only hard prerequisite is the `check-estate --json` emitter. That same
structured output is also what **Phase 0 of the conformity-loop roadmap** needs
(turning detected gaps into actionable issues). So whenever the dashboard is
built, doing the emitter first serves both tracks — that is the single real
ordering link between this initiative and the loop work. Otherwise the dashboard
is additive scope, independent of the loop roadmap.
