### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything, You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it." ASK ME when you're unsure! Don't make assumptions when asking directly will give concrete directive; honesty is key, confidence must be earned through evidence.*
>
> Proven REPEATEDLY: verify-first recon caught Apple's rule-of-3 can't reproduce the legacy parser; the Phase-4 review caught a real `*`-styling regression 99 green tests missed; LOOK-before-staging caught a parallel session's entry an instant before bundling. **This session adds two:** the recon falsified two of the revert pitch's own premises against code; and the final confirmation gate caught that *my own* multi-round fixes had introduced sequencing bugs (deleting a method before its caller retired, a binding spanning four views, a renderer hitting a popover's partial environment) — verify the *fixes*, not just the original claim.

#### Session Summary

> **Resume prompt (next session):** *"The **ItemsV2 execution plan is written + BULLETPROOFED** at `Planning/06-03-ItemsV2-Plan.md` (6 phases, ~25 bite-sized TDD tasks), built on the locked spec `Planning/06-03-ItemsV2-Spec.md`. It survived five review/correction rounds ending in a clean confirmation gate (**0 blockers / 0 majors**). Next: **commit the planning docs** (curate by path — do NOT bundle the parallel session's work), then **execute via `superpowers:subagent-driven-development` from T1.1** (`LayoutArchetype` — no deps, on-disk strings locked). **CRITICAL collision:** a parallel session is editing the SAME files ItemsV2 touches — `SidebarDetailView` + the four detail views (T4.4's targets) — and added an untracked `DetailFooterBar.swift` + `FooterAddMenuButton.swift` that overlap the ItemsV2 footer (T3.1). Reconcile before executing Phase 3–4. The plan + spec are on disk and survive compaction; everything below is context."*

A **planning + multi-round review session — no app code shipped by me**; the deliverable is the bulletproofed ItemsV2 execution plan. Started from the settled ItemsV2 PRD (written the prior session).

Key moments: (1) **Recon workflow** (research + codebase-mapping) verified every `file:line` and surfaced conflicts. (2) **Locked seven decisions with Nathan** via AskUserQuestion: one config-driven `ItemWindowRenderer` (not 6 stub views); `LayoutArchetype` enum + region-recipe (5 archetypes + 1 reserved + tolerant unknown); native floating-scene window, PreviewWindow-first (zero AppKit on macOS 26.4); per-property display config (`promoted_properties: [{id, display}]`); MarkdownPM 250-cap description; image-filtered `.file` cover; Type-default → Collection-override scope. (3) **Reorder-library bench** — Nathan's two suggested repos (`visfitness/reorderable`, `globulus/...`) lost to **native SwiftUI**: the codebase already owns the drag pattern in `PropertyVisibilityPane`; extract one shared splice, no dependency. (4) **Wrote the plan**, then **five review/correction rounds**: R1 adversarial (crashes/compile), R2 (citations/snowball/simplify/net-reduce — consolidated onto the existing `PropertyCellDisplay`, deleted the legacy pin cluster), **R3 model correction** (Nathan: pinning/order is edited *in the template* via a WYSIWYG "mockup item frame", not the live item), R4 final gate (4 blockers + 5 majors — deletion ordering, the four-view `presentedItem` binding, the popover's partial env), **R5 confirmation gate → bulletproof**.

Nathan's voice: on the libraries — confirmed native-over-dependency once shown the repo already had the pattern; the model correction — *"Re-ordered via the template … a 'template' item will appear, and you can sort around and pin properties in a mockup item frame … applies to the items it governs"*; and the closing bar — *"must be bulletproof."*

