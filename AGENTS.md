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
templates/           — starter files for new projects; templates/agents/ holds
                       canonical agent definitions synced via scripts/sync-agents.sh
scripts/             — setup and sync utilities
.github/workflows/   — CI automation (estate-wide conformity audits)
docs/                — presentations and design specs
```

## Commands

```bash
# Run conformity checks against a single project
./checks/check-all.sh <project-path> <product-yaml-path>

# Run conformity checks across the entire estate
./checks/check-estate.sh [--repos-dir <path>] [--json <snapshot-path>]

# File GitHub Issues for gaps recorded in the snapshot
./checks/create-issues.sh [--dry-run] [--snapshot <path>]

# Run the shell test suite for the check tooling
./checks/tests/run-tests.sh

# Individual checks
./checks/check-documentation.sh <project-path> <product-yaml>
./checks/check-secrets.sh <project-path> <product-yaml>
./checks/check-versions.sh <project-path> <product-yaml>
./checks/check-environments.sh <project-path> <product-yaml>
./checks/check-architecture.sh <project-path> <product-yaml>
./checks/check-domain-modelling.sh <project-path> <product-yaml>

# Sync global Claude Code instructions from this repo to ~/.claude/CLAUDE.md
./scripts/sync-claude-md.sh           # interactive (shows diff, prompts)
./scripts/sync-claude-md.sh --force   # non-interactive

# Sync canonical agent definitions (templates/agents/) to ~/.claude/agents/
./scripts/sync-agents.sh [--force]

# Run one agent attempt on one ready-for-agent issue of a project repo
# (see choices/ai-dev-workflow.md for the full ticket-loop workflow)
./scripts/ticket-loop.sh --repo-dir <project-path> [--issue N] [--afk]

# Onboard a repo to the separate-reviewer-identity flow (idempotent): branch
# protection, auto-merge, human-signoff + workflow:* labels, reviewer collaborator
./scripts/setup-reviewer.sh --repo-dir <project-path>
```

## Key Conventions

- Check scripts source `checks/lib.sh` for shared helpers (colours, YAML parsing, divergence detection)
- Exit code from checks = gap count (enables aggregation)
- Divergences documented in product YAML are recognised and marked `✓*`
- Product YAMLs are the source of truth for each project's choices and versions
- Version targets are floors, not pins (actual >= target is conformant)
- Templates use `{{PLACEHOLDER}}` syntax for project-specific values
- Agent context lives in `AGENTS.md` (agent-agnostic); `CLAUDE.md` references it via `@AGENTS.md`
- The estate's AI dev workflow is a per-product choice (`choices.ai_workflow`):
  `ticket-loop` (default — see `choices/ai-dev-workflow.md`) or `superpowers` (legacy)
- Ticket-loop PRs auto-merge on reviewer approval unless a deterministic review
  gate matches (`standards/review-gates.yaml` + per-repo
  `docs/agents/review-gates.yaml`, evaluated by `scripts/review-gates-lib.sh`);
  gated PRs carry the `human-signoff` label and wait for a human merge
- The review pass runs as the reviewer machine account; its PAT lives in
  Doppler (`platform`/`prd`/`REVIEWER_GH_TOKEN`) — see "Reviewer identity &
  onboarding" in `choices/ai-dev-workflow.md`
- Per-ticket workflows are selected by a `workflow:<skill>` label whose name is
  the mattpocock skill name (`workflow:tdd` → `/tdd`) — no menu files exist by
  design; the model-invocable skills are the menu
- `wayfinder:*` issues are decision tickets and are refused by
  `scripts/ticket-loop.sh` — filtered from the auto-pick, an error via `--issue`
- Check output line format (`  <dim>: ✓|✗|✓* (details)`) is a parsed contract — changes require updating `parse_check_output` in checks/lib.sh and checks/tests/test-parse.sh
- Adding a check means registering it in `checks/check-all.sh` **and** bumping the dimension count in `checks/tests/test-snapshot.sh`
- `create-issues.sh` routes gaps by dimension: mechanical ones get `platform-upgrade`, ones needing a human decision get `ready-for-human` (see `issue_label`)
- `data/conformity-snapshot.json` is the machine-readable contract between checks, create-issues.sh, and the planned estate dashboard

## Platform Context

This is the platform repo itself. Global Claude Code instructions at `~/.claude/CLAUDE.md`
point all projects here for standards and choices.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, operated via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary — the five canonical role names used as-is (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
