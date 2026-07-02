## Handoff — Pommora React

One long session: shipped PropertiesV2 end-to-end, ratified the Tables Next-Parts brainstorm, **built + shipped Tables Phase 1** (9 green tasks, Nathan's visual sign-off) plus his live-testing fixup wave (capsule/seed picker semantics, tier/context pickers, Clear menus, the DRY OverflowScroll, the **Apple overflow model — elastic title reverted**, the conditional inspector), a full review sweep, planned + ratified Phase 2 through two adversarial rounds — and then **EXECUTED Tables Phase 2 (band drag) end-to-end overnight under Nathan's contract**: T1–T6 in-line (one green commit each), a post-green build-breaker (3 findings fixed) + simplifier pass, and the FULL T7 live-CDP functional pass with authorized real drops against the real Nexus (structural reorder + sidecar/sidebar proofs, a reparent round-trip with real folder moves, a property-band drop — all screenshot-evidenced, all state restored). A second review round (Nathan's morning ask) added sub-set↔set + sub-set→root reparent proofs and a second breaker pass (3 findings shipped in `3893fb4`). Then the daytime arc: a **quantified perf audit + five-commit fix wave** (band snapshot index, var-driven column drag, parse-once value cache, tree structural sharing, memoized rows), the **pick-closes-the-picker fix** (a propagation boundary — the option click was re-opening it through the cell's own onClick), and the **conditional-inspector teardown** (Nathan's call after live use; the inspector now compresses unconditionally). Green on `main`, **1003/1003 tests**; two full simplifier passes + a DRY sweep (`gapShift` unified, `DROP_LINE_INSET` hoisted to the shared interactions vocabulary); every doc reconciled and committed.

**Session ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Dates:** 06-27-2026 → 07-02-2026

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

**Model:** Opus 4.8 → Fable 5
**Compactions:** ~14 (best-effort; multi-window session)
**Connectors:** Figma MCP (early — Switch component); Electron CDP for live screenshots + UI drive (not MCP)
**Agents:** general-purpose (adversarial reviews ×6+), code-simplifier (×5 across Phase 1/2 + the full-day pass), build-breaking-agent (×3 — Phase 1 sweep, two Phase 2 rounds, the perf audit)
**Skills:** handoff; `superpowers:brainstorming` / `writing-plans` / `executing-plans`; `studio-brainstorm`

**Tables Phase 1 SHIPPED + signed off (07-01):** the full gesture matrix is live — title navigates (row-click narrowed), status/select/multi/context cells open the `PropertyPicker` (PickerMenu-based, Solid variation), checkbox-look status cycles its group on valued cells and pickers on empty ones (capsule-chip options), numbers inline-edit via `PropertyEditor` (keystroke-filtered; empty commit clears via `setProperty null`), links/files open through sanctioned IPC, right-click always menus (per-type Style radios + Clear on picker-based cells, title Rename/Change Icon/Delete). Styles persist per-view in `column_styles` (per-KEY fold in `mergeOverrides` — an entry-level spread wipes sibling keys). The reusable editing surfaces live table-agnostic in `Detail/Views/PropertyEditing/` for Gallery/List reuse (Nathan's DRY directive). → `Features/TableView.md`.

**The Apple overflow model — elastic title REVERTED (07-01):** Nathan's live testing overturned the prior session's elastic-`minmax` title: it made the title the shock absorber for every resize ("new columns only compress the tight-view; theres no room affordance") and per-type max caps made resizes hit an immovable wall. Now every column holds its resolved width, all maxes are uncapped (mins stay), and overflow h-scrolls the whole view past the pane — capped-with-filler when fitting, right inset flattened while overflowing (`--table-right-inset` + the `overflowing` class from ONE table-level RO). His reference: Apple's tables ("when a column doesnt extend... it stays capped; when you extend beyond... the table becomes scrollable"). → `Features/TableView.md` §Overflow & Scroll.

**Conditional inspector — REMOVED (07-02):** the fitting-compresses / overflowing-keeps-width conditional went through three implementations (scrollWidth latch → known-column-sum hypothetical → a two-signal split) and live CDP verification, and Nathan still called the live feel wrong — torn down entirely on his order, no dead code left. The inspector now plainly compresses the pane; a tighter table h-scrolls within the inset. The scrollWidth-floors-at-clientWidth lesson survives in Lessons Learned; decision → `History.md` 07-02.

**DRY OverflowScroll (07-01):** Nathan caught that the title truncation didn't reuse the sidebar's row mechanism ("WE DRY-ed that mechansim for a reason"). Now `design-system/components/OverflowScroll.tsx` is THE shared truncate-hover-scroll box — icon rides INSIDE the scroll box with the text, rAF `slideScrollBack` bounce-back (hoisted; the sidebar imports it), and a two-edge eclipse fade so clipped content NEVER hard-cuts (his Active/Closed chips screenshot). Wrapped around every cell content type: title, chips, dates, numbers, links.

**Review sweep (7 findings fixed, `34429aa` + `e4e1b54`):** build-breaking-agent post-green attack. Fixed: the per-cell ResizeObserver cliff (≈3000 ROs on a big table → one debounced epoch broadcast via `OverflowMeasureContext`; hover/scroll keep single cells honest), the overflow RO never re-binding after empty→populated, per-file write serialization in main (`serializeOnFile` — rapid picker toggles could land out of order, the registry race one level down), value-only ops (`setProperty`/`setTier`) skipping the full-nexus `load()` re-walk (the watcher settles canon), a mid-Bloom picker click gate, a PropertyEditor unmount flush (StrictMode-guarded), and `TableView.md` restated to the fixed-track model. The reviewer called the inspector guard "sound" — the live CDP check proved it was a one-way latch anyway: agents' verdicts are hypotheses too.

**PropertiesV2 SHIPPED (07-01):** definitions nexus-wide in `.nexus/properties.json`, sidecars hold assignment-id arrays, `readNexus` joins, `schema:*` re-backed so PropertiesPane never changed; registry mutations serialized (review-caught race); SQLite v16 pure mirror. Net +163 code lines. → `History.md` 07-01. Plan 2's Max-Properties gate + B-7 option colors: this doc + the Tables log are the record (spec pruned).

**Seed options aren't values (07-01):** Nathan's model — the default creation seeds (Not started/In progress/Done) are scaffolding, not defined options; a seed-only def pickers EMPTY (`isUntouchedSeed`, the picker's proportioned empty pane is interim UX). For testing (no creation UI yet) the REAL Nexus registry's status def was hand-edited to Open (upcoming) / Active (in_progress) / Closed (done) and 4 page values migrated to match. New `setTier` mutate op backs the tier pickers (bare `tier1/2/3` arrays via `setPageTier`, per-path serialized).

**Sidebar drag-lag fixed (`2f4cb83`):** the same per-pointermove O(rows) rect storm the table had — snapshot-at-activation now house standard; the inverted-justification root cause captured in `Features/PommoraDND.md` §Measurement discipline.

**Tables Phase 2 (band drag) SHIPPED (07-02, overnight):** group bands drag by their glyph on the insertion-line gesture — structural reorder persists to the view-level `group_order` (full-tree merge; collapsed siblings survive), property reorder writes `group.order` + manual mode (its first UI writer), a Set band's nest / parent-changing slot commits a real `moveSet` with the append-only order guard, Esc aborts every drag surface, and the **no-"None"-band ruling** (Nathan's pre-execution interjection) landed in the pipeline: value-less rows flatten header-less at the bottom, `empty_placement` demoted to decode parity. Thirteen commits `f1e7327..3893fb4`; suite 939 → **994**. Two post-green build-breaker rounds found 6 real issues, all fixed (`f199d65`, `3893fb4`) — round one: **region-owned hit-testing** (headers aren't adjacent in the real render — hovering a group's data rows used to hand the slot to the NEXT header, a silent misplaced reparent; now a band owns its whole region and its row-space reads as an explicit nest-into highlight), a **failed `moveSet` now commits nothing** (no phantom `group_order` on a name collision), and the drag ghost's label resolves once at activation. T7 proved everything live against the real Nexus (Index): mid-drag chrome, Esc restore, a reorder whose `group_order` write left `set_order` + the sidebar byte-identical and survived a reload, a nest + de-nest round-trip with real folder moves (the disclosed set_order-tail caveat observed live, then restored), and a property drop on a temporary view (cleaned up after). Band headers then adopted the sidebar's interaction model (Nathan's closing ask): glyph click = toggle, double-click = open (openable Sets only), right-click = the native set menu with the store-driven inline rename — via a hoisted shared `RenamableTitle` + `suppressNextClick`, zero new IPC (the sidebar's contextMenu/begin-rename flow drives it). → `History.md` 07-02 (ship + lock entries), `Features/TableView.md` §Groups.

**Perf audit + fix wave (07-02):** Nathan asked for an explicit whole-tree-reads / every-X-scans hunt. Benched findings → fixes: band hit-testing allocated per pointermove (index now rides the frozen snapshot, `e4759d0`); column drag re-rendered the whole unmemoized table per frame — 13.9ms JS floor @2k rows (the cursor-follow now rides a grid-level `--col-drag-x` CSS var; state keeps only slot flips, `05b654e`); the grouped pipeline + Cells double-parsed every value (one WeakMap cache keyed on frontmatter identity, `_title` bypasses, `ec38b70`); every watcher push re-rendered every consumer (store-level structural sharing — echoes are literal no-ops, unchanged containers keep identity, `d231f9d`); rows unmemoized (`React.memo` DataRow over identity-stable props — per-column style/align arrays, one ref-routed handler object, primitive overlay target, `bb71712` — which also fixed a latent hook-after-conditional-return crash). **Remaining, recorded:** main's watcher still re-walks the whole nexus per fs event (off the UI thread; the surgical-reconcile arc is the named fix), virtualization at thousands of rows, and external VALUE edits don't live-refresh open tables (values load per container open; the tree carries structure only).

**Pick-closes-the-picker (07-02):** the picker renders INSIDE the cell it edits, so an option click committed + dismissed and then BUBBLED to the cell's own onClick, which re-opened it — it had never actually closed on pick. A propagation boundary on the picker wrapper fixes it; regression test pins pick → commit → gone after the Bloom-out; the close animation verified numerically (opacity 1→0 over the 225ms `dropdown` token).

**Lessons Learned**

- **"Please confirm" means STOP and talk, then wait.** Nathan: "TALK dont just go into fixing... You got away with it because it worked — but dont do that again." State the understanding, end the turn, implement on his go-ahead. → memory `feedback-confirm-means-stop-and-talk`.

- **`scrollWidth` floors at `clientWidth`** — any "is content bigger than the box" comparison that subtracts a hypothetical from `clientWidth` while comparing against `scrollWidth` is a one-way latch. Compare KNOWN content size (state) against the box, not a floored measurement.

- **A pipe masks an exit code.** `vitest run | tail` exits with tail's 0 — one broken test rode into a commit that way. Capture to a file, check `$?` directly (`> /tmp/out; VE=$?`).

- **React 19 does not delegate `scroll`.** `onScroll` on an ancestor never fires for a descendant's scroll; use a native capture-phase listener — or own the node (a component binding its own `onScroll` is fine).

- **Diagnose the real complaint in code before asking.** → memory `feedback-diagnose-before-asking`.

- **An overlay rendered inside its own trigger re-fires the trigger.** The cell picker lives inside the cell whose click opens it — any click inside the overlay bubbles to the opener unless the overlay is a propagation boundary. Same rule as the chip-(×) E-3 note; apply to every future in-cell editor.

- **A feature can be CDP-verified correct three times and still be wrong.** The conditional inspector passed live verification on every implementation; Nathan's real-hand use killed it anyway. Screenshots prove mechanics, not feel — a visual-preference feature isn't done until HE uses it.

- **A memoized context freezes every closure behind it.** BandDnd's context memo froze `begin` from the first render, so the drop callback saw first-render props — property bands didn't exist yet (values load async) and drops silently no-op'd. The house fix is the ref pattern (`onDropRef.current`), same as the sidebar's `onCommitRef`. Any callback that crosses a memoized context + long-lived listener chain needs it.

- **Test fixtures inherit your mental model's geometry.** Every band test measured headers as ADJACENT 24px rows; the real render puts a group's data rows between headers, and hovering that space handed the slot to the next header (a silent misplaced reparent). The build-breaker caught it by executing the model over realistic gap geometry — fixtures must model the render's real shape, not the diagram's.

**Key Files & Insights**

- `Detail/Views/PropertyEditing/` — the table-agnostic editing home: `PropertyPicker` (+ `StatusCapsule`), `PropertyEditor`, `statusCycle` (fixed 3-group cycle + glyph map), `formatValue` (Swift-parity, en-US pinned, local-midnight date parse). Gallery/List mount these as-is later.
- `design-system/components/OverflowScroll.tsx` — THE overflow mechanism (hover-scroll + bounce-back; the eclipse fade is scroll-driven CSS in `OverflowScroll.css` — the engine activates it only on real overflow, so there's no JS measurement and nothing to go stale); the sidebar shares `slideScrollBack`.
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
- **Mutating gestures against the running app (real Nexus) need Nathan's explicit authorization** — granted for the 07-02 arcs with the standing condition that state is restored exactly (drop → verify on disk → reverse). Without it: drag-and-abort / open-and-Esc only.
- **PropertiesV2 net +163 code lines** (20,063 → 20,226 via `scratchpad/count-loc.py` — reuse that script for LOC deltas). Locked decisions → `History.md` 07-01.
- The REAL Nexus status def now holds Open/Active/Closed (test data, hand-written); `isUntouchedSeed` correctly reads it as "touched," so pickers show the three options.

### Next Session — Phase 3 remainder → View-Settings pane

**The chip hover (×) SHIPPED (07-02, Nathan-directed live):** every PILL chip (status-pill, select, multi, context/tier — Chip AND ContextChip) reveals an × on hovering its RIGHT THIRD (the ×'s own zone — left/middle hovers do nothing, so an overflowing label can be approached without summoning it), the label tail blurring INTO THE FILL beneath: the text renders three times, and the reveal flips OPACITIES ONLY — crisp copy out, pre-masked melt + `blur(2px)` fill-colored twins in (`--chip-fill`; ContextChip overrides it inline). That opacity-only shape is forced by a Chromium dropped-repaint family (bisected by agent, Nathan-verified live; laws + mandatory re-verify matrix → `Guidelines/Build-Gotchas.md` § Chip Melt). Trade-offs accepted: removable-chip labels are pointer-inert (no hover-scroll), and the right-third rest-click hits the revealing × rather than the cell. One reusable chip-level mechanism (`chipRemovable`/`chipRemove`/`chipFrost` tokens + `ChipRemoveButton`), opt-in via `onRemove`; Cell routes per-chip removal through the ref-stable `cellApi.remove` (tier → setTier, rest → setProperty). Capsule/checkbox looks carry NO × — menu Clear only (already shipped). **No-empties rule locked in `applyPropertyValue`**: null OR empty (`[]`/`''`) deletes the key — a page without a value carries no key (checkbox false / number 0 stay; tier `area: []` deliberately KEEPS writing — Nathan: context-wiping fights the nexus indexing; one-line prospective in Contexts.md). Live-proven on the real Nexus: × click → `properties: {}` on disk → picker-restored exactly.

Next up: **Phase 3 remainder** (decision log §E): the E-3 context table leftovers — the capsule's floating × (**~4px RIGHT of the chip** — it can't sit inside) if Nathan still wants it, slide verification post-OverflowScroll, the D-section "+" wiring. Then the View-Settings property pane (Pending Focuses, Figma-designed + Swift-proven — stop and ask on "Max Properties"). Open thread: **file chips deliberately got no ×** (removal = deleting an attachment; unasked) — confirm with Nathan.

### Pending Focuses

- **View-Settings property creation/management pane: design-complete, ready to implement.** Nathan: the entire property creation + management ViewPane is already designed in Figma and shipped in similar form in the Swift build — pull the Figma design + Swift precedent when building. Folds in PropertiesV2 Plan 2's assign surface (assign-existing `+` picker over the registry, Remove-vs-Delete, global-clash nudge, lossy changeType strip, **B-7 per-option status colors**, Inspector's assignment gate) — **MUST stop and ask Nathan about "Max Properties"** when building it.
- **Per-style minimum column widths + slide animation (idea, Nathan 07-01):** each look carries its own column min (checkbox min < capsule min < pill min); when an at-minimum column's style changes to a wider look, the width "slides" to the new minimum with an animation. Design-note only for now.
- **Empty-picker UX** — the proportioned empty pane is interim; Nathan will design the real no-options affordance (creation entry point?) later.
- **(Perf) Remaining debt after the 07-02 fix wave** (`e4759d0` `05b654e` `ec38b70` `d231f9d` `bb71712` — band snapshot index, var-driven column drag, parse-once value cache, tree structural sharing, memoized rows): (1) **the main process still re-walks the whole nexus per watcher event** (fs + YAML for every page; the renderer no longer cares — stabilize makes unchanged pushes identity-stable no-ops — but main's CPU/IO cost scales with nexus size; the durable fix is the surgical-reconcile arc, Swift precedent: 11 TDD commits, coarse-rebuild fallback for structural events). (2) **Virtualization** — every row still MOUNTS (memoized rows re-render only on their own changes now, but initial mount + DOM size remain O(rows); bites at thousands). (3) External VALUE edits don't live-refresh open tables (loadValues runs per container open only; the tree carries structure, not values) — pre-existing, surfaced by the audit trace.
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
