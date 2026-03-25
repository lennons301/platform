# Platform

Estate-wide standards, choices, product registry, and conformity checks.

## Structure

- `standards/` — Principles that apply to all projects (tool-agnostic)
- `choices/` — Current tool selections implementing each standard (reviewed quarterly)
- `versions/manifest.yaml` — Target runtime/framework versions for the estate
- `products/` — One YAML file per product (metadata, choices, versions, divergences)
- `checks/` — Shell scripts that audit projects against standards and the manifest
- `templates/` — Starter files for new projects

## Quick start

```bash
# Run conformity checks against all local projects
./checks/check-estate.sh

# Check a single project
./checks/check-all.sh ~/code/lemons products/lemons.yaml

# Create GitHub Issues for gaps
./checks/create-issues.sh
```

## For agents

This repo is automatically available at:
- `/workspace/platform/` in Interlude agent containers
- `~/code/platform/` on local development machines

Read `products/<project-name>.yaml` for the current project's configuration.
Read `standards/` and `choices/` for estate-wide rules and tool decisions.
