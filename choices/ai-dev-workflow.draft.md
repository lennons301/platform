# AI Dev Workflow Choice

**Current choice:** ticket-loop — the only one. Superpowers was retired on
2026-07-31.

## The workflow at a glance

Five stages carry a work item from idea to landed code, coordinated through one
shared **tracker**:

**Generation → [arm] → Execution ⇄ Review → [land] → (deployment)**

- **Generation** turns intent into published, typed work items. Ideas reach it
  by more than one route — **triage** routes *inbound* ones (into a lane, back
  for information, to a human, or closed); an owner with a clear idea starts a
  lane directly.
- **Execution** takes one armed item and produces a candidate change — a PR.
- **Review** judges that candidate with fresh eyes and decides its fate.
- **Deployment** is downstream: landing a PR hands off to `ci-cd.md`; this
  document owns up to the land decision, no further.

**Tracking is not a stage — it is the substrate.** Every handover happens
*through* the tracker: Generation publishes typed items into it, Execution
claims them from it, Review records verdicts on it. The tracker is the
coordinator; no orchestrator holds the workflow in its head. If it isn't in the
tracker, it doesn't exist. The published items are the interface — any tool can
generate them, any agent or human can execute them, and either side can be
swapped without breaking the other.

The shape is a **state machine, not a pipeline** — Execution and Review form a
loop (changes-requested routes back), and repair/attempt loops sit inside
Execution. The handovers are the triggers between states:

| Handover | Trigger | Detailed in |
|---|---|---|
| Generation → Execution | **arming** — a human-decided `ready-for-agent` on a frontier item | *Tracking* |
| Execution → Review | a PR whose objective signals pass | *Execution* |
| Review → land | a gate-cleared approval | *Review* / *Landing* |
| Review → Execution | changes requested (the loop) | *Review* |

### What makes it autonomous — and transportable

These invariants are tool-agnostic; GitHub Issues, the mattpocock skills, and
`ticket-loop.sh` are just this estate's bindings of them. Any port must
reproduce them:

1. **Bounded loops** — every cycle has a deterministic exit or an escape to a
   human (≤N attempts, repair-then-`ready-for-human`, changes-requested
   routing). No unattended thrash.
2. **Blocks are data, not memory** — items are grouped into a block (a
   milestone) with a `0 open` completion signal, and any ordering within lives
   as dependency edges; the executable set is the derived *frontier*. Both the
   grouping and the ordering live in the tracker, never in an orchestrator's head.
3. **Typed, provenance-gated entry** — one tracker holds many entity types
   (ideas, specs, maps, work items); only a correctly-typed item, armed by an
   explicit human decision, enters Execution.
4. **The coordinator verifies side effects** — the runner checks the system of
   record (mergeability, whether a review actually landed), never a pass's
   narration of what it did.
5. **Fresh, independent actors** — one fresh instance per item, Review by a
   separate identity, no shared-context orchestration, never subagents.
6. **Landing is decided by deterministic gates**, not the reviewer's discretion.

Invariants 1–3 are exactly the three things that make this *look* complicated —
loops, blocks of work, and one tracker holding many entity types. They aren't
complications to hide; they're the load-bearing rules.

## Generation

Generation turns intent into **published, typed work items**. There's more than
one way in: **triage** (`/triage`) is the route for *inbound* ideas — an issue
starts `needs-triage` and is routed into one of the lanes below, back for detail
(`needs-info`), to a human (`ready-for-human`), or closed (`wontfix`) — while an
owner with a clear idea just starts a lane directly (or drops a single
`ready-for-agent` ticket). However it entered, what *leaves* Generation is one or
more items on the tracker, still **unarmed**: arming is a separate human step
(see *Who may arm a ticket*).

### The generation flow

Ticket generation isn't a single pipeline — it's a decision tree keyed on **how
big and how foggy** the work is. Pick the entry point that fits; the lanes all
rejoin at the loop.

1. **Tiny / clear** — skip generation entirely. Open one `ready-for-agent`
   ticket, or just do the work.
2. **Already-discussed feature** — `/to-tickets` straight from the conversation.
   Add `/to-spec` first only when the feature is big enough to want a durable,
   reviewable PRD before it's sliced.
