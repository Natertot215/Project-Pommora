### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-07 — ItemsV2 **Phase A SHIPPED** via subagent-driven execution)

> **Resume prompt (next session):** *"Phase A (foundations) of the interactive Item Window is DONE + committed on branch `itemsv2-interactive-window` (`14760b0..0def549`, full target **1283/1283 green**, code-review clean). **Start Phase B (`ItemWindowViewModel`, B1–B9)** — pure `@Observable @MainActor` logic + TDD, no design needed. The loop that worked: a subagent authors each task (Opus 4.8; Sonnet for trivial), authoring ONLY (no build, no commit); the orchestrator HARD-VERIFIES via a background `builder` agent (real NON-ZERO test count — quirk #1), reads the actual diff, grounds against source, THEN green-commits; builds always go through the background `builder` so xcodebuild never grabs focus (quirk #13). Keep task-verification chatter to 1–3 sentences. Phases D/E are DESIGN-GATED — **Nathan has background Figma work to share first** (D2 header, D4 segmented property bar, D5 inspector row, E1 pane muted-states). Agents lie; the build and the diff don't."*

**Where it started.** Opened with Spec-V5 + Plan-V3 review-certified (planning-only, on `main`). Nathan folded pre-execution corrections (segmented property bar, gate-EACH-visual, inline-commit model, inspector `(icon)(title)—(field)` row, `displayIcon` DRY, a standing post-functional UIX-review phase), a 3-agent delta-review was run + folded, then he said **"Execute."**

**Key moments.** Executed Plan-V3 **Phase A (A0–A10) subagent-driven** on a fresh branch: 11 green commits + 1 cleanup commit. Each task: implementer authors → orchestrator verifies via background `builder` (non-zero count) + diff + source → green-commit. **Every task passed first-try; full target 1283/1283.** Post-Phase-A code-review pass came back **clean (no blockers/majors)**; 3 minors fixed (cap-engine test coverage, `displayIcon` DRY fold ×3, legacy-layout already covered). Phase A confirmed every downstream anchor against real source — **no B–F task needs rewriting**.

**Nathan's voice.** Mid-execution he tightened the loop: *"DONT give task verification reports with extensive review — it wastes tokens, 1–3 sentences MAX"* and *"Each agent's completion claim must be INDEPENDENTLY verified… DO NOT assume what an agent [says] is true unless EVIDENCE backs it up."* He flagged **background Figma work that must be shared** before the design-gated visual phases.

**Where it left off.** Branch `itemsv2-interactive-window` at `0def549`. Working tree carries 3 `.claude/Planning/*` deletions from Nathan's PARALLEL session (his reorg) — left UNTOUCHED per quirk #10. `main` unchanged. Next: Phase B tomorrow.

#### Lessons Learned

