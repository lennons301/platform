# Platform

Estate-wide governance repo: standards, choices, conformity checks, and templates
for all projects.

## Tech Stack

- Shell (bash) for conformity checks
- YAML (parsed with yq) for product registry and version manifest
- GitHub Actions for CI/CD
- PlantUML + C4-PlantUML for architecture diagrams

## Project Structure

```
standards/           — estate-wide principles (documentation, testing, secrets, etc.)
choices/             — current tool selections with decision matrices
products/            — per-project YAML registry (choices, versions, divergences)
versions/            — runtime/framework version manifest
checks/              — conformity check scripts (shell)
templates/           — starter files for new projects
scripts/             — setup and sync utilities
.github/workflows/   — CI automation (estate-wide conformity audits)
docs/                — presentations and design specs
```

## Commands

```bash
# Run conformity checks against a single project
./checks/check-all.sh <project-path> <product-yaml-path>

# Run conformity checks across the entire estate
./checks/check-estate.sh [--repos-dir <path>]

# Individual checks
./checks/check-documentation.sh <project-path> <product-yaml>
./checks/check-secrets.sh <project-path> <product-yaml>
./checks/check-versions.sh <project-path> <product-yaml>
./checks/check-environments.sh <project-path> <product-yaml>
./checks/check-architecture.sh <project-path> <product-yaml>

# Sync global Claude Code instructions from this repo to ~/.claude/CLAUDE.md
./scripts/sync-claude-md.sh           # interactive (shows diff, prompts)
./scripts/sync-claude-md.sh --force   # non-interactive
```

## Key Conventions

- Check scripts source `checks/lib.sh` for shared helpers (colours, YAML parsing, divergence detection)
- Exit code from checks = gap count (enables aggregation)
- Divergences documented in product YAML are recognised and marked `✓*`
- Product YAMLs are the source of truth for each project's choices and versions
- Version targets are floors, not pins (actual >= target is conformant)
- Templates use `{{PLACEHOLDER}}` syntax for project-specific values

## Platform Context

This is the platform repo itself. Global Claude Code instructions at `~/.claude/CLAUDE.md`
point all projects here for standards and choices.