3. **Feature needing design** — `/grill-me` (or `/grill-with-docs`, which also
   writes `CONTEXT.md`/ADRs as decisions crystallise) → `/to-spec` and/or
   `/to-tickets` → the loop.
4. **Large, foggy initiative** — too big for one session and the way to the
   destination isn't visible yet. `/wayfinder` first (below), until the way is
   clear, then rejoin lane 2 or 3.

The generation skills are all `disable-model-invocation: true` — you drive them
by slash command; an agent never picks one up on its own.

| Skill | Use |
|---|---|
| `/grill-me` | Interview until the design decisions are actually resolved |
| `/grill-with-docs` | Same, but updates `CONTEXT.md` and ADRs as decisions crystallise |
| `/to-spec` | Work was already discussed — skip the interview, write up what was agreed |
| `/to-tickets` | Break a spec/plan/conversation into thin vertical-slice issues, dependency-ordered |
| `/triage` | Move issues through the label lifecycle — the intake route for *inbound* ideas |
| `/wayfinder` | Charts a large fuzzy initiative as a map of **decision** tickets — see below |
| `/improve-codebase-architecture` | Scan for shallow modules, get an HTML report of deepening candidates, grill through one |

### Wayfinder (lane 4)

`/wayfinder` charts a large fuzzy initiative as a `wayfinder:map` issue that
indexes **decision-ticket** children, each labelled `wayfinder:<type>`
(`research` / `prototype` / `grilling` / `task`), then resolves them one per
session until the way to the **destination** is clear. The map body, fog-of-war,
and frontier mechanics live in the skill — this section is only how wayfinder
meets the rest of the estate.

**Wayfinder plans, it doesn't build.** Every ticket resolves a *decision*, not a
slice of the build — including the `task` type, the one that *does* rather than
decides: it performs prerequisite work (provisioning access, moving data so its
shape can be seen) whose output is *facts a later decision waits on*, never a
piece of the destination. If a ticket's output would be a piece of the product,
it was mis-typed and belongs in the build lane.

**Two different "AFK" axes — don't conflate them.** Wayfinder tickets carry their
own AFK/HITL distinction — can the *wayfinding agent* resolve this one alone in
its session? (`research` is AFK, `grilling` is HITL, `task` is either.) That is a
different axis from the estate's `ready-for-agent` launch button — can
*ticket-loop* land a PR unattended? Different ticket-spaces, different units of
work: a fact recorded on the map versus a mergeable PR.

**Strict separation.** No `wayfinder:*` ticket ever carries `ready-for-agent` or
reaches the execution loop. A wayfinder ticket is claimed by **assignment**
(`gh issue edit <n> --add-assignee @me`), never by the triage label; `/to-spec`
and `/to-tickets` are what stamp `ready-for-agent`, downstream in the build lane.
`ticket-loop.sh` is defensive about it regardless: the auto-pick excludes
`wayfinder:*` and an explicit `--issue` naming one is a hard error — "they must
never reach this loop, however they got labelled `ready-for-agent`." An agent
sent to *implement* a `wayfinder:grilling` ticket would answer its own question
and open a PR for it.

**One exit.** The map has exactly one exit — its **destination** (a spec to hand
to lane 2/3, a decision locked as an ADR, or an in-place change). Individual
tickets, `task` included, are internal steps toward it, never exits in their own
right. When the destination is realised, the map closes (see *Object lifecycle*).

## Tracking (the substrate)

Tracking is the substrate the other stages hand off through: a single **typed
store** that holds several entity kinds at once — unspecced ideas, specs,
`wayfinder:map`s and their decision tickets, and build tickets — encodes their
ordering as data, and retires each as its successor appears. The rules that
follow — what lives where, the label roles, how blocks of work are sequenced,
who may arm, and when objects close — are what let the four activity stages run
without an orchestrator.

### Repo documents vs tracker state

Durable knowledge lives in the repo; work state lives in the tracker.

**Repo (versioned, read every session):** `ROADMAP.md` (coarse, priority-ordered
milestones), `CONTEXT.md` (domain model, terminology, invariants), `docs/adr/`
(decision records — the *why*, written during grilling sessions).

**Tracker (transient work state):** the issues, PRs, and milestones for work in
flight. Tracker state is *derived* — it coordinates work whose durable result
lands in the repo — so no tracker object outlives the artefact that supersedes it
(see *Object lifecycle*).

