### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-08 — ItemsV2 **Phases B + C SHIPPED**; paused for Figma before D/E)

> **Resume prompt (next session):** *"Phases B (the `ItemWindowViewModel`) and C (renderer teardown) are DONE + committed on `itemsv2-interactive-window` — B: `22ed49c..2355f1e` + review/`fireSave` `48015ae` (full target **1302** green); C: `560d855` (C1) + `0c821c6` (C2) (full target **1290** green). **Next is Phases D/E — DESIGN-GATED on Nathan's Figma** (D2 header, D4 segmented property bar, D5 inspector row, E1 templates pane). Get the Figma first; build each gated task's non-visual scaffolding before the visual ask. READ `Planning/06-07-ItemsV2-Plan-V3.md` — its top EXECUTION UPDATE block carries the corrections that MUST flow into D/E/F: the `-only-testing` selector is the TYPE name (`<Name>Tests`) NOT the `@Suite("string")` (string label runs 0 tests); D1/D2 set `PreviewWindow(showsDefaultHeader: false)` + supply the card's own header in `content`; E1 RE-IMPLEMENTS the captured legacy-pin-collapse (its source was deleted in C1). Same loop: subagent authors → background `builder` hard-verifies (NON-ZERO count) → green-commit. Agents lie; the build and the diff don't."*

**Where it started.** Resumed on `itemsv2-interactive-window` at `0cc1ed1` (Phase A shipped). Directive: execute Phase B (B1–B9) via the verified subagent loop; mid-session Nathan added "do a full Phase-B code review with A's discipline, then begin C." Also committed (per his instruction) the 3 parallel-session `.claude/Planning` deletions + de-indexed the README (`7f29b8b`).

