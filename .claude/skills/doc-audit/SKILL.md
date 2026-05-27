---
name: doc-audit
description: Use when auditing documentation for drift (claims that no longer match the code or current direction), redundancy/duplication across files, overconfident or overstated claims, or bloat — and when reconciling docs back to what is actually true, then trimming or updating them. Triggers on "are the docs still accurate", "the docs drifted", "de-dupe / trim / tighten the docs", "these claims feel overstated", doc-vs-code reconciliation, and post-refactor / post-rename doc cleanup. Language- and project-agnostic.
---

# Doc Audit

Find where documentation has fallen out of sync with reality, then bring it back — without flattening the author's voice or deleting intent.

A doc audit answers four questions about a body of docs, in order of cost:

1. **Drift** — what does it claim that is no longer true?
2. **Redundancy** — what is stated in more than one place (and therefore drifts in only some of them)?
3. **Overconfidence** — what is phrased as more certain than the evidence supports?
4. **Bloat** — what no longer earns the space it takes?

Then it reconciles the docs to **ground truth = code + intent**, proposes graded changes, and (on approval) applies them.

## Core principle: documentation is downstream of truth, not a peer of it

Docs are not the source of truth — they *describe* it. So an audit never reasons about doc-vs-doc in a vacuum; it anchors every judgment to an external authority:

- **Code** — what the system actually does: shipped behavior, what compiles, what tests assert, file/symbol/path existence, current dependency versions, current config.
- **Intent** — what the project has *decided*: locked decisions, a decision/history log, design docs designated as canonical, the issue/PR record, and direct statements from the author/owner.

When a doc disagrees with code, code usually wins. When a doc disagrees with intent (e.g. a decision was reversed), the latest decision wins. When code and intent disagree with each other, **that is itself a finding** — surface it, don't silently pick a side.

**Never manufacture certainty.** The audit's job is to *calibrate* claims to evidence, never to invent it. You may downgrade an overstated claim; you may not upgrade a hedge into a guarantee unless code/tests actually back it.

## When to use

- Docs may have drifted after refactors, renames, version bumps, dependency changes, or reversed decisions.
- The same fact (a value, a path, a version, a rule) is repeated across files and you suspect copies have diverged.
- Claims read as "verified / confirmed / only / always" but were never actually validated.
- A doc set has grown sprawling and you're asked to trim, tighten, or de-duplicate.
- Routine hygiene before a release, a handoff, or onboarding a new contributor.

## When NOT to use