### Labels (canonical roles)

`needs-triage` → `needs-info` | `ready-for-agent` | `ready-for-human` | `wontfix`

- `ready-for-agent` (AFK) — an agent can implement and merge unattended
- `ready-for-human` (HITL) — needs a human decision or human implementation

### Managing blocks: milestones, dependencies, the frontier

A **block** is a set of work items grouped under one milestone and tracked to a
single completion signal — `0 open`. Most blocks come from a **generation run**
dropping a batch of tickets under a milestone named for the roadmap item; a block
can also be **assembled** from existing, independent items — a clutch of proposed
UX improvements pulled from the backlog, say — grouped to track them to
completion even though each is independently releasable. Three rules keep any
block legible:

**1. The milestone holds only work; a spec is not part of it.** `0 open` is the
completion signal, and it only means something if everything in the milestone is
*work*. So when a block came from a spec, close that spec issue once `/to-tickets`
has decomposed it — with a comment linking the tickets it produced (*Object
lifecycle*: no artefact outlives its successor). (`/to-tickets` deliberately never
touches a parent issue — it can't tell a one-off spec from a `wayfinder:map`, so
the close is the human's call.) Left open inside the milestone, the spec parks
the count at `n+1` forever and shows up as startable work.

**2. Dependency order is data, not memory.** `/to-tickets` records blocking
edges as native GitHub issue dependencies. GitHub counts only *open* blockers,
so a ticket is on the frontier exactly when `blocked_by` is 0, and it becomes
eligible on its own as its blockers close. Nothing needs re-sequencing by hand.
An assembled block of independent items simply carries no edges — every item is
on the frontier at once.

**3. Arm from the frontier.** The frontier query — open, in the milestone, no
open blockers:

```bash
for n in $(gh issue list --milestone "<milestone>" --state open \
             --limit 100 --json number --jq '.[].number' | sort -n); do
  gh api "repos/{owner}/{repo}/issues/$n" \
    --jq 'select((.issue_dependencies_summary.blocked_by // 0) == 0)
          | "#\(.number)  \(.title)"'
done
```

`ticket-loop.sh` skips blocked tickets in its auto-pick and refuses a blocked
`--issue` outright, so the order survives an armed ticket that isn't ready.
Interlude's autonomous executor applies the same rule as a claim-eligibility
check (Phase 5). Publishing a generated batch **unlabelled** and arming from
the frontier keeps `ready-for-agent` doing one honest job: it is both the
launch button and the sequencer.

### Object lifecycle

**No artefact outlives its successor.** Each generation phase publishes a tracker
object, and each is closed once the downstream object that supersedes it exists —
so the tracker never shows superseded work as live, startable, or countable.
Durable knowledge is never lost to a close: it has already moved to its successor.

| Object | Closes when | Its record lives on as |
|---|---|---|
| `wayfinder:*` child ticket | on resolution | a *Decisions-so-far* pointer on the map (+ an ADR if it settled a design decision) |
| `wayfinder:map` | its destination is realised — the spec+tickets exist, the decision is locked as an ADR, or the in-place change is made; a redrawn destination is a **fresh map**, not a reopening | the spec/tickets it produced, plus ADRs |
| Spec issue (`/to-spec`) | `/to-tickets` decomposes it — closed with a comment linking the tickets it produced | the build tickets and their milestone |
| Build ticket (`/to-tickets`) | its PR merges | merged code |
| Milestone | it reaches `0 open` (milestone-autoclose) | — |

The per-object *operational* specifics — how to close the spec issue, the `n+1`
milestone-count trap, the frontier query — are in *Managing blocks* above.

### Who may arm a ticket

Applying `ready-for-agent` is the launch button: it authorises unattended code
to land — the **Generation → Execution** trigger. The rule is about
**provenance, not about who types the command**.

**Arming requires an explicit human decision, expressed through any channel
where the human is actually deciding.** All of these are the owner arming work,
and all are legitimate:

- the owner applying the label directly;
- an interactive session applying it to tickets the owner has just approved —
  a generation run, say, where the breakdown was reviewed before publishing;
- an agent *asking* — a triage pass recommending a ticket in Discord, the owner
  replying yes, the orchestrator applying the label on that confirmation.

**No unattended pass may arm on its own judgement.** Triage, the autonomous
executor, and anything else reading inbound issues may recommend, label
`needs-info`, or label `ready-for-human` — never `ready-for-agent`. The reason
is provenance: an issue body is untrusted text, so a pass that can both read one
and arm it hands the launch button to whoever opened the issue.

A confirmation is only a decision if the owner saw what they were agreeing to.
Record the arming route on the issue, so "who armed this and on what basis" is
answerable after the fact.

Claim eligibility is a second, independent control: an issue whose author is not
allow-listed is not claimable even when labelled, so the label alone was never
the only thing between an outside contributor and a merge.

Whether to arm a whole generated batch at once is a *pacing* decision, separate
from all of the above, and belongs to the owner batch by batch.

## Execution

Execution takes one armed item off the frontier and produces a candidate
change — a PR — through a **bounded loop** run by a **fresh, independent
actor**: one item, one fresh instance, one worktree. The runner is a thin
driver, never an orchestrator holding tickets in a shared context. When the
objective signals pass, it hands the PR to Review.

### Independent per-ticket loops

- Each ticket is worked by one agent (or human) in its own git worktree and
  branch (`agent/issue-<n>`).
- The loop: read the ticket fresh → implement → validate (tests/lint) →
  commit → open PR linking the issue. Stuck after ~3 attempts → stop and
  label `ready-for-human` rather than thrash.
- The agent never grades its own work. Done = objective signals pass (tests,
  lint, CI) **and** a separate reviewer agent — fresh context, fresh GitHub
  identity, reviewing against repo standards and the originating ticket —
  approves the PR (the **Execution → Review** handover; see *Review*). The
  `ticket-reviewer` agent definition is canonical at `templates/agents/` in this
  repo and synced to `~/.claude/agents/` via `scripts/sync-agents.sh`.
- **Parallel or sequenced, it's always independent instances.** Running several
  unrelated tickets at once and driving a dependent chain in order are the same
  mechanism: independent loops coordinated by the tracker, not one agent holding
  them in a shared context. There's more than one way to drive a chain —
  (a) pure labelling: dependency edges plus `ready-for-agent`, each ticket
  auto-picked in order as its blockers close; (b) a Claude session running
  `ticket-loop.sh` across the frontier; (c) a user driving Claude agents;
  (d) manual command-line invocation. The invariant they share: **each ticket is
  worked by a separate, fresh Claude instance in its own worktree — never a
  subagent of the driver.** A subagent would share the driver's context and
  identity, defeating both the fresh-context read and the fresh-identity review.
  Subagents stay fine for narrow fan-out *within* a ticket (research, scanning).
- Thin runner: `scripts/ticket-loop.sh` in this repo picks up one
  `ready-for-agent` issue, runs the implement pass in a worktree, evaluates
  the review gates, then runs the review pass with fresh context under the
  reviewer identity.

### Per-ticket skills

The generation skills above are human-driven. These carry no
`disable-model-invocation`, so an agent inside the loop reaches them on its own —
no wiring needed, and they are the menu that ticket labels select from (see
*Workflows per ticket*).

| Skill | Where it lands |
|---|---|
| `/tdd` | Red→green loop. **Needs its seams pre-agreed** — see below |
| `/diagnosing-bugs` | Diagnosis loop; replaces `superpowers:systematic-debugging` |
| `/code-review` | Two-axis (Standards + Spec) self-check the implement pass runs before pushing |
| `/resolving-merge-conflicts` | When the default branch has moved under a PR |
| `/research` | Background agent against primary sources |
| `/prototype` | **HITL only** — the user runs it and reacts. Never on a `ready-for-agent` ticket |
| `/codebase-design` | Deep-module vocabulary: module, interface, depth, seam, adapter, leverage, locality |
| `/domain-modeling` | Owns the `CONTEXT.md` and `docs/adr/` formats this doc mandates |

**Seams must arrive in the ticket.** `/tdd`'s core rule is that no test is
written at an unconfirmed seam — "confirm them with the user". An unattended
pass has no user to confirm with, so it either invents seams (defeating the
discipline) or stalls. `/to-tickets` output for anything labelled `workflow:tdd`
must therefore name the seams under test in the issue body. A ticket that
doesn't is not ready for an agent.

**`/implement` is deliberately not adopted.** It is the plugin's alternative
*orchestrator* — `ticket-loop.sh` is ours — and being
`disable-model-invocation: true` it is unreachable from the runner anyway.

**Per-repo setup:** run `/setup-matt-pocock-skills` once in each repo before
first use. It configures the issue tracker (GitHub), the triage label
vocabulary, and where `CONTEXT.md`/ADRs live (writes `docs/agents/`).

### Workflows per ticket

1. **The menu** — the model-invocable skills above *are* the menu. A
   `workflow:<skill>` label on the ticket selects one, and the label name is
   the skill name, so there are no menu files to write or keep current:

   | Label | Runs |
   |---|---|
   | `workflow:tdd` | `/tdd` — must name its seams in the body |
   | `workflow:diagnosing-bugs` | `/diagnosing-bugs` |
   | `workflow:research` | `/research` |
   | `workflow:prototype` | `/prototype` — HITL, pair with `ready-for-human` |

   No label means the agent uses its judgement, as before.
2. **Per-ticket overrides** — if no menu item fits, the ticket author writes a
   short **Workflow** section into the issue body: steps, gates, done-signal.
   Agents follow this if present, otherwise the labelled default.
3. **Promotion rule** — the same bespoke workflow in three tickets gets
   promoted: prefer an upstream skill where one fits, otherwise add a named
   workflow to this table via PR.

### Capability contracts

**A pass must never be promised a capability its executor doesn't actually
provide.** The failure is silent and total: a headless pass told to run a
command it isn't permitted, to call a `gh` it can't authenticate, or to invoke a
`workflow:<skill>` the executor doesn't have is auto-denied everything it was
told to do — *including its own escape hatch* (comment + relabel
`ready-for-human`) — and stalls without recourse.

The rule: **every executor states an explicit capability contract for its
passes — what the agent can run, what auth it has, which skills resolve —
and its pass prompts are derived from that contract**, so prompt and
capabilities cannot drift.

This estate's bindings:

- **The laptop runner** (`scripts/ticket-loop.sh`): the contract is the
  `IMPLEMENT_VERBS` / `REPAIR_VERBS` / `REVIEW_VERBS` arrays. Each pass's
  `--allowedTools` is rendered from its array, and the permission preflight
  checks ask/deny rules against the same arrays — one definition, three
  consumers. Changing a pass prompt (or `templates/agents/ticket-reviewer.md`,
  which the review pass launches) means updating the matching array in the
  same change. `REPAIR_VERBS` is the implement set minus the PR-creation
  verbs (`gh pr list` / `create` / `edit`), keeping `git fetch` /
  `git merge` — no rebase or force-push verb appears in any headless
  contract.
- **Interlude's Phase 5 native executor** provides capabilities
  architecturally (`--dangerously-skip-permissions` inside isolated
  containers, GitHub side-effects moved to the orchestrator, git via
  credential helper), so it cannot hit the permission variant — but its
  implement prompt must not instruct `gh` verbs the container cannot
  authenticate, and `workflow:<skill>` labels must resolve to skills the
  container actually has.

### PR-state dispatch & the repair pass

Parked PRs go stale underneath the loop: gated (`human-signoff`) PRs wait for
a human merge, and each human merge can flip the still-parked ones to
`CONFLICTING` — and the eventual fix-push dismisses the reviewer's approval
(stale-approval dismissal is deliberate), leaving a review rerun nothing
triggers. **Repair is a normal loop operation, not ad-hoc human work**:
re-invoking the runner against an issue that already has an open PR reads the
PR's state first and does only the work that state calls for, instead of
burning one of the limited implement attempts regardless.

After ticket selection, if an open PR exists for the issue branch
(`agent/issue-N`), the runner reads the PR's `mergeable` and `reviewDecision`
(`gh pr view --json …`) — polling while `mergeable` is `UNKNOWN`, which
means "GitHub hasn't computed it yet" and is never treated as a verdict either
way — then dispatches:

| `mergeable` | `reviewDecision` | Runner does |
|---|---|---|
| `CONFLICTING` | any | **Repair pass**, then gates + review. No attempt consumed. |
| `MERGEABLE` | `APPROVED` | Report parked awaiting human merge; exit 0. No agent invoked, no attempt consumed. |
| `MERGEABLE` | none / `REVIEW_REQUIRED` | Gates + review only — covers an approval dismissed by a manual push, or a runner that died between passes. |
| `MERGEABLE` | `CHANGES_REQUESTED` | Normal implement attempt (the work is addressing the feedback) — unchanged. |
| *no open PR* | — | Normal implement attempt — unchanged. |

**The repair pass** is a fresh headless session in the issue worktree that
fetches origin, merges the default branch into the issue branch (**merge only
— never rebase, never force-push**), resolves the conflicts
(`/resolving-merge-conflicts` is the blessed skill), re-runs the repo's
checks, and pushes. On success the invocation falls through to the existing
gates → review sections unchanged: a resolution that newly touches a gated
path re-gates the PR, and the approval the fix-push dismissed gets its review
rerun automatically.

Repair accounting: a repair posts its own `🔧` issue-comment marker —
deliberately distinct from the `🤖 Attempt N/M` markers, so attempt counting
is unaffected — and never increments the attempt count. If the PR is still
`CONFLICTING` after the repair pass, the runner comments its findings on the
issue, labels it `ready-for-human`, and exits non-zero. Fail fast — no retry
loop.

The implement pass carries the same duty as an exit criterion: before
finishing, it must confirm the PR is `MERGEABLE`, integrating the current
default branch (`git fetch` + `git merge`) and resolving if not. The runner
remains the deterministic guarantor — after the implement pass it polls
mergeability and routes `CONFLICTING` into the same repair machinery before
gates/review. Repair keeps parked PRs mergeable; it never merges them —
`human-signoff` still means a human merges.

## Review

Review judges the candidate with **fresh eyes and a separate identity** and
decides its fate — approve, request changes (back to Execution, the loop), or
escalate to a human. Two rules keep it honest and autonomous: a **deterministic
gate** decides whether an approval may auto-land, not the reviewer; and the
**coordinator verifies the verdict actually landed** on the PR rather than
trusting the pass's narration.

### Reviewer identity & onboarding

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
and stored in Doppler. Onboarded repos: `lemons`, `last-person-standing`,
`interlude` (2026-07-30). Run `scripts/setup-reviewer.sh` per repo as it adopts
the loop.

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

**Repo permission rules:** each headless pass pre-approves, via
`--allowedTools`, exactly the command verbs its prompt (or the agent
definition it launches) instructs — the implement pass's workflow verbs
(issue read/comment/relabel, stage/commit, push, fetch/merge the default
branch, PR create/update, `doppler run`), the repair pass's conflict-repair
verbs (the implement set minus PR creation, keeping `git fetch` / `git merge`),
and the review pass's reviewer verbs (issue/PR read, CI
checks, review submission, auto-merge disarm, labelling). Onboarding
therefore does not depend on a repo's interactively-grown allowlist: on a
repo with no allow rules at all, both passes function. Repo-specific check
commands (tests, lint) are the deliberate exception — they run under the
already-approved `doppler run`, or fall to the repo's own allowlist.

