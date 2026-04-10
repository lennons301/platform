# CI/CD Standard

Every project has automated checks on pull requests and a clear path from merge to production.

## Principle

Code is never merged without passing automated checks. Deployments are automated and predictable — merging to the main branch is the only manual step. The CI pipeline catches what pre-commit hooks and local development missed.

## Requirements

1. Every PR triggers automated checks before merge is allowed. At minimum: linting, type checking, and tests.
2. The main branch is protected — direct pushes are blocked, PRs require passing checks.
3. Preview deployments are created automatically for every PR (where the hosting platform supports it).
4. Merging to the main branch triggers a production deployment automatically. No manual deploy steps.
5. CI installs dependencies from the lockfile only — no dependency resolution at build time.

## Guidance

- Keep CI fast. Developers and agents should not wait more than a few minutes for feedback.
- CI should run the same commands as local development (the same lint, test, and type-check commands documented in the justfile/CLAUDE.md).
- Secrets in CI are injected from the secrets provider using scoped service tokens — never hardcoded in workflow files.
- The specific CI platform is a project-level decision (GitHub Actions is the current default for this estate), but the requirements above apply regardless of platform.