- Authoring brand-new docs from scratch (this skill reconciles existing docs to truth; it doesn't invent coverage).
- Pure copy-editing for grammar/style with no truth or structure question.
- Docs that are *intentionally* frozen snapshots (archives, changelogs, decision logs, "as-of vX" specs, contingency/mirror copies). Detect these and leave their historical content alone — see Guardrails.

## Workflow

### Phase 0 — Scope and establish ground truth
1. **Define the doc set** and the truth set. Which files are under audit? Which are *authorities* (code, tests, decision log, canonical design docs) and which are *describers* (everything else)?
2. **Classify each doc by role**, because the rules differ:
   - **Canonical / source-of-truth** — owns certain facts; other docs should point here, not restate.
   - **Describer / derived** — should agree with canonical + code.
   - **Frozen** — archives, changelogs, decision/history logs, version-pinned specs, mirrors/contingency copies. *Transitions and dated claims belong here.* Do not "current-ize" these.
3. **Build the ground-truth picture** before reading docs critically: skim the code surface relevant to the claims, the decision/history log, recent commits (`git log`), and any owner statements in the conversation. You are looking for what's *actually* shipped, named, versioned, and decided.

### Phase 1 — Audit across the four axes
Pass over the doc set looking for each signal class. See `references/detection-heuristics.md` for the full signal catalog and linguistic markers. In brief:

- **Drift** — claims contradicted by code/current state; dead references (deleted/renamed files, symbols, paths, commands); stale counts/versions/dates; superseded decisions still written as current; "TBD" that's since been resolved.
- **Redundancy** — the same fact in multiple files, *especially* values that must stay in sync (numbers, hex, paths, versions, command invocations). Identify the canonical home; the rest become pointers.
- **Overconfidence** — certainty words ("confirmed", "guaranteed", "only", "always", "never fails", "verified") not backed by a citation to code/test/authoritative source. Research and speculation dressed as validated fact.
- **Bloat** — over-elaboration, vestigial sections, content duplicated from code that rots, walls of prose where a list or pointer would do.

Record every finding with **evidence** (the exact claim + where truth says otherwise) and a **proposed action**. Don't fix inline yet.

### Phase 2 — Grade and report
Produce a findings report (format in `references/report-template.md`): each finding gets a **severity**, the **evidence**, and a **proposed action**. Group by file or by axis. Separate the *unambiguous* (dead reference, contradicted-by-code) from the *judgment calls* (is this elaboration valuable or bloat?).

### Phase 3 — Confirm before applying
**Bloat and trims are author calls, not yours.** Present the report and let the owner elect what to apply — some elaboration is deliberate, some duplication is intentional emphasis. Use `AskUserQuestion` to batch the judgment-call decisions when there are several. Unambiguous truth-fixes (dead links, contradicted facts) can be proposed as a default-yes batch. If the user already said "just fix it," skip the round-trip for the unambiguous tier but still surface the judgment calls.

### Phase 4 — Apply safely
Apply only elected changes, following the Guardrails below. For redundancy, move the fact to its canonical home and replace copies with a pointer. For drift, rewrite the claim to current truth. For overconfidence, calibrate the wording down to match evidence. For bloat, cut content — not voice.

### Phase 5 — Verify
- Re-check that edits didn't introduce *new* contradictions or break cross-references (a pointer must resolve; a renamed term must be renamed everywhere it's load-bearing).
- Confirm canonical facts now appear once.
- If a build/test/lint exists for docs (link-checkers, doctests), run it.
- Summarize what changed and what was deliberately left alone.

## Guardrails (these are where audits do damage — follow them)

- **Trim content, not phrasing.** Remove duplication, dead references, and vestigial sections. Do *not* rewrite the author's wording to "improve" it — preserve voice, structure, sentence patterns, and formatting. ("Remove bloat, not phrasing.") If you find yourself rephrasing a sentence that was already true and clear, stop.
- **Propose before collapsing.** The owner decides what elaboration stays. A maximalist doc can be intentional. Don't unilaterally merge or gut sections.
- **Calibrate down, never fabricate up.** Only soften claims that overstate their evidence. Never strengthen a claim's certainty unless code/tests actually justify it. When unsure how strong the evidence is, say so rather than guessing.
- **Rewrite to current state in describers; preserve transitions in frozen docs.** In a normal doc, don't narrate the history of a decision ("was X, now Y, resolved:") — just state the current truth. In a decision log / changelog / archive, the transition *is* the content — leave it.
- **Don't auto-revert intentional placements.** Annotations, deliberate cross-references, and content the author placed on purpose (even if it looks odd) are flagged, not removed. When in doubt, ask.
- **Respect doc roles.** Never "current-ize" a frozen/version-pinned/mirror doc. Never delete the canonical statement of a fact while removing its duplicates — move it, don't lose it.
- **Ground every truth claim in a concrete source.** If you assert "the docs are wrong, the truth is X," cite where X comes from (a file path, a test, a decision-log entry, an owner statement). No truth-by-intuition.
- **Don't expand scope mid-audit.** Surface adjacent problems as notes; don't silently start a refactor.

## Output

Default deliverable is the **findings report** (Phase 2), then — on approval — the **applied edits** plus a short change summary. Lead with the unambiguous truth-fixes; flag the judgment calls separately. Keep the report itself lean: this skill should model the hygiene it enforces.

## References

- `references/detection-heuristics.md` — full signal catalog per axis, the evidence-tier model, and an overconfidence-language calibration table.
- `references/report-template.md` — findings-report format, severity rubric, and a worked example.
