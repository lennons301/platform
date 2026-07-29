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
  lint, CI) **and** a separate reviewer agent — fresh context, fresh GitHub
  identity, reviewing against repo standards and the originating ticket —
  approves the PR. The `ticket-reviewer` agent definition is canonical at
  `templates/agents/` in this repo and synced to `~/.claude/agents/` via
  `scripts/sync-agents.sh`.
- Whether an approval may *land* the PR is decided deterministically, not by
  the reviewer: the runner matches changed paths against
  `standards/review-gates.yaml` (+ the repo's `docs/agents/review-gates.yaml`
  extension). No match → auto-merge armed (squash); approval lands it. Match →
  `human-signoff` label, auto-merge off; a human merges after looking. See
  `standards/review-gates.md`.
- Parallelism = several independent loops in separate worktrees, not an
  orchestrating agent. Subagents are for narrow fan-out (research, scanning)
  only.
- Thin runner: `scripts/ticket-loop.sh` in this repo picks up one
  `ready-for-agent` issue, runs the implement pass in a worktree, evaluates
  the review gates, then runs the review pass with fresh context under the
  reviewer identity.

## Reviewer identity & onboarding

The review pass runs as a dedicated GitHub **machine account** so its
approvals are accepted (GitHub rejects self-approval) and can trigger
auto-merge. One account serves the whole estate — GitHub's ToS permits
exactly one free machine account per person.

**Defaults** (override via env vars of the same names in the scripts):

| Setting | Value |
|---|---|
| `REVIEWER_LOGIN` | `lennons301-reviewer` |
| `REVIEWER_DOPPLER_PROJECT` / `_CONFIG` | `platform` / `prd` |
| `REVIEWER_DOPPLER_SECRET` | `REVIEWER_GH_TOKEN` |

**Status:** estate setup complete (2026-07-28) — account created, PAT minted
and stored in Doppler. No repos onboarded yet: run `scripts/setup-reviewer.sh`
per repo as it adopts the loop.

**One-time estate setup (manual, ~10 min):**

1. Create the machine account: ordinary GitHub signup as `lennons301-reviewer`.
   A plus-addressed email (`you+reviewer@…`) works — GitHub treats it as
   distinct.
2. Enable 2FA (mandatory); store the TOTP secret next to the PAT (password
   manager or a second Doppler secret) so a lost device can't strand the
   account.
3. Mint a **classic** PAT with `repo` scope. Classic, not fine-grained:
   fine-grained PATs cannot reach collaborator repos owned by a different
   personal account. Reach stays bounded by collaborator invites.
4. Store it: `doppler secrets set REVIEWER_GH_TOKEN --project platform --config prd`

**Per-machine bootstrap:** install the Doppler CLI and `doppler login`
(plus the usual `gh auth login` and `claude` setup). Nothing else to copy —
the runner fetches the PAT at review time, and exports it only around the
review pass.

**Per-repo onboarding:** `./scripts/setup-reviewer.sh --repo-dir ~/code/<repo>`
(idempotent). It sets branch protection (1 approving review, stale approvals
dismissed on push — existing rules preserved), enables auto-merge, creates the
`human-signoff` label, seeds `docs/agents/review-gates.yaml` (commit it), and
invites + accepts the reviewer as a write collaborator.

**Repo permission rules:** the implement pass pre-approves `git push` and
`doppler run` via `--allowedTools`, but Claude Code evaluates permission rules
deny → ask → allow with the *first match winning* — an `ask`/`deny` rule in
the repo's `.claude/settings.json` or `.claude/settings.local.json` (worktree
sessions resolve these to the main checkout) beats any allow from any source,
and a non-interactive pass cannot answer an ask prompt, so the push dies
mid-run. `ticket-loop.sh` preflights these files (plus `~/.claude/settings.json`)
and fails fast naming the offending rule; remove or relax it before onboarding
a repo, or run `--afk` (which skips permissions entirely).

**Finding gated PRs:** `gh pr list --label human-signoff --state open` in any
repo. Approve and merge when satisfied; the reviewer's comment-review explains
what it verified.

### Human parity (solo developer)

This estate has one developer. The reviewer identity exists to **enable
automation, never to gate the human out**: every outcome the automation can
produce must remain achievable by the owner alone, in the GitHub UI. That
holds because `setup-reviewer.sh` leaves `enforce_admins` **off** — the admin
bypass is the guaranteed human path.

| Situation | Solo human path |
|---|---|
| Own/manual PR, no reviewer ran | Admin bypass merge (red button + confirm — explicit, but one click) |
| Agent PR, armed | Auto-merges on reviewer approval; or merge/bypass yourself anytime |
| Agent PR, gated (`human-signoff`) | Reviewer already approved — normal green merge button |
| Reviewer requested changes, you disagree | Dismiss its review (write access) or bypass-merge; your call is final |
| Reviewer broken (Doppler down, PAT revoked) | Bypass merge — automation degrades, the human path never blocks |

GitHub never lets a PR author approve their own PR, so "1 required review"
can only be satisfied by the reviewer account — for a solo developer the
admin bypass **is** the human review, not a workaround. Corollary: do NOT
enable `enforce_admins` (include administrators) on ticket-loop repos — with
one human it makes solo merging impossible. `setup-reviewer.sh` preserves it
where it already exists and warns; either accept reviewer-approval-then-merge
as your only path there, or turn it off.

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
  outside contributors must not be able to reach `ready-for-agent`. With
  auto-merge live this is a hard requirement, not advice: whoever can label an
  issue `ready-for-agent` can cause code to land unattended. The deterministic
  gates (`standards/review-gates.yaml`) are the owner's mechanical control
  surface — a PR can never widen its own gates (the extension file is read
  from the default branch and is itself gated).
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
