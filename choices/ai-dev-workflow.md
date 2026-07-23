# AI Dev Workflow Choice

**Current default:** ticket-loop (piloting; superpowers remains the legacy value)

## Decision

Development work is split into two loosely-coupled halves, connected through
GitHub Issues:

1. **Work item generation** — align on what to build, write it down once,
   break it into tickets. The output is *published* to the repo's issue
   tracker. If it isn't in the tracker, it doesn't exist.
2. **Work execution** — humans or agents pick up tickets and work them
   independently. There is no orchestrator; the tracker is the coordinator.

The published tickets are the interface: any tool can generate them, any agent
or human can execute them, and either side can be swapped without breaking the
other.

## Tooling

### Generation: mattpocock-skills plugin (installed at user scope)

| Skill | Use |
|---|---|
| `/grill-me` | Interview until the design decisions are actually resolved |
| `/grill-with-docs` | Same, but updates `CONTEXT.md` and ADRs as decisions crystallise |
| `/to-spec` | Work was already discussed — skip the interview, write up what was agreed |
| `/to-tickets` | Break a spec/plan/conversation into thin vertical-slice issues, dependency-ordered |
| `/triage` | Move issues through the label lifecycle |
| `/wayfinder` | Large fuzzy initiatives — parent "map" issue, child tickets created only at the frontier |

Small tasks skip all of this — go straight to execution.

**Per-repo setup:** run `/setup-matt-pocock-skills` once in each repo before
first use. It configures the issue tracker (GitHub), the triage label
vocabulary, and where `CONTEXT.md`/ADRs live (writes `docs/agents/`).

### Labels (canonical roles)

`needs-triage` → `needs-info` | `ready-for-agent` | `ready-for-human` | `wontfix`

- `ready-for-agent` (AFK) — an agent can implement and merge unattended
- `ready-for-human` (HITL) — needs a human decision or human implementation

### Execution: one agent per ticket, no orchestrator

- Each ticket is worked by one agent (or human) in its own git worktree and
  branch (`agent/issue-<n>`).
- The loop: read the ticket fresh → implement → validate (tests/lint) →
  commit → open PR linking the issue. Stuck after ~3 attempts → stop and
  label `ready-for-human` rather than thrash.
- The agent never grades its own work. Done = objective signals pass (tests,
  lint, CI) **and** a separate reviewer agent — fresh context, reviewing
  against repo standards and the originating ticket — approves the PR. The
  `ticket-reviewer` agent definition lives at `~/.claude/agents/`.
- Parallelism = several independent loops in separate worktrees, not an
  orchestrating agent. Subagents are for narrow fan-out (research, scanning)
  only.
- Thin runner: `scripts/ticket-loop.sh` in this repo picks up one
  `ready-for-agent` issue, runs the implement pass in a worktree, then the
  review pass with fresh context.

## Workflows per ticket

1. **The menu** — default workflows live in the repo as named, versioned files
   (e.g. `tdd-loop`, `spike`, `refactor`, `docs-only`). A ticket label selects
   one.
2. **Per-ticket overrides** — if no menu item fits, the ticket author writes a
   short **Workflow** section into the issue body: steps, gates, done-signal.
   Agents follow this if present, otherwise the labelled default.
3. **Promotion rule** — the same bespoke workflow in three tickets gets
   promoted to the menu via PR.

## Repo documents vs tracker state

Durable knowledge lives in the repo; work state lives in the tracker.

**Repo (versioned, read every session):** `ROADMAP.md` (coarse, priority-ordered
milestones), `CONTEXT.md` (domain model, terminology, invariants), `docs/adr/`
(decision records — the *why*, written during grilling sessions).

**Tracker:** milestones group the issues for one roadmap item (grill → spec →
tickets → execute → review → close → next); a parent "map" issue per large
fuzzy initiative.

## Cautions

- **Prompt injection** — autonomous agents read issue bodies as instructions.
  Restrict who can create/label issues on any repo running unattended agents;
  outside contributors must not be able to reach `ready-for-agent`.
- **Skills are advisory** — the hard gates are tests, the reviewer agent, and
  branch protection, not the markdown.
- **Don't double-plan** — a generated ticket *is* the spec. No second planning
  ceremony on top of it.

## Migration status

Piloting alongside Superpowers (still installed). Move projects one at a time:
run `/setup-matt-pocock-skills` in the repo, create the labels, flip the value
in its product YAML. Once the estate has moved, disable the superpowers plugin
(`claude plugin disable superpowers`).

## Canonical values

For use in `products/*.yaml` under `choices.ai_workflow`:
- `ticket-loop` — Pocock skills for generation + independent per-ticket loops (default)
- `superpowers` — legacy two-document flow (design doc + implementation plan)