**Key moments.** Built the entire `ItemWindowViewModel` B1→B9 (hydration; property/tier/icon/title/body/delete handlers; Add-Property; VM↔manager↔disk↔index round-trip) — each task authored by a fresh subagent, hard-verified via a background builder (non-zero count), green-committed. The builds (not the agents) caught two real defects: a B4 default-arg-references-sibling-param compile error, and a B9 failure proving the integration test must seed the parent Type into a fresh index (quirk #14) — not a product bug. The full-target run then caught 2 debounce tests that passed in isolation but raced under parallel main-actor load → de-flaked (poll-until-condition + deterministic flush). Post-Phase-B review came back clean; folded one DRY consolidation (`fireSave`). Phase C: C1 collapsed the renderer to its live stub and retired the entire archetype/mockup/display path (−946 lines) atomically; C2 made `PreviewWindow`'s built-in header optional via a non-breaking `showsDefaultHeader` (deviation from the plan's "default headerless" to avoid a close/drag regression while D2 is gated).

**Nathan's voice.** Standing rules held all session: terse 1–3-sentence task reports, every agent claim independently EVIDENCE-verified, type-name test selectors with confirmed non-zero counts, never bundle/revert unattributed working-tree changes. He has Figma to hand over before the visual phases.

**Where it left off.** Branch `itemsv2-interactive-window` at `0c821c6`, full target **1290** green, working tree clean. Paused for Nathan's Figma before Phases D/E.

#### Lessons Learned

- **`-only-testing:PommoraTests/<X>` matches the `@Suite`/struct TYPE name, NOT the `@Suite("string")` display label** — the string label silently runs 0 tests (xcresult-confirmed). Always use the type name + visually confirm a non-zero executed count. **→ candidate CLAUDE.md quirk refinement (sharpens #1).**
- **Flaky-timing tests hide in isolation.** Two debounce tests passed via `-only-testing:<suite>` but failed under the full parallel target (main-actor contention starved the timer past a fixed sleep). Verify timing-sensitive logic against the FULL target; prefer poll-until-condition or a deterministic direct flush over fixed-margin sleeps.
- **Layer-confusion check paid off (quirk #17).** B9's "index empty" was a missing test-seed (the parent-Type FK that `loadAll` supplies in the real app), not a product bug. Confirm the layer before "fixing" — and grep-verify every symbol before a large deletion (C1).
- **The subagent-authored / orchestrator-hard-verified loop keeps catching real defects** the agents' own "DONE" missed (B4 compile error, B9 seed gap) — the build and the diff are the truth.

#### Next Session

1. **Get Nathan's Figma, THEN Phases D/E (DESIGN-GATED).** D2 header / D4 segmented property bar / D5 inspector row / E1 templates pane. Build each gated task's non-visual scaffolding first; batch the visual asks into one design checkpoint. Carry the Plan-V3 EXECUTION-UPDATE corrections (type-name selector; `showsDefaultHeader: false` in D1/D2; E1 re-implements the captured collapse).
2. **Phase F** — full-target green → post-functional UIX review (standing gate, runs no matter how clean) → docs (`Features/Items.md` + Paradigm #15 amend + History) → prose-level doc-sweep.
3. **Branch `itemsv2-interactive-window`** merges to `main` after Phase F (or whenever Nathan wants). C sits done between B and the visual phases.

#### Pending Focuses

- **[carried] Item Window — Phases A–C SHIPPED; Phases D–F remain.** Spec `Planning/06-07-ItemsV2-Spec-V5.md`, plan `Planning/06-07-ItemsV2-Plan-V3.md` (execution status + corrections in its top banner). D/E are design-gated on Nathan's Figma.
- **[carried from 06-07]** `markerRanges[0]/[1]` subscripts in `styleItemLinks` (no bounds guard). Can't crash today (tokenizer always emits 2). Add `guard token.markerRanges.count >= 2` if the tokenizer is refactored.
- **[carried from 06-03]** Push `folder-exclusion` → origin — still no upstream, ~30+ commits ahead. (carried 3×+ — confirm still wanted.)
- **[carried from 06-03]** Delete the merged `markdownpm-rehome` branch.
- **Nathan: add `excluded_folders` entries + rebuild once** to clear the meta-file leak. Recommended `The Nexus/.nexus/settings.json` additions: `"Claude"`, `"Pommora/CLAUDE.md"`, `"Pommora/Handoff.md"`. Confirm whether `History.md`/`Framework.md`/`Resources.md` are also non-content.
- **Latent (review-flagged):** pages nested ≥2 folders deep in a collection still missing from the launch index scan (`IndexBuilder` non-recursive `children` vs `loadAll` recursive `descendantFiles`). Fix when it bites.

#### Fix Log

1. **Column reorder broken** — drag-reordering table columns; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show icons); folds into v0.7.0.
5. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
6. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
7. **Agenda description-cap doc mismatch** — specs claim a 1000-char cap but validators enforce none; decide the intended cap or drop the doc claim.
8. **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **ItemsV2 interactive Item Window (Phases A–C BUILT 2026-06-07/08; D–F pending) →** spec `Planning/06-07-ItemsV2-Spec-V5.md`; plan `Planning/06-07-ItemsV2-Plan-V3.md` (top banner carries execution status + the Phase-C corrections); review discipline `Guidelines/Review-Discipline.md`. Built on branch `itemsv2-interactive-window` (`14760b0..0c821c6`). Paradigm #15 amend deferred to Plan-V3 Task F3 (docs).
- **ItemsV2 (SHIPPED 2026-06-03, archetype model — RETIRED) →** as-built `Planning/06-03-ItemsV2-Implemented.md`; the archetype/mockup/display path it described was torn out in Phase C1.
- **Connections (PAGE-LEVEL COMPLETE 2026-06-07) →** spec `Features/Connections.md`; plan `Planning/06-05-Connections-Plan.md`. Item chip click path (`onItemLinkClick` → `ItemLinkOpener.loadItem` → `AppGlobals.presentItemAction`) is the entry to the Item Window.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` · review discipline → `Guidelines/Review-Discipline.md`
- Branch quirks + hard rules → `CLAUDE.md`
