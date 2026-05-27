# Detection Heuristics

Signal catalogs for the four audit axes, plus the evidence model that underpins the overconfidence axis. Use these as a scan checklist, not a rigid script — the goal is to *find* candidate findings; severity and disposition come later.

---

## The evidence-tier model (used by every axis, central to overconfidence)

Every factual claim in a doc has an implicit evidence tier. The audit's job is to make the *wording* match the *tier*.

| Tier | What backs it | Wording it earns |
|---|---|---|
| **T0 — Verified** | Shipped behavior, passing test, code that exists and compiles, observed runtime result, authoritative upstream doc cited | "does", "is", "returns", "verified by `<test>`" |
| **T1 — Implemented but unproven** | Code exists but no test/observation confirms the claimed property | "implemented as", "currently", "intended to" |
| **T2 — Decided / planned** | A decision or plan exists; no code yet | "planned", "will", "the decision is", "spec'd" |
| **T3 — Researched** | External reading suggests it; not validated in *this* system | "per `<source>`", "appears to", "reportedly", "candidate" |
| **T4 — Speculated** | Reasoning/intuition only | "likely", "probably", "may", "expected to" |

**Overconfidence = wording above the tier the evidence supports.** A T3 fact ("the library reportedly supports X") written in T0 voice ("X is fully supported, confirmed") is the classic burn. The fix is to drop the wording to the right tier, *not* to delete the claim and *not* to go research it into a higher tier unless asked.

Two asymmetries to respect:
- **Downgrading is safe; upgrading is not.** You can always soften an overstatement. You may only strengthen a claim if you have T0/T1 evidence in hand.
- **A bare certainty word with no citation is a smell even when it happens to be true.** Flag "confirmed/only/always/guaranteed/never" that lacks a pointer to what confirms it; the right fix is often to *add the citation*, not remove the word.

---

## Axis 1 — Drift (claims that are no longer true)

Highest-priority axis: a wrong doc is worse than a missing one. Scan for:

- **Contradicted by code.** A described behavior, signature, field name, default value, file layout, or flow that the code no longer matches. (Read the relevant code; don't trust the doc's self-description.)
- **Dead references.** Links/paths/filenames/symbols/commands that no longer exist — deleted files, renamed modules, moved paths, removed flags, retired commands. Grep each referenced name; a zero-hit reference is dead.
- **Rename lag.** A term was renamed in the system but old-name occurrences linger in prose, headings, diagrams, or examples. Renames are the #1 drift source — when you find one renamed term, search the whole set for the old name.
- **Stale quantities.** Counts ("12 steps", "three options"), version numbers, dates, percentages, sizes — anything that was true at writing and silently went stale. Recompute against current state.
- **Superseded decisions written as current.** A decision was reversed or refined but the old framing survives in a describer doc. Cross-check against the decision/history log.
- **Resolved TBDs.** "TBD", "to be decided", "open question", "placeholder" markers whose answer now exists elsewhere. Either fill from truth or, if still open, confirm it's *actually* still open.
- **Aspirational-as-shipped.** Future/planned features described in present tense as if they exist. Re-tag to the right tense/tier.

Drift findings are usually **unambiguous** (truth says otherwise) and can be batched as default-yes fixes.

---

## Axis 2 — Redundancy (the same fact in multiple places)

Duplication isn't bad because it wastes bytes — it's bad because **copies drift independently**, so the reader can't tell which is right. Scan for:

- **Repeated load-bearing values.** The same number, hex, path, version, command string, or config snippet appearing in 2+ files. These are the dangerous duplicates — when one updates, the others rot. Grep the literal value across the set.
- **Restated rules/definitions.** The same rule, definition, or principle explained in full in several docs. Pick the canonical home (usually the most-authoritative or most-topical doc); the others get a one-line summary + pointer.
- **A doc acting as a superset of others.** One doc that re-narrates everything the feature docs say. This *can* be intentional (a deliberate overview/PRD) — flag it as a judgment call, don't auto-collapse.
- **Copy-pasted prose blocks.** Identical or near-identical paragraphs. Near-identical (one drifted, one didn't) is itself a drift finding — reconcile to truth first, then de-dupe.

**Resolution pattern:** establish the canonical statement → keep it in one place → replace every copy with a pointer (or a one-line gloss + pointer). Never delete all copies of a fact while de-duping — *move*, don't lose.

---

## Axis 3 — Overconfidence (wording exceeds evidence)

Run the evidence-tier model over factual claims. Linguistic markers that warrant a tier check:

- **Certainty absolutes:** "confirmed", "verified", "proven", "guaranteed", "always", "never", "only", "the only", "impossible", "cannot fail", "fully supported", "100%".
- **Validation language without a referent:** "tested" (by what?), "confirmed" (by whom/what?), "verified" (where?). If no citation follows, either add one or downgrade.
- **Superlatives standing in for analysis:** "best", "the right choice", "obviously", "clearly", "trivially" — often T3/T4 opinions wearing T0 clothes.
- **Borrowed authority:** claims that paraphrase an upstream source but state it more strongly than the source does. Check the source's actual wording; match it.

The fix is calibration: rewrite to the tier the evidence supports (table above). Preserve the claim and its substance — only the certainty changes. If calibrating would gut the sentence, the claim was probably load-bearing speculation that should be re-tagged (e.g. "likely direction:") rather than deleted.

> Caution: overconfidence-calibration is the axis most likely to slide into rewriting voice. Change the certainty word(s); leave the rest of the sentence alone.

---

## Axis 4 — Bloat (content that no longer earns its space)

The softest axis — almost always a judgment call, so report and let the owner elect. Scan for:

- **Vestigial sections.** Content about a removed feature, an abandoned approach, an old structure — historically interesting but no longer operative. (If it's *decision history*, it belongs in the decision log, not deleted — relocate.)
- **Over-elaboration.** Five paragraphs where the operative content is one rule + one example. Propose tightening, but preserve the author's wording within what remains.
- **Code/data restated in prose.** Long inline restatements of things the code or a generated artifact already states authoritatively — these rot. Prefer a pointer to the authority.
- **Redundant scaffolding.** Throat-clearing intros, repeated context-setting, "as mentioned above" loops.
- **Resolved hedging.** Multi-line "but what if / on the other hand" passages whose question has since been answered — collapse to the answer.

**Do not** treat brevity as an end in itself. Some elaboration is the doc's value. The test is: *does removing this lose truth or intent?* If yes, keep it. If it only loses words, propose the cut — and let the owner decide.

---

## Cross-axis interactions (handle in this order)

Findings interact; resolving in the wrong order creates churn:

1. **Reconcile drift first.** Fix what's *wrong* before deciding what's *redundant* — otherwise you might canonicalize the stale copy.
2. **Then de-dupe** against the now-correct canonical statement.
3. **Then calibrate overconfidence** on what remains.
4. **Bloat last**, since de-duping and calibrating often already removed much of it.

A single passage can trip multiple axes (a duplicated, stale, overstated paragraph). Note all axes on the finding; apply the order above.

---

## What "ground truth" actually means in practice

When verifying a claim, prefer authorities in this order:
1. **Running/observed behavior** (a test result, a command's output, a built artifact).
2. **The code itself** (existence, signatures, defaults, current versions/config).
3. **The designated canonical doc / decision log** for *intent* questions code can't answer.
4. **A direct owner statement** in-conversation.
5. **External upstream docs**, cited — and only ever at the certainty the upstream itself uses.

If none of these can settle a claim, the honest finding is "unverifiable from here" — report it as such rather than guessing which way it resolves.
