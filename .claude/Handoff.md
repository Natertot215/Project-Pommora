### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything, You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it." ASK ME when you're unsure! Don't make assumptions when asking directly will give concrete directive; honesty is key, confidence must be earned through evidence.*
>
> Extended this session: **a gate answer of "execute" is NOT a license to auto-start building.** Nathan answered "Grep + execute Phase 1" at the approval gate; the agent launched the rename build subagents immediately. Nathan: *"I did not tell you to start."* Close the gate (answer the open decisions), get a deliberate **go**, THEN execute. Also proven: **verify the dependency's source AND verify your own edits** — the plan's multi-round loop caught that round-1 fixes introduced their own regressions (an `LD-20` mis-pointer, a non-existent zero-arg init) that later rounds had to fix. Adversarial rounds apply to your own corrections, not just the original claim.

#### Session Summary

> **Resume prompt (next session):** *"The MarkdownPM rebuild plan is **FINAL + committed** (`f37790c`) at `Planning/2026-06-02-MarkdownPM-Plan.md` (2,905 lines, 36 tasks); the verified code map is `Planning/2026-06-02-MarkdownPM-CodeMap.md`. It went through a 22-agent code-map → 3 forks ruled → v3 draft → **3 adversarial review rounds** (blocker→major→minor→cosmetic convergence, every fix verified). Execution was **prematurely started and cleanly reverted** — the worktree isolation meant main was never touched; the green baseline is verified (**1153/0 tests, package `Build complete!`**). **DO NOT auto-start execution.** The approval gate is now CLOSED (answers folded into the plan 2026-06-02: emphasis-inside-code = suppress; new heading scale `[2.0,1.75,1.5,1.25,1.15,H6-TBD]`; tables = keep engine rendering but refinable; cosmetic Phase-5 defaults ratified). The **one open value is the H6 heading multiplier** (Nathan set H1-H5; H6 unspecified — confirm it). First: confirm H6 + get a deliberate **go**. THEN execute Phase 1 in an **isolated git worktree off `main`** (NOT an in-place branch — parallel sessions are active and share the working tree): Task 1.1 baseline → 1.2 atomic rename → 1.3 pkg-root rename → 1.4 docs, via `superpowers:subagent-driven-development` (implementer → spec review → quality review per task). Phases 2-6 follow; the build is gated on the Phase-2 characterization net before any behavior change."*

A **planning-to-the-finish** session, entirely workflow-driven. Opened mid-plan (prior session left plan v2 at NEEDS-V3); Nathan redirected hard: *"we're wasting time sending subagents against a design doc; we're planning the implementation. Use WORKFLOWS to send 20 subagents to map dependencies + locations into a report; those get assessed by plan-creating agents to make v3; then revise-and-lock until bulletproof."* That became the whole session.

- **Map workflow (`wd8w1pdqf`, 22 agents → CodeMap).** Verified every dependency + `file:line` against actual source, producing `MarkdownPM-CodeMap.md` + a claims-verification ledger that caught the v2 doc's errors (15 vs 14 init params, 4 vs 6 styler extensions, the dual-styler-merge being **two** sites not one, `ParsedDocument` holding only regex tokens not the Apple AST, the supplemental styler re-parsing the whole doc every keystroke = the #9 culprit, two dead code paths). Verdict: sufficient to write Phases 1-3 in full + outline 4-6.
- **Three forks ruled by Nathan:** underscore emphasis = **ADOPT** (`_italic_` newly works); the two heading detectors = **UNIFY** (DRY, behind the net); DEC-1 id-guard = first "structural lock," then **deferred entirely to the separate Wiki-Link session** ("we don't need to scaffold that yet — note where it exists, decide later"). Also surfaced + corrected Nathan's premise that "Obsidian uses IDs" — Obsidian resolves by **filename**; Pommora's ULID-in-frontmatter is already the portable identity, so the link stays plain `[[Title]]` and never embeds an id.
- **Plan-creation workflow (`w3z786uob`) → controller-assembled v3.** The single-agent assembler hit an output ceiling (truncated a 3,000-line doc); fixed by resuming to return the 5 raw sections and assembling controller-side. Result: 2,905 lines, full bite-sized TDD for Phases 1-3, concrete outline for 4-6, Nathan's rulings folded in as `Locked Decisions` (LD-1..LD-32).
- **3 adversarial review rounds** (6 lenses each: code-check · skeptic · simplify · approval · plan-YAGNI · design-YAGNI, the last two added on Nathan's "look for over-engineering"). R1: 4 substantive Phase-2↔3 seam bugs + ~300 lines of ceremony. R2: 11 precision/regression fixes (several were R1's own regressions). R3: **zero blockers/majors**, 7 cosmetic nits. Each round's fixes hand-applied + grep-verified. Design verified sound throughout (no scope/architecture problems — the over-engineering was in the plan *wrapper*, not what it builds).
- **Finalized + committed `f37790c`** (scoped: Plan + CodeMap + README; folded Decisions doc removed; v2 Service doc → `Superseded/`). Stale-reference grep against live code: clean (editor tree untouched by parallel sessions; all load-bearing citations exact).
- **Premature execution + revert.** At the gate Nathan chose "Grep + execute Phase 1"; the agent created an isolated worktree, ran Task 1.1 (**baseline green: 1153/0 + `Build complete!`**), and launched Task 1.2 (atomic rename — got through the `Package.swift` manifest edit). Nathan: *"I did not tell you to start. Revert (keep lessons)."* Worktree + branch removed; main untouched.
- **Where it left off:** plan FINAL + committed; execution reverted; gate **not yet closed** (open decisions below await Nathan); next session executes only after a deliberate go. Main tree carries Nathan's parallel doc edits (untouched).

