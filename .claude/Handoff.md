### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.
>
> Proven AGAIN this session: when the plan looked done, Nathan said *"do another review pass, I'm sure you can find something."* He was right — a third adversarial round (run at deeper lenses than the first two) caught **real** lifecycle bugs the compile-focused rounds missed: a phantom connection that never re-activates after a duplicate is deleted (a spec violation), `EntityStateRef.kind` being a `String` not an `EntityKind` (a latent compile error), and a rename "phantom window." Never declare a plan bulletproof from your own confidence; earn it by attacking it from angles you haven't tried yet.

#### Session Summary

> **Resume prompt (next session):** *"Connections is mid-build. The plan is `Planning/06-05-Connections-Plan.md`; Phases A+B (the index foundation) shipped GREEN — 8 commits `f04de8e`→`8be67f3`, full PommoraTests 1217/0 at HEAD `8be67f3`. Resume execution at **Task C1** (nexus-wide title uniqueness) via `superpowers:subagent-driven-development`, then D1/D2/E1–E5/F1. One task per fresh implementer; implementers DON'T build — verify each via a background `builder` Agent (quirk #13) run from the `Pommora/` subdir, `-only-testing:PommoraTests`, confirm ~1217 count. Test fixtures: `TempNexus.make()` → `PommoraIndex.open(at:)` → `IndexUpdater(index)`/`IndexQuery(index)`; a `pages` insert needs a `page_types` parent seeded (INSERT OR IGNORE) for the FK; on-disk rebuild tests follow `RebuildResilienceTests`. Trust the plan's round-3 fixes — they're folded in."*

**Where it started.** Opened at HEAD `25cbdae` (post-Contextv2, green) with the prior handoff's Next Session #1 = "scope the Connections implementation plan." The Connections feature was spec'd (`Features/Connections.md`) but unbuilt; the graphify graph (5,162 nodes) was already on disk from the prior session.

**Key moments.** (1) **Recon** — 4 source-verified agents mapped the spec against the code and surfaced the load-bearing landmines: no file-watcher (just a comment), no graph view, no restore-from-trash, item bodies display-only, `[[ ]]` is a *dead wire today* (no `onLinkClick` wired + a no-op resolver), and `makeStorageState` would corrupt bodies with `[[Name|id]]` absent LD-28. (2) **Plan** — wrote `Planning/06-05-Connections-Plan.md` (6 phases A–F, ~18 TDD tasks) after Nathan locked scope via four questions: both `[[ ]]` + `{{ }}` functional with `{{ }}` as a **plain-link placeholder**, file-watcher deferred, live-visibility = editor+index, adoption tolerates dups (picker lists both), cascade needn't be instantaneous. (3) **Bulletproofing** — 3 adversarial rounds (round 1 structural blockers → round 2 cosmetic → round 3 lifecycle/harness/edge), each consolidated + applied; round 3 was the one Nathan insisted on and it paid off. (4) **Side-task** — a delegated agent raised the item-description cap 250→500 (`ItemValidator.maxDescriptionLength` + ~10 docs) before the review round so it wouldn't get flagged. (5) **Execution** — subagent-driven, Phases **A+B shipped green**: A1 retire `_wikilinks` (`f04de8e`), A2 LD-28 id-strip (`25ba1b3`), B1 connections table + schema v8 (`f56d34b`), B2 scanner (`6886988`), B3 reconcile/activate/deactivate (`3c4f044`), B4 read queries (`009c023`), B5 cold-start scan (`c1562f9`), B6 live CRUD hooks across all 12 create/update/delete overloads (`8be67f3`). Two fixtures needed controller fixes mid-flight (a `pages` NOT NULL/FK violation, a stale LD-28 test pin) — caught by the background builder, not the implementers.

**Nathan's voice.** *"Do another review pass, I'm sure you can find something"* — and there was. *"Don't report back exhaustive reports; simple 1-2 sentence updates… you have full permission to STOP and ASK."* *"Cascade renaming doesn't have to be 'immediate', a 300ms buffer means jack shit lmao"* — killed an over-engineered coordination landmine. On scope: *"Both work; establish the functionality for both; use plain-link for items as a placeholder for proper chip UI."* *"Finish this phase and update the handoff to resume in a freshly compacted context window."*

**Where it left off.** HEAD `8be67f3`, full suite **1217/0**. Phases A+B done; **C1 is next.** Working tree is dirty with uncommitted docs (last session's Connections reconciliation + this session's cap-bump), the plan + `Connections.md` (untracked), and `graphify-out/` — Nathan stages these himself.

#### Lessons Learned

