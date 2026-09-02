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

## Estate conformity feed (platform repo only)

The platform repo's own `Estate Conformity Check` measures every product daily
and files gap issues. Where its snapshot goes is not a detail: `AGENTS.md` calls
`data/conformity-snapshot.json` "the machine-readable contract between checks,
create-issues.sh, and the planned estate dashboard".

It used to `git push` that file straight to `master`. Once `setup-reviewer.sh`
put branch protection on the platform repo's own default branch, every push was
rejected with `GH006` — and because the failing step ran before gap-filing, a
month of runs measured the estate and threw the result away. Nothing alarmed.

The snapshot now has two homes, written by `scripts/snapshot-publish.sh`:

| Where | Refreshed | Read by |
| --- | --- | --- |
| `automation/conformity-snapshot` branch | every run | the estate dashboard, the watchdog |
| `data/conformity-snapshot.json` on the default branch | by PR, when the conformity content changes | humans, `create-issues.sh` defaults |

The feed branch is rebuilt from the default branch each run and force-pushed, so
its diff is always exactly one file — it never needs merging or conflict
resolution, and nothing but the publisher writes to it. Consumers that want the
current picture should read that branch; the committed copy is the reviewed,
human-facing record and moves only when the *conformity content* changes, not
when a timestamp does.

The PR is opened with auto-merge armed. It is deliberately *gate-clear* — it
touches only `data/conformity-snapshot.json`, which matches no glob in
`standards/review-gates.yaml` — so one approval lands it and nobody has to come
back to press merge. Branch protection still requires that approval; arming
removes the second human step, not the first. A test pins the gate-clearance,
because a gate glob that swallowed the snapshot path would re-stall the
committed copy in exactly the silent way this whole section exists to prevent.

Merging that PR is itself a push to the default branch, which would start the
conformity job again. The old direct-push path used `[skip ci]`; a merge commit
is composed by GitHub and varies with the merge strategy, so the guard lives on
the trigger instead — `paths-ignore: ['data/**']`, which makes a snapshot-only
push the job's own echo regardless of how it was merged.

Four rules hold this together, and each one is a test in `checks/tests/`:

- **Gap-filing is not downstream of bookkeeping.** "Create issues for gaps" runs
  before the snapshot is persisted, and persistence runs under `if: always()`.
  Either can fail without suppressing the other; a persist failure still fails
  the run.
- **Silence is a failure state.** `Estate Conformity Watchdog` is a *separate*
  daily workflow, because a check inside the conformity job cannot notice a job
  that never ran. It reads the feed branch and calls
  `scripts/conformity-alarm.sh`, which files exactly one `ready-for-human`
  tracking issue once the snapshot passes 48h old and closes it when fresh
  snapshots resume. The conformity workflow calls the same script on `failure()`.
- **One open issue, no comment stream.** A repeat alarm is a no-op. An alarm
  that comments daily is an alarm people mute, which is how a month went by.
- **The publisher's output cannot re-trigger the publisher.** The snapshot PR
  merge is filtered out of the `push` trigger by path, so the feed does not
  chase its own tail.

## Conventions

- The workflow file is called `ci.yml` (not `test.yml`, `checks.yml`, etc.)
- One workflow with one job is usually enough — don't split lint/test/typecheck into separate jobs unless the repo is large enough that parallelism saves meaningful time
- Pin action versions to major tags (`@v4`, not `@main`)
- Use `--frozen-lockfile` / `--frozen` so CI fails if the lockfile is out of date rather than silently resolving

## Canonical values

For use in `products/*.yaml` under `choices.ci_cd`:
- `github-actions` — GitHub Actions (default)