#### Lessons Learned

- **"Execute" at a gate ≠ "start now."** When clarifications or a compaction are pending, a proceed-answer means *prepare + close the gate*, not *launch build subagents*. Get an explicit go. **→ candidate CLAUDE.md quirk.**
- **Verify your own edits, not just the original claim.** The v→vN loop caught that round-1's fixes introduced fresh regressions (LD-20 swept into the wrong phase's pointer; a `NativeTextViewCoordinator()` init that doesn't exist). Hand-edits get adversarially re-checked too.
- **A single agent can't re-emit a ~3,000-line doc** (output ceiling) — partition by section and assemble controller-side. The map/draft/review workflows all worked per-section to dodge this.
- **Worktree-from-committed-`main` is the correct isolation when parallel sessions are active** — an in-place `git checkout -b` would hijack the shared working tree (and Xcode) the parallel sessions use. The worktree made the revert free (main never touched). The plan's Task 1.1 still says in-place branch (written when the parallel session was assumed dormant); **next session must use a worktree instead.**
- **Adding YAGNI/over-engineering lenses pays off** — they confirmed the *design* was right-sized and concentrated the cuts on the plan's ceremony (repeated Locked-Decisions blocks ×4, per-task quirk boilerplate ×33, 18 heredoc commit blocks).

#### Next Session

1. **Close the approval gate** — get Nathan's answers to the open decisions (the questions block in this session's chat + Fix Log items): emphasis-inside-code suppression, H5/H6 sizes, and the Phase-5 cosmetic defaults (table markers / services seam / find-highlight / config prune). Fold answers into the plan's outline.
2. **Then execute Phase 1** (only on a deliberate go) in an **isolated worktree off `main`**: 1.1 baseline (already verified 1153/0) → 1.2 atomic rename → 1.3 pkg-root rename → 1.4 docs reconciliation, via `superpowers:subagent-driven-development`. Re-assess between green commits.
3. **Continue Phases 2-6** — Phase 2 (characterization net) is the hard gate before any behavior change (Phases 3-6).

#### Pending Focuses

- **[active] MarkdownPM rebuild — plan FINAL + committed; execution pending Nathan's go.** Plan: `Planning/2026-06-02-MarkdownPM-Plan.md`; map: `Planning/2026-06-02-MarkdownPM-CodeMap.md`.
- **[gate ANSWERED 2026-06-02, folded into the plan + divergence ledger]** emphasis-inside-code = **suppress** (D-EMPH-2, matches Apple); heading sizes = **new scale** `[H1 2.0, H2 1.75, H3 1.5, H4 1.25, H5 1.15, H6 TBD]` (D-HEAD-2 — **H6 is the one open value to confirm**; no heading below body; pad proportionally); tables = **keep engine rendering but keep it refinable** (D5.1-a; proper tables are a future focus); the cosmetic Phase-5 defaults (services seam separate, find-highlight as-is, keep all config sub-structs) **ratified**. Underscore-emphasis + heading-detector-unify also confirmed ACCEPTED in the ledger.
- **[carried] Push `main`** — the whole planning arc + `f37790c` are committed but unpushed.
- **[carried] v0.4.0 roadmap** — Symbols / Settings / Trash / **Wikilinks** (now explicitly the post-MarkdownPM session that also owns the DEC-1 id-guard + the unified-ID-vs-Obsidian on-disk format) + file-watcher + FTS5.
- **[gated]** Retire legacy-Item-JSON migration machinery (`Prospects.md`) once every nexus has run the `.json`→`.md` migration.

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns*; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into v0.7.0.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels.
6. **Settings popout sizing** — should size to content dynamically.
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
8. **Backspace on a checkbox / list item** should auto-delete the syntax — **confirmed UNIMPLEMENTED** (CodeMap: zero such code); explicitly OUT of the rebuild scope (a feature-add, not a refactor) — recorded as deferred new work.
9. **Page editor per-caret re-parse glitch** — **addressed by the MarkdownPM rebuild Phase 3** (single cached parse spine; the supplemental styler re-parses the whole doc every keystroke today). Not a standalone fix.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Planning →** `Planning/2026-06-02-MarkdownPM-Plan.md` (FINAL, committed `f37790c`) · `Planning/2026-06-02-MarkdownPM-CodeMap.md` (verified code map) · `Planning/Superseded/2026-06-02-MarkdownPM-Service.md` (v2 design, superseded) · `Planning/Superseded/2026-06-01-Items-as-Markdown-Plan.md` (shipped). Wikilink spec: `Features/Wiki-Link.md` (the wikilink feature + DEC-1 id-guard are a separate post-rebuild session).
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` (**#7 "vendored swift-markdown-engine" → reconciled to MarkdownPM-owned in the rebuild's Phase 1 Task 1.4**)
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