- **A "bulletproof" plan isn't bulletproof until attacked from un-tried angles.** Rounds 1–2 were compile/structure focused and converged to cosmetic; round 3 (test-harness reality, runtime concurrency, spec-lifecycle edge cases) found genuine bugs. Vary the lens each round, don't just re-confirm. **→ candidate CLAUDE.md quirk.**
- **The background builder is the real spec gate, not the implementer's report.** Two tasks reported DONE but were red (a `pages.page_type_id` NOT NULL violation; a stale `[[Name|id]]` test pin). Implementers can't build (quirk #13), so EVERY task must be controller-verified before "done."
- **Test fixtures: a `pages` row needs a `page_types` parent.** `INSERT INTO pages` with `page_type_id = NULL` throws SQLite-19 (NOT NULL + FK). Seed `INSERT OR IGNORE INTO page_types …` first. The `connections` table itself has no FK, so phantom/dangling `target_id` is safe.
- **Right-sizing reviews to task complexity worked.** Build-green as the gate for mechanical tasks + behavioral-test-as-spec for logic tasks (no separate reviewer agents) kept the loop fast and honored Nathan's token economy — the plan code was already thrice-reviewed.

#### Next Session

1. **Resume the Connections build at Task C1** (`superpowers:subagent-driven-development`, plan = `Planning/06-05-Connections-Plan.md`). Order: **C1** nexus-wide per-kind title uniqueness (index-backed `titleExists`, both create/rename paths, all overloads) → **D1** atomic rename cascade (`ConnectionRewriter` + `SchemaTransaction`, all 4 rename overloads, revert-on-failure, then `activateConnections` after `upsertPage`) → **D2** pinned/recents title refresh (closes Fix Log #9) → **E1–E5** editor (inject `PommoraConnectionResolver`; wire `onLinkClick`→page nav; `{{ }}` tokenizer + plain-link styler + `.itemLinkTitle` attribute; `{{ }}`→Item Window bridge; autocomplete) → **F1** ItemChip stub. Each: fresh implementer, TDD, controller-verify via background builder, green commit. Carry the methodology in the resume prompt above.

#### Pending Focuses

- **[carried from 06-05]** Contextv2 loose ends — commit the untracked `Planning/Contextv2.md`; decide the unattributed `Planning/` deletions (`06-03-ItemsV2-Plan.md`, `2026-05-31-…interim.md`, two `Superseded/*`). Don't blind-revert (quirk #10). Was last handoff's Next Session #2; the Connections build took priority. (carried 2× — confirm still wanted)
- **[carried from 06-03]** Push → origin — `folder-exclusion` has no upstream, now 50+ commits ahead. (carried 3×+ — confirm still wanted)
- **[carried from 06-03]** Delete merged `markdownpm-rehome` branch.
- **[new]** Stage the uncommitted working tree when ready — the 250→500 cap-bump (`ItemValidator.swift` + ~10 docs), `Features/Connections.md`, last session's reconciled docs, the plan doc, `graphify-out/`. All intentional; none auto-committed.

#### Fix Log

1. **Column reorder broken** — drag-reordering table columns; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show icons); folds into v0.7.0.
5. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
6. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
7. **Agenda description-cap doc mismatch** — specs claim a 1000-char cap but validators enforce none; decide the intended cap or drop the doc claim. (Distinct from the Item description cap, which was raised 250→500 this session.)
8. **Page / Heading Jerk** — the caret-in-heading jerk fix is **no longer in the working tree**. Confirm it was committed before treating as closed.
9. **Title changes don't update pinned nav** — **now scheduled as Connections Task D2** (pinned/recents title refresh on rename); close when D2 ships.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Connections (BUILDING 2026-06-05) →** spec `Features/Connections.md`; plan `Planning/06-05-Connections-Plan.md` (page `[[ ]]` + item `{{ }}` inline links). **Phases A+B shipped** (`f04de8e`..`8be67f3`, suite 1217/0); **C–F pending** (resume at C1). Recon + 3-round bulletproofing folded into the plan.
- **Drop Relations → Contexts (SHIPPED 2026-06-05) →** `Planning/Contextv2.md` (as-executed; 12 commits `f2e96c6`..`25cbdae`). Ship log → `History.md`; locked decisions → `Paradigm-Decisions.md` #16.
- **ItemsV2 (SHIPPED 2026-06-03) →** as-built `Planning/06-03-ItemsV2-Implemented.md`; rework design `Planning/06-03-ItemsV2-Planned.md` (zone framework — a candidate next build). Item desc cap raised 250→500 (2026-06-05).
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
