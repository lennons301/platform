# Secrets Standard

All secrets are stored in a single remote provider and injected at runtime.

## Principle

Secrets are never committed to source control, never stored only on a local machine, and never hardcoded in code. A single remote provider is the source of truth. Secrets are injected into the runtime environment — the same mechanism works on any machine or in any agent container.

## Requirements

1. Every project that needs secrets must be registered with the chosen secrets provider.
2. The provider must support per-environment configuration (dev, stg, prd).
3. `.env.local` and similar files are gitignored and ephemeral — they are caches, not sources of truth.
4. Service tokens (for CI/agents) are scoped to a single environment — never use a personal token in automation.
5. Local development uses the secrets provider to inject secrets at runtime (e.g., `<provider> run -- <dev command>`).

## How to comply

See `choices/secrets-provider.md` for the current provider and setup instructions.
