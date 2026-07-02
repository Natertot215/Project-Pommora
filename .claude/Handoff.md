## Handoff — Pommora React

One long session: shipped PropertiesV2 end-to-end, ratified the Tables Next-Parts brainstorm, then **built + shipped Tables Phase 1** (9 green tasks, Nathan's visual sign-off) and rode his live-testing feedback through a large fixup wave — capsule/seed picker semantics, tier/context pickers, Clear menus, the DRY OverflowScroll, the **Apple overflow model (elastic title reverted)**, the conditional inspector — closing with a full adversarial review sweep (7 findings fixed + 1 latch bug the reviewer missed, caught by live CDP verification). Parked green on `main`, 939/939 tests, ~23 commits this window.

**Session ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Dates:** 06-27-2026 → 07-02-2026

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

**Model:** Opus 4.8 → Fable 5
**Compactions:** ~13 (best-effort; multi-window session)
**Connectors:** Figma MCP (early — Switch component); Electron CDP for live screenshots + UI drive (not MCP)
**Agents:** general-purpose (perf audit ×1, adversarial reviews ×6+), code-simplifier (×3), build-breaking-agent (×1 — the Phase 1 post-green sweep)
**Skills:** handoff; `superpowers:brainstorming` / `writing-plans` / `executing-plans`; `studio-brainstorm`

**Tables Phase 1 SHIPPED + signed off (07-01):** the full gesture matrix is live — title navigates (row-click narrowed), status/select/multi/context cells open the `PropertyPicker` (PickerMenu-based, Solid variation), checkbox-look status cycles its group on valued cells and pickers on empty ones (capsule-chip options), numbers inline-edit via `PropertyEditor` (keystroke-filtered; empty commit clears via `setProperty null`), links/files open through sanctioned IPC, right-click always menus (per-type Style radios + Clear on picker-based cells, title Rename/Change Icon/Delete). Styles persist per-view in `column_styles` (per-KEY fold in `mergeOverrides` — an entry-level spread wipes sibling keys). The reusable editing surfaces live table-agnostic in `Detail/Views/PropertyEditing/` for Gallery/List reuse (Nathan's DRY directive). → `Features/TableView.md`.

**The Apple overflow model — elastic title REVERTED (07-01):** Nathan's live testing overturned the prior session's elastic-`minmax` title: it made the title the shock absorber for every resize ("new columns only compress the tight-view; theres no room affordance") and per-type max caps made resizes hit an immovable wall. Now every column holds its resolved width, all maxes are uncapped (mins stay), and overflow h-scrolls the whole view past the pane — capped-with-filler when fitting, right inset flattened while overflowing (`--table-right-inset` + the `overflowing` class from ONE table-level RO). His reference: Apple's tables ("when a column doesnt extend... it stays capped; when you extend beyond... the table becomes scrollable"). → `Features/TableView.md` §Overflow & Scroll.

**Conditional inspector (verified live):** a fitting table compresses for the inspector as before; an overflowing one keeps its width and h-scrolls beneath the hovering glass (`Detail.css` `:has(.table-view.overflowing)` drops the compressed padding). The first cut latched: fit was measured via `scrollWidth`, which floors at `clientWidth`, so once lifted the flag could never release — fixed by comparing the KNOWN column sum (`reflowRef`, zoom-adjusted) against the hypothetical compressed pane (`e4e1b54`). Both states CDP-screenshot-verified. Kill switch if it ever misbehaves: delete the `:has` rule + the `liftedBy` branch in TableView's `check()` — the core overflow mechanics don't depend on it.

**DRY OverflowScroll (07-01):** Nathan caught that the title truncation didn't reuse the sidebar's row mechanism ("WE DRY-ed that mechansim for a reason"). Now `design-system/components/OverflowScroll.tsx` is THE shared truncate-hover-scroll box — icon rides INSIDE the scroll box with the text, rAF `slideScrollBack` bounce-back (hoisted; the sidebar imports it), and a two-edge eclipse fade so clipped content NEVER hard-cuts (his Active/Closed chips screenshot). Wrapped around every cell content type: title, chips, dates, numbers, links.

**Review sweep (7 findings fixed, `34429aa` + `e4e1b54`):** build-breaking-agent post-green attack. Fixed: the per-cell ResizeObserver cliff (≈3000 ROs on a big table → one debounced epoch broadcast via `OverflowMeasureContext`; hover/scroll keep single cells honest), the overflow RO never re-binding after empty→populated, per-file write serialization in main (`serializeOnFile` — rapid picker toggles could land out of order, the registry race one level down), value-only ops (`setProperty`/`setTier`) skipping the full-nexus `load()` re-walk (the watcher settles canon), a mid-Bloom picker click gate, a PropertyEditor unmount flush (StrictMode-guarded), and `TableView.md` restated to the fixed-track model. The reviewer called the inspector guard "sound" — the live CDP check proved it was a one-way latch anyway: agents' verdicts are hypotheses too.

**PropertiesV2 SHIPPED (07-01):** definitions nexus-wide in `.nexus/properties.json`, sidecars hold assignment-id arrays, `readNexus` joins, `schema:*` re-backed so PropertiesPane never changed; registry mutations serialized (review-caught race); SQLite v16 pure mirror. Net +163 code lines. → `History.md` 07-01. Plan 2's Max-Properties gate + B-7 option colors: this doc + the Tables log are the record (spec pruned).

**Seed options aren't values (07-01):** Nathan's model — the default creation seeds (Not started/In progress/Done) are scaffolding, not defined options; a seed-only def pickers EMPTY (`isUntouchedSeed`, the picker's proportioned empty pane is interim UX). For testing (no creation UI yet) the REAL Nexus registry's status def was hand-edited to Open (upcoming) / Active (in_progress) / Closed (done) and 4 page values migrated to match. New `setTier` mutate op backs the tier pickers (bare `tier1/2/3` arrays via `setPageTier`, per-path serialized).

**Sidebar drag-lag fixed (`2f4cb83`):** the same per-pointermove O(rows) rect storm the table had — snapshot-at-activation now house standard; the inverted-justification root cause captured in `Features/PommoraDND.md` §Measurement discipline.

**Lessons Learned**

- **"Please confirm" means STOP and talk, then wait.** Nathan: "TALK dont just go into fixing... You got away with it because it worked — but dont do that again." State the understanding, end the turn, implement on his go-ahead. → memory `feedback-confirm-means-stop-and-talk`.

- **`scrollWidth` floors at `clientWidth`** — any "is content bigger than the box" comparison that subtracts a hypothetical from `clientWidth` while comparing against `scrollWidth` is a one-way latch. Compare KNOWN content size (state) against the box, not a floored measurement.

- **A pipe masks an exit code.** `vitest run | tail` exits with tail's 0 — one broken test rode into a commit that way. Capture to a file, check `$?` directly (`> /tmp/out; VE=$?`).

- **React 19 does not delegate `scroll`.** `onScroll` on an ancestor never fires for a descendant's scroll; use a native capture-phase listener — or own the node (a component binding its own `onScroll` is fine).

- **Diagnose the real complaint in code before asking.** → memory `feedback-diagnose-before-asking`.

**Key Files & Insights**

- `Detail/Views/PropertyEditing/` — the table-agnostic editing home: `PropertyPicker` (+ `StatusCapsule`), `PropertyEditor`, `statusCycle` (fixed 3-group cycle + glyph map), `formatValue` (Swift-parity, en-US pinned, local-midnight date parse). Gallery/List mount these as-is later.
- `design-system/components/OverflowScroll.tsx` — THE overflow mechanism (fade + hover-scroll + bounce-back + `OverflowMeasureContext` epoch); the sidebar shares `slideScrollBack`.
- `Detail/Views/Table/TableView.tsx` — gesture routing (`onCellClick`/`openCellMenu`/`cellOverlay`), the overflow check (column-sum vs pre-compression pane), per-view style state. Still no virtualization/memo on rows — the standing perf debt, now hotter with cell interactivity.
- `shared/columnStyles.ts` + `Table/columnStyles.ts` — type+zod+defaults live shared (main needs them for menus); the schema-aware `styleFor` resolver is renderer-side (mirrors `columnAlign`) because `shared/` can't import the pipeline's `declaredType`.
- `main/mutate.ts` `serializeOnFile` — per-path write chain for the hot value ops; the pattern to reuse for any read-modify-write on user files.

**Landmines**

- **The dev app runs against Nathan's REAL Nexus.** Value writes via the UI are his data; automated CDP must never pick/commit — open + Esc only. The registry + 4 Guides pages were hand-migrated to Open/Active/Closed at his direction.
- **Parallel sessions** — stage explicit paths, never `-A`. (`Handoff - B.md` is deleted + committed; solo doc now.)

**User Feedback**

- Talk-first (see Lessons). Screenshot-verify visual claims — he asked for the inspector proof shots, and they caught the latch.
- Seeds/groups must never register as pickable options; the picker for a no-options def should show an EMPTY pane (interim), real UX later.
- Capsule = the icon-only chip in the token set (showcase "Select"); picker options follow the column's glyph look.

**Uncertain**

- Whether the interim empty-picker pane (a bare spacer) survives Nathan's "I'll think of a UIX solution later" — don't polish it until he decides.

---

### Working Notes

- UI iteration runs in **dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R** and **`src/main`/preload need a dev-server restart**. The app is currently running WITH `POMMORA_DEBUG_PORT=9222` (launched by Claude; relaunch recipe: `env -u ELECTRON_RUN_AS_NODE POMMORA_DEBUG_PORT=9222 npm run dev`).
- CDP tooling in the scratchpad: `cdp-shot.mjs` (screenshot/eval/clip) + `cdp-emulate.mjs` (viewport emulation — how the inspector states were verified without touching the window). **Reading** a screenshot surfaces it to Nathan.
- **Never run a mutating gesture against the running app** — real Nexus. Drag-and-abort / open-and-Esc only.
- **PropertiesV2 net +163 code lines** (20,063 → 20,226 via `scratchpad/count-loc.py` — reuse that script for LOC deltas). Locked decisions → `History.md` 07-01.
- The REAL Nexus status def now holds Open/Active/Closed (test data, hand-written); `isUntouchedSeed` correctly reads it as "touched," so pickers show the three options.

### Next Session — Phase 2, Then Phase 3

Phase 1 is closed (built, reviewed, simplified, visually signed off). Next: **Phase 2 — band drag**, its own short plan → review loop → in-line build: vertical band reorder always per-view (structural grouping needs the net-new flat set-id array schema extension), Set reparenting = fs `moveSet` with the order-leak guard (destination's CURRENT fs order + moved id appended), the glyph (Set icon+name) is the drag surface — no handles (C-6), full-tree walking, ungrouped band pinned. Ride PommoraDND's frozen-snapshot discipline. Then **Phase 3 — chips**: the hover-reveal (×) remove (DRY'd into the chip components; **on a capsule the × floats ~4px right of the chip** — it can't sit inside) + the chip slide mechanic. Spec: `Planning/7-1 - Tables Next-Parts … Decision Log.md` §C + §E.

### Pending Focuses

- **View-Settings property creation/management pane: design-complete, ready to implement.** Nathan: the entire property creation + management ViewPane is already designed in Figma and shipped in similar form in the Swift build — pull the Figma design + Swift precedent when building. Folds in PropertiesV2 Plan 2's assign surface (assign-existing `+` picker over the registry, Remove-vs-Delete, global-clash nudge, lossy changeType strip, **B-7 per-option status colors**, Inspector's assignment gate) — **MUST stop and ask Nathan about "Max Properties"** when building it.
- **Per-style minimum column widths + slide animation (idea, Nathan 07-01):** each look carries its own column min (checkbox min < capsule min < pill min); when an at-minimum column's style changes to a wider look, the width "slides" to the new minimum with an animation. Design-note only for now.
- **Empty-picker UX** — the proportioned empty pane is interim; Nathan will design the real no-options affordance (creation entry point?) later.
- **Conditional-inspector kill switch** — if it ever fights the overflow mechanics: delete the `Detail.css` `:has(.table-view.overflowing)` rule + the `liftedBy` branch in TableView's `check()`. Verified working via CDP 07-01 (screenshots delivered).
- **(Perf) Table-view architecture redo** — `source`-identity stabilization (the multiplier), `React.memo` on the row/cell path, **virtualization** (the review re-flagged it: every row mounts, now with interactive cells), `loadValues` caching. The "on every X" rule's remaining debt.
- **Row grips on horizontal scroll** — freezing them = a frozen title column; Nathan's call, deferred.
- **Block Drag V2 — nesting** (separate spec): interior drop-slots inside callouts, the box-nesting guard table, cross-container re-prefix.
- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build.
- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

### Fix Log

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either half corrupts the document (`MarkdownPM/editor/blockModel.ts` — test-pinned, unguarded).
- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → `Features/MarkdownPM.md` § Known Issues.

### Handoff Rules

- **Resolve = delete + route, never tag.** When an entry here is genuinely done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.
- **One block per session, updated in place.** Compactions bump the `Compactions` count, they don't add sections. Carry still-open Pending Focuses forward to a fresh sequential session.
- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.
- **Parallel sessions share this one doc** — a concurrent session adds its own labeled block; the Cornerstone + footer are shared; never edit another session's block.
