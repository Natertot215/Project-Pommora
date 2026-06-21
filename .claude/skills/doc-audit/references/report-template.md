# Findings Report — format, severity, and a worked example

The report is the audit's primary deliverable. It exists so the owner can **elect** what to apply, so it must make each finding decidable at a glance: what's claimed, why it's wrong/redundant/overstated/bloated, and what you'd do about it.

Keep the report itself lean — model the hygiene the skill enforces. Don't pad it with restated context.

## Severity rubric

| Severity | Meaning | Default disposition |
|---|---|---|
| **S1 — Wrong** | Contradicted by code or by the latest decision. A reader acting on it would be misled. | Fix by default (unambiguous tier). |
| **S2 — Risky** | Dead reference, drifted duplicate, or overstatement that could mislead under the right conditions. | Fix by default, but show the edit. |
| **S3 — Judgment** | Bloat, "is this elaboration worth it", canonical-home choice, intentional-superset questions. | **Owner elects.** Do not auto-apply. |
| **S4 — Note** | Adjacent issue, out of audit scope, or "unverifiable from here". | Surface only; no action. |

S1/S2 form the default-yes batch. S3 is where you use `AskUserQuestion`. S4 is FYI.

## Finding shape

Each finding carries, compactly:

- **ID + axis + severity** — e.g. `D3 · drift · S1`.
- **Location** — `file:line` (or section heading).
- **Claim** — the exact text or a tight quote of what the doc says.
- **Evidence** — what truth says, *with its source* (a code path, test, decision-log entry, grep result, or owner statement). No truth-by-intuition.
- **Proposed action** — the specific edit: rewrite to X / replace with pointer to Y / downgrade wording to tier T / cut. For S3, frame as a question, not a done deal.

## Report skeleton

```markdown
# Doc Audit — <scope>
Ground truth used: <code areas / decision log / commits / owner statements consulted>
Docs audited: <N files>  ·  Doc roles: <canonical | describer | frozen breakdown>

## S1 — Wrong (proposed default-fix)
- **D1 · drift · S1** — `guide.md:42`
  Claim: "the CLI flag is `--out`"
  Evidence: code uses `--output`; `--out` removed in `a1b2c3d` (grep: 0 hits in src).
  Action: rewrite to `--output`.

## S2 — Risky (proposed default-fix, edit shown)
- **R1 · redundancy · S2** — `setup.md:10`, `deploy.md:55`, `README:88`
  Claim: build timeout "300s" stated in 3 files; `deploy.md` says "600s".
  Evidence: config `ci/build.yaml: timeout=600`. Two copies stale, one current.
  Action: canonical home = `ci/build.yaml`; docs point there; remove the literal from all 3.

## S3 — Judgment (owner elects)
- **B1 · bloat · S3** — `architecture.md:120-180`
  Claim: 60-line walkthrough of an abandoned approach.
  Evidence: approach removed in `#214`; no current code references it.
  Question: relocate to decision log, cut entirely, or keep as context?

## S4 — Notes (no action)
- **N1** — `api.md` examples reference an internal service I can't reach; accuracy unverifiable from here.

## Summary
<counts by severity; what you'd apply now vs. what needs a call>
```

## After approval — the change summary

Once elected changes are applied (Phase 4–5), close with a short summary:

```markdown
# Applied
- Fixed N S1/S2 findings (list IDs).
- De-duped <fact> to <canonical home>; <K> pointers added.
- Calibrated <M> overstated claims to their evidence tier.
Deliberately left alone:
- <frozen doc> — historical content preserved by role.
- <S3 items the owner declined>.
Verification: <cross-refs re-resolved / link-check / doctest result>.
```

## Worked example (condensed)

> **Scenario:** A library was renamed `fastcache` → `turbocache` and a config default changed. Audit of `docs/`.

```markdown
# Doc Audit — docs/ (post-rename hygiene)
Ground truth: src/ (grep), CHANGELOG, commits since v2.0, package.json versions.
Docs audited: 9  ·  Roles: 2 canonical, 6 describer, 1 frozen (CHANGELOG).

## S1 — Wrong
- D1 · drift · S1 — caching.md:5,33,40 — "import fastcache" / "fastcache.set(...)"
  Evidence: package renamed turbocache in #301; `fastcache` 0 hits in src.
  Action: rename all occurrences to turbocache (load-bearing term — swept whole doc set: also overview.md:12, examples.md:70).
- D2 · drift · S1 — config.md:18 — "default TTL is 60s"
  Evidence: src/config.ts default = 300. Changed in #318.
  Action: rewrite to 300s.

## S2 — Risky
- O1 · overconfidence · S2 — caching.md:48 — "turbocache is the only thread-safe option and is guaranteed lossless"
  Evidence: no test or upstream doc cited; README of turbocache says "thread-safe for single-writer". T0 wording on T3 basis.
  Action: downgrade to "turbocache is thread-safe for single-writer use (per its README)"; drop "only" + "guaranteed lossless".
- R1 · redundancy · S2 — install.md:8 & quickstart.md:3 — min-version "Node 18" in both; quickstart says "Node 16".
  Evidence: package.json engines = ">=18". quickstart stale.
  Action: canonical = install.md; quickstart points to it.

## S3 — Judgment
- B1 · bloat · S3 — caching.md:60-95 — long "why we moved off fastcache" rationale.
  Question: this is decision history — move to CHANGELOG/decision log, or keep inline?

## S4 — Notes
- N1 — benchmarks.md cites numbers from a machine I can't reproduce; left as-is.

## Summary
4 default-fixes (D1,D2,O1,R1) ready. 1 judgment call (B1). 1 note.
Frozen CHANGELOG untouched.
```

Notice what the example does and doesn't do: it **renames the load-bearing term everywhere** (not just where first spotted), **calibrates the overstatement without deleting the claim**, **moves the duplicated version to a canonical home**, and **asks** about the history block rather than cutting it — and it never rewrote a sentence that was simply already correct.
