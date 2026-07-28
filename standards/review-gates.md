# Review Gates Standard

Whether an agent-authored PR may merge without a human is decided by data, not
by agent judgement.

## Principle

The ticket-loop reviewer agent approves PRs under its own identity, and an
approval on an armed PR auto-merges. The decision to *arm* is therefore the
real gate — and it is made deterministically: the runner diffs the PR's
changed paths against declared globs (`standards/review-gates.yaml`). Agentic
judgement may add human review on top; it can never remove it.

Gates route work *to* a human; they never require a second one. Every outcome
the automation produces must remain achievable by the estate owner alone in
the GitHub UI (see "Human parity" in `choices/ai-dev-workflow.md`) — which is
why ticket-loop repos keep `enforce_admins` off.

## Requirements

1. The estate-default gate globs live in `standards/review-gates.yaml`,
   grouped by category. Any changed path matching any glob means: no
   auto-merge, `human-signoff` label, a human merges after looking.
2. A repo may extend the gates via `docs/agents/review-gates.yaml` (same
   shape). Extensions are additive only — a repo cannot un-gate an estate
   default.
3. Gate evaluation is script-enforced (`scripts/review-gates-lib.sh`) and
   fail-closed: missing or unparseable platform config aborts the run rather
   than arming auto-merge.
4. The reviewer agent may escalate an armed PR to human sign-off (disarm,
   label, comment-type review) when it judges the change consequential —
   guided by the categories below — but never approves in that case and never
   removes a gate.
5. Gate changes are ordinary PRs to this repo (or the repo's extension file),
   so the tuning history stays reviewable.

## Seeded categories

- **visual-ui** — anything altering rendered output. Visual work always gets
  human eyes (estate design-review practice).
- **data-migrations** — schema changes and destructive data operations;
  wrong-once is expensive.
- **auth** — authentication/authorisation paths; silent regressions are
  security incidents.
- **ci-secrets** — workflow definitions and secret-adjacent config; the
  automation's own control surface.

## Tuning loop

Learn when human review pays and encode it: a gate that keeps firing on
changes you would happily auto-land → delete the glob. A bad auto-merge →
add a glob that would have caught it. Adjustments are data edits, not prompt
edits.

## How to comply

Run `scripts/setup-reviewer.sh` when onboarding a repo to the ticket-loop
(see `choices/ai-dev-workflow.md`); it seeds the repo's extension stub.