What a repo's settings *can* still do is block: Claude Code evaluates
permission rules deny → ask → allow with the *first match winning* — an
`ask`/`deny` rule in the repo's `.claude/settings.json` or
`.claude/settings.local.json` (worktree sessions resolve these to the main
checkout) beats any allow from any source, and a non-interactive pass cannot
answer an ask prompt, so the pass dies mid-run. `ticket-loop.sh` preflights
these files (plus `~/.claude/settings.json`) against the full carried verb
set of the passes and fails fast naming the offending rule; remove or relax
it before onboarding a repo. (`--afk` skips permissions for the implement and
repair passes only — the review pass always runs under permissions.) The carried sets
and the preflight's checked set are one definition in the runner — see
*Capability contracts* above.

### Review gates

Whether an approval may *land* the PR is decided deterministically, not by the
reviewer: the runner matches changed paths against `standards/review-gates.yaml`
(+ the repo's `docs/agents/review-gates.yaml` extension). No match → auto-merge
armed (squash); the approval lands it. Match → `human-signoff` label, auto-merge
off; a human merges after looking (see *Landing the PR*). See
`standards/review-gates.md`. Because the gate — not the reviewer — decides
landing, a mistaken or compromised approval still cannot auto-land a gated path.

### Verified side effects: a pass's narration is not evidence

**A pass's narration is never evidence that its side effect landed.** The twin
of the capability-contract drift (see *Capability contracts* under Execution),
one step later: the capabilities are all present, but a pass reports work it
never did. The classic case is a review pass that emits a complete
`VERDICT: approve` with full reasoning while GitHub shows no review submitted —
a runner that trusts the narration exits 0 on an approval that isn't there.
(This estate hit exactly that; the owner caught it by eye.)

The rule: **where a pass's job is a side effect, the runner verifies the side
effect before reporting — never the pass's account of it.** The runner already
does this for mergeability (it polls `mergeable` rather than trusting the
implement pass's word) and now for the review itself:

- the review pass must end its output with a machine-readable
  `VERDICT: approve | request-changes | comment | escalate` line;
- the runner reads that line, then reads the reviewer identity's own review off
  the PR (`gh pr view --json reviewDecision,latestReviews`) and requires the two
  to agree — `approve` → `APPROVED`, `request-changes` → `CHANGES_REQUESTED`,
  `comment` → `COMMENTED`, `escalate` → anything but an approval (it submits a
  PR comment, not a review);
- a mismatch exits non-zero naming what the pass claimed against what GitHub
  shows. A pass that emits no readable verdict, or a PR read that fails, is
  *unverifiable* — also non-zero, because "can't tell" is not "fine".

Logic lives in `scripts/review-verify-lib.sh` (tested by
`checks/tests/test-review-verify.sh`); mismatches are re-read a few times first
(`REVIEW_VERIFY_ATTEMPTS` / `REVIEW_VERIFY_SLEEP`) since review data reads back
through GraphQL and falsely failing a real approval is as wrong as passing a
phantom one. A failed run leaves the PR unreviewed and mergeable, which the
PR-state dispatch above routes straight back into gates + review on the next
invocation — no attempt consumed.

## Landing the PR (Review → out)

A gate-cleared approval lands the PR (auto-merge, squash); a gated one carries
`human-signoff` and waits for a human (see *Review gates*). Landing is the
workflow's exit — merged code hands off to **deployment**, which lives in
`ci-cd.md` and the environments checks, not here.

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

## Cautions

Three safety properties that span every stage:

- **Prompt injection** — autonomous agents read issue bodies as instructions.
  Restrict who can create/label issues on any repo running unattended agents;
  outside contributors must not be able to reach `ready-for-agent`. With
  auto-merge live this is a hard requirement, not advice: whoever can label an
  issue `ready-for-agent` can cause code to land unattended. This is why an
  unattended pass may never arm on its own judgement — see "Who may arm a
  ticket". The deterministic
  gates (`standards/review-gates.yaml`) are the owner's mechanical control
  surface — a PR can never widen its own gates (the extension file is read
  from the default branch and is itself gated).
- **Skills are advisory** — the hard gates are tests, the reviewer agent, and
  branch protection, not the markdown.
- **Don't double-plan** — a generated ticket *is* the spec. No second planning
  ceremony on top of it.

## Migration status

**Complete (2026-07-31).** Every active product is on ticket-loop and the
superpowers plugin is uninstalled (`claude plugin uninstall superpowers`).

The last holdout was `premier-league-survivor-picks`, which never migrated —
it was archived instead (`status: archived`, superseded by
`last-person-standing`), so its `ai_workflow: superpowers` is a historical
record of what it used, not a live dependency. Archived products are skipped by
`checks/check-all.sh`, so nothing checks it.

Retiring the plugin mattered more once the execution-side skills were adopted:
`superpowers:using-superpowers` injects a "you MUST invoke a matching skill"
instruction at session start — including the loop's unattended passes — and both
plugins claimed the same triggers, with
`superpowers:test-driven-development` and `:systematic-debugging` competing
against `/tdd` and `/diagnosing-bugs`. One skill set now owns each trigger.

To reinstate it: `claude plugin install superpowers@claude-plugins-official`.
Nothing in the estate depends on it — reinstating would be a new decision, not
a rollback.

## Canonical values

For use in `products/*.yaml` under `choices.ai_workflow`:
- `ticket-loop` — Pocock skills for generation + independent per-ticket loops.
  The only valid value for an active product.
- `superpowers` — **retired.** The legacy two-document flow (design doc +
  implementation plan). The plugin is disabled estate-wide, so this value no
  longer describes a runnable workflow. It survives only on archived products
  as a record of what they used; do not set it on anything new.
