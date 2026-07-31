# Domain Modelling Standard

Every ticket-loop project records its domain model in a `CONTEXT.md` at the
repo root.

## Principle

Agents and humans need the same words for the same things. `CONTEXT.md` is the
project's glossary — the terms specific to this domain, defined tightly, with
the rejected synonyms named so nobody drifts back to them. It is read before
exploring the codebase, and its vocabulary is what issue titles, test names,
and refactor proposals are written in.

`docs/adr/` holds the decisions — the *why* a future reader would otherwise
wonder about.

## Requirements

1. Every project with `choices.ai_workflow: ticket-loop` has a `CONTEXT.md` at
   the repo root defining at least one domain term, in the format
   `**Term**:` followed by a one-or-two sentence definition.
2. Multi-context repos may instead keep a root `CONTEXT-MAP.md` indexing
   per-context `CONTEXT.md` files.
3. **ADRs are not required.** See below.

## Why ADRs are not counted

An ADR is only written when a decision is hard to reverse, surprising without
context, and the result of a real trade-off. Most decisions meet none of those,
so **zero ADRs is a legitimate steady state** and a check that demanded one
would only produce filler.

The problem an empty `docs/adr/` does create is ambiguity: it looks identical
whether nobody ever modelled the domain, or the domain was modelled and no
decision met the bar. `CONTEXT.md` resolves it. It is the artifact domain
modelling produces, so its presence asserts that the modelling ran — and
therefore that zero ADRs was the correct answer at that point.

That is the whole reason `CONTEXT.md` is the conformance signal and ADRs are
not: one file, positively recorded, makes the absence of the other legible.

## Divergence

A project that genuinely has no domain worth a glossary — a thin script, a
config-only repo — records it in its product YAML rather than carrying a
permanent gap:

```yaml
divergences:
  - standard: domain-modelling
    choice: none
    reason: >
      Single-purpose deploy script with no domain vocabulary beyond its CLI
      flags. A glossary would restate the --help output.
```

Projects on the legacy `superpowers` workflow are skipped automatically — the
remedy is a ticket-loop skill they do not use.

## Closing a gap

The gap is closed by a conversation, not a commit: run `/grill-with-docs` in
the repo, which builds the domain model through `/domain-modeling` as terms get
resolved. For an initiative too large for one session, `/wayfinder` charts it
first. The check then passes on its own.

`checks/create-issues.sh` files these as `ready-for-human`, never
`ready-for-agent` — an agent inventing a domain model unattended produces
plausible fiction that every later session then treats as authoritative.
