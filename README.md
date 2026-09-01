# Platform

Estate-wide standards, choices, product registry, and conformity checks.

## Structure

- `standards/` — Principles that apply to all projects (tool-agnostic)
- `choices/` — Current tool selections implementing each standard (reviewed quarterly)
- `versions/manifest.yaml` — Target runtime/framework versions for the estate
- `products/` — One YAML file per product (metadata, choices, versions, divergences)
- `checks/` — Shell scripts that audit projects against standards and the manifest
- `data/conformity-snapshot.json` — Machine-readable conformity snapshot (CI-committed; consumed by create-issues and the planned estate dashboard)
- `templates/` — Starter files for new projects

## Quick start

```bash
# Run conformity checks against all local projects
./checks/check-estate.sh

# ...and also emit the machine-readable snapshot
./checks/check-estate.sh --json data/conformity-snapshot.json

# Check a single project
./checks/check-all.sh ~/code/lemons products/lemons.yaml

# Create GitHub Issues for gaps (reads the snapshot)
./checks/create-issues.sh --dry-run   # preview
./checks/create-issues.sh             # file them

# Run the shell test suite
./checks/tests/run-tests.sh

# Lint the shell sources (shellcheck over checks/ and scripts/)
./scripts/lint.sh
```

Both of the last two run on every pull request
(`.github/workflows/pr-checks.yml`), and are wrapped as `just test` / `just lint`.
`just setup` installs the pinned tools from `.mise.toml`.

This repo audits itself: `products/platform.yaml` is its own registry entry, so
`check-estate.sh` reports on it alongside the products.

## For agents

This repo is automatically available at:
- `/workspace/platform/` in Interlude agent containers
- `~/code/platform/` on local development machines

Read `products/<project-name>.yaml` for the current project's configuration.
Read `standards/` and `choices/` for estate-wide rules and tool decisions.
