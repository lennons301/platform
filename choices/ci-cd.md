# CI/CD Choice

**Current default:** GitHub Actions

## Decision

All projects use GitHub Actions for CI/CD. Vercel handles deployments automatically via its GitHub integration — the workflow's job is checks, not deploys.

## Setup for a new project

### 1. Branch protection

In the repo's GitHub settings (Settings > Branches > Add rule for `main`/`master`):

- Require a pull request before merging
- Require status checks to pass before merging (select the `ci` job once it exists)
- Do not allow bypassing the above settings

### 2. Workflow file

Create `.github/workflows/ci.yml`:

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main, master]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install mise
        uses: jdx/mise-action@v2

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Lint
        run: just lint

      - name: Type check
        run: just typecheck

      - name: Test
        run: just test
```

Adapt as needed — the key point is that CI runs the same commands as local development (`just lint`, `just test`, etc.).

### 3. Secrets in CI

If the workflow needs secrets (e.g., for integration tests against a staging database):

1. Generate a scoped service token from Doppler for the `stg` environment
2. Add it as a GitHub Actions secret (`DOPPLER_TOKEN`)
3. Use `doppler run --` in the workflow to inject secrets:

```yaml
      - name: Test
        run: doppler run -- just test
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
```

Never hardcode secrets in workflow files.

### 4. Deployments

Vercel's GitHub integration handles deployments automatically:

- **PR opened/updated** — Vercel creates a preview deployment
- **Merged to main** — Vercel deploys to production

The CI workflow does not need to deploy. Its job is to gate the merge.

For projects not on Vercel (e.g., Interlude on Hetzner), add a deploy step to the workflow or use a separate `deploy.yml` triggered on push to main.

### 5. Milestone auto-close (opt-in)

GitHub gives a milestone a free "X of Y closed" progress bar, but never flips the
milestone's own state — it sits at `open`, 100% complete, until someone closes it
by hand. If you group tickets under milestones, opt in to the estate's reusable
workflow so "milestone closed" is a trustworthy done signal.

Copy `templates/milestone-autoclose.yml.tmpl` from this repo to
`.github/workflows/milestone-autoclose.yml`:

```yaml
name: Milestone Auto-Close

on:
  issues:
    types: [closed]

jobs:
  autoclose:
    permissions:
      contents: read
      issues: write
    uses: lennons301/platform/.github/workflows/milestone-autoclose.yml@master
```

Behaviour: when an issue closes, its milestone is closed **only** if no open
issues remain on it (open PRs assigned to the milestone count as open work).
It is a no-op otherwise and idempotent on an already-closed milestone, so
reopening and re-closing issues is safe.

- **Permissions** — the caller's `GITHUB_TOKEN` is enough: `issues: write` for
  the milestone (milestones live under the issues scope) and `contents: read`
  for the step that checks the platform script out. A called workflow's token
  can only be as narrow as the caller's, and naming any scope in a
  `permissions:` block drops every scope you leave out to `none` — so both
  lines above are required, not decorative. Only cross-repo milestones need a
  PAT (`gh_token` secret).
- **Opt out per milestone** — put `[no-autoclose]` anywhere in a milestone's
  description to keep a rolling milestone open.
- **Optional comment** — pass `with: {comment-on-issue: true}` to have the
  closing issue get a note explaining the auto-closure.
- **Private platform repo** — if `lennons301/platform` is not readable by the
  caller's `GITHUB_TOKEN`, pass `secrets: {platform_token: ...}` with a PAT that
  can read it; the workflow checks the platform repo out to run its script.

The logic lives in `scripts/milestone-autoclose.sh` in this repo (runnable
locally with `--dry-run`), so fixes reach every product without a copy-paste
round.

## Conventions

- The workflow file is called `ci.yml` (not `test.yml`, `checks.yml`, etc.)
- One workflow with one job is usually enough — don't split lint/test/typecheck into separate jobs unless the repo is large enough that parallelism saves meaningful time
- Pin action versions to major tags (`@v4`, not `@main`)
- Use `--frozen-lockfile` / `--frozen` so CI fails if the lockfile is out of date rather than silently resolving

## Canonical values

For use in `products/*.yaml` under `choices.ci_cd`:
- `github-actions` — GitHub Actions (default)