Where it left off: on branch **`folder-exclusion`** (no upstream tracking). The **parallel session SHIPPED folder-exclusion** (6 commits, `af0b40a`…`ef49263`) and has since moved to **uncommitted UI work** — modified `DateTimePicker/*`, `PageEditor*`, `PageStatsBar`, **`SidebarDetailView` + all four detail views**, plus new untracked `DesignSystem/DetailFooterBar.swift` + `Detail/FooterAddMenuButton.swift`; it also **deleted** `Planning/2026-06-02-MarkdownPM-CodeMap.md` + `MarkdownPM-Divergence-Ledger.md`. **None of that is mine** (quirk #10 — surfaced, never reverted/bundled). Mine + uncommitted: `Planning/06-03-ItemsV2-Plan.md` + `06-03-ItemsV2-Spec.md` (new), `Planning/README.md`, `CLAUDE.md` (Item-Window directive), this `Handoff.md`.

#### Lessons Learned

- **Verify the fixes, not just the original plan.** A plan revised across multiple rounds needs a *final confirmation gate*: my own round-4 fixes introduced fresh sequencing bugs (deletion-before-caller-retires, a `@Binding` spanning four views, a renderer hitting the View Settings popover's partial env) that earlier passes couldn't have seen. The clean R5 gate is what earns the word "bulletproof."
- **Native often beats the dependency — check the repo first.** The codebase already owned the drag-reorder pattern; the right move was extracting a shared splice, not adopting either suggested SPM lib.
- **Separate the editing surface from the render surface.** Nathan's "edit the template via a mockup item frame" correction made the live window pure-render and put pin/order in the template — one persist path, simpler model.
- **The parallel-session collision is now concrete, not hypothetical.** It edits the exact detail-view files ItemsV2 rewires and is building a footer that overlaps the ItemsV2 footer. Execution must reconcile, not assume a clean tree.

#### Next Session

1. **Commit the ItemsV2 planning set** — `Planning/06-03-ItemsV2-Plan.md`, `06-03-ItemsV2-Spec.md`, `Planning/README.md`, `CLAUDE.md`, `Handoff.md`. **Curate by path** — do NOT bundle the parallel session's `Pommora/Pommora/*.swift` changes, the new `DetailFooterBar`/`FooterAddMenuButton`, or the MarkdownPM-doc deletions.
2. **Reconcile ItemsV2 ↔ the parallel UI work** before Phase 3–4: the parallel session's `DetailFooterBar`/`FooterAddMenuButton` overlaps T3.1's footer, and its detail-view edits collide with T4.4's `presentedItem` rewire. Decide whether ItemsV2 builds on `DetailFooterBar` or replaces it.
3. **Execute ItemsV2** via `superpowers:subagent-driven-development` from **T1.1** (`LayoutArchetype`; pure data, no deps). First commit = T1.1.

#### Pending Focuses

- **[CRITICAL — new] Parallel-session file collision.** It modified `SidebarDetailView` + the four detail views (ItemsV2 T4.4 targets) and added `DetailFooterBar.swift` + `FooterAddMenuButton.swift` (overlaps T3.1's footer). All uncommitted, all in `Pommora/Pommora/`. Reconcile before executing ItemsV2 Phase 3–4; never revert/bundle (quirk #10).
- **[new] MarkdownPM docs deleted in the working tree** — `2026-06-02-MarkdownPM-CodeMap.md` + `MarkdownPM-Divergence-Ledger.md` (not me; the Plan doc survives). Confirm the deletion was intended; the `README.md`/pointers reference them.
- **[carried] Push → origin** — branch has no upstream tracking; was 105+ ahead. One push when wanted.
- **[carried] My ItemsV2 planning docs uncommitted** (see Next Session #1).
- **[carried] v0.4.0 roadmap** — Symbols / Trash / **Wikilinks** + file-watcher + FTS5; the ItemsV2 `@item` chips + graph edge-weighting connect here (deferred per LD-11).
- **[carried] Delete `markdownpm-rehome`** — merged; safe to remove.
- **[done] folder-exclusion** — SHIPPED by the parallel session (6 commits); drop from the carry list.

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns*; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into v0.7.0.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels.
6. **Settings popout sizing** — should size to content dynamically.
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
8. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
9. **"Add new" footers on views** — adjust to allow a navigation breadcrumb on the left. _(The parallel `DetailFooterBar` may already touch this — confirm.)_
10. **Item Window property double-render** — **scheduled fix: ItemsV2 T3.3** resolves it structurally (promoted/overflow are disjoint sets in the single renderer).

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **ItemsV2 (PLAN, bulletproofed — ACTIVE) →** `Planning/06-03-ItemsV2-Plan.md` (6 phases, ~25 TDD tasks; records all 5 review rounds in its self-review) · spec `Planning/06-03-ItemsV2-Spec.md` (locked model + Figma window-surfaces + landmines). **Execute from T1.1.**
- **MarkdownPM (SHIPPED, merged) →** `Planning/2026-06-02-MarkdownPM-Plan.md` (Execution Record = canonical phases/commits). _(Note: the CodeMap + Divergence-Ledger companions were deleted in the working tree this session — see Pending Focuses.)_ · markdown behavior → `Guidelines/Markdown.md` · gate: `External/MarkdownPM/run-tests.sh`.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md` · Wikilink spec → `Features/Wiki-Link.md` (v0.4.0 wikilink session; owns the ItemsV2 `@item`/graph thread)