- **The subagent-authored / orchestrator-hard-verified loop works** — Phase A's 11 tasks each passed first-try because no "done" was trusted: every claim was checked against a real background build (non-zero count), the actual diff, and source. Cross-checking even caught a false implementer claim (one agent insisted `PromotedProperty(id:)` "won't compile" — it does; an earlier task had already proven it) — code was fine, reasoning wasn't.
- **The "mid-session Planning deletions" were NOT an anomaly — they're Nathan's parallel-session reorg** (quirk #10). Never restore/bundle unattributed working-tree changes; surface them. (Supersedes the prior session's "unidentified deleter" framing — no root-cause needed.)
- **Stale SourceKit squiggles fire on nearly every Swift edit** (quirk #3) — "Cannot find type X" / "No such module" / "does not conform to Equatable" for same-module types. Trust the background `builder`, never IDE diagnostics.
- **Builds via the background `builder` agent only** (quirk #13) so xcodebuild never grabs focus; implementer subagents author, they do not build or commit.

#### Next Session

1. **Phase B — `ItemWindowViewModel` (B1–B9).** Pure `@Observable @MainActor` logic + TDD; no design input. Same loop: subagent authors → background-builder verify (non-zero count) → diff/source check → green-commit. All anchors confirmed in Phase A.
2. **Before Phases D/E (visuals) — get Nathan's Figma.** D2 header / D4 segmented property bar / D5 inspector row / E1 pane muted-states are design-gated and Nathan has background Figma to share. Build each gated task's non-visual scaffolding first so a gate never stalls the plan; batch the visual asks into one design checkpoint.
3. **Branch `itemsv2-interactive-window`** — merges to `main` after Phase F (or whenever Nathan wants). Phase C (renderer cleanup) sits between B and the visual phases.

#### Pending Focuses

- **[carried] Item Window — Phase A SHIPPED; Phases B–F remain.** Spec `Planning/06-07-ItemsV2-Spec-V5.md`, plan `Planning/06-07-ItemsV2-Plan-V3.md` (execution status in its banner). B is next; D/E need Figma.
- **[carried from 06-07]** `markerRanges[0]/[1]` subscripts in `styleItemLinks` (no bounds guard). Can't crash today (tokenizer always emits 2). Add `guard token.markerRanges.count >= 2` if the tokenizer is refactored.
- **[carried from 06-03]** Push `folder-exclusion` → origin — still no upstream, ~30+ commits ahead. (carried 3×+ — confirm still wanted.)
- **[carried from 06-03]** Delete the merged `markdownpm-rehome` branch.
- **Nathan: add `excluded_folders` entries + rebuild once** to clear the meta-file leak. Recommended `The Nexus/.nexus/settings.json` additions: `"Claude"`, `"Pommora/CLAUDE.md"`, `"Pommora/Handoff.md"`. Confirm whether `History.md`/`Framework.md`/`Resources.md` are also non-content.
- **Latent (review-flagged):** pages nested ≥2 folders deep in a collection still missing from the launch index scan (`IndexBuilder` non-recursive `children` vs `loadAll` recursive `descendantFiles`). Fix when it bites.

#### Fix Log

1. **`.claude/Planning` working-tree deletions = Nathan's parallel-session reorg, NOT a bug** (clarified this session, quirk #10). 3 tracked Planning docs show as deleted in the working tree; left untouched, never bundled into commits. Supersedes the prior "unidentified deleter" entry — no root-cause needed.
2. **Column reorder broken** — drag-reordering table columns; folds into v0.7.0 view-system work.
3. **"Modified" not hideable** in the visibility settings.
4. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
5. **Column layout not persisted** across sessions (+ property columns don't show icons); folds into v0.7.0.
6. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
7. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
8. **Agenda description-cap doc mismatch** — specs claim a 1000-char cap but validators enforce none; decide the intended cap or drop the doc claim.
9. **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **ItemsV2 interactive Item Window (Phase A BUILT 2026-06-07; B–F pending) →** spec `Planning/06-07-ItemsV2-Spec-V5.md`; plan `Planning/06-07-ItemsV2-Plan-V3.md` (banner carries execution status); review discipline `Guidelines/Review-Discipline.md`. Built on branch `itemsv2-interactive-window` (`14760b0..0def549`). Paradigm #15 amend deferred to Plan-V3 Task F3 (docs).
- **ItemsV2 (SHIPPED 2026-06-03, archetype model — being replaced) →** as-built `Planning/06-03-ItemsV2-Implemented.md`; superseded by the interactive rework above.
- **Connections (PAGE-LEVEL COMPLETE 2026-06-07) →** spec `Features/Connections.md`; plan `Planning/06-05-Connections-Plan.md`. Item chip click path (`onItemLinkClick` → `ItemLinkOpener.loadItem` → `AppGlobals.presentItemAction`) is the entry to the Item Window.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` · review discipline → `Guidelines/Review-Discipline.md`
- Branch quirks + hard rules → `CLAUDE.md`
