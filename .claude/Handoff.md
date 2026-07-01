## Handoff — Pommora React

One long session that specced Table Views Part 1, then drove a deep UIX-polish + performance arc across the table view and sidebar — and closed by auditing the table for lag and teeing up a redo brainstorm. Parked green on `main`, ready for that brainstorm.

**Session ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Dates:** 06-27-2026 → 07-01-2026

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

**Model:** Opus 4.8
**Compactions:** ~10 (best-effort; multi-window session)
**Connectors:** Figma MCP (early — Switch component); Electron CDP for live screenshots + hover/drag drive (not MCP)
**Agents:** general-purpose (perf audit ×1, adversarial reviews ×5+), code-simplifier (×2)
**Skills:** handoff; earlier `superpowers:brainstorming` / `writing-plans` (Part 1)

**Table view — full-bleed heading + elastic-title reflow:** The heading band now bleeds its fill + seam to both glass edges (sidebar left, inspector/window right) while its tracks stay locked to the body grid. The **title column became an elastic `minmax(floor, width)`** so the table compresses like a Page's body when the inspector opens / the sidebar toggles — the title yields (down to a 120px floor), property columns hold and stay visible, instead of clipping the right columns under the inspector. This was the fix to Nathan's "it doesn't compress" — the real cause was that every column was a *fixed* width with a trailing filler, so nothing reflowed. → `Features/TableView.md`.

**Table view — the elastic title couples three rules:** the `minmax` title, the grid's reflow-floored `min-width`, and the heading's **both-sides padding**. That last one was a bug Nathan caught: the heading bleeds a content-gutter wider than a data row, so an un-padded header resolved the elastic title wider and drifted every column right. Adding the compensating right padding re-lands the header tracks on the exact data-row width (fill still bleeds — border box vs content box). Change one, re-check the others.

**Table view — sticky disclosure headers + nesting tuning:** Group headers + their chevrons are `position: sticky; left: 0`, so the gutter holds them legible during horizontal scroll while columns scroll. Members nest one `--row-indent` step inside via `groupIndent` (no cell-pad base); ungrouped/loose rows use a new `--loose-inset` (tucked a touch left of the column inset). Known gap: the hover-only **row grips still scroll** with their row — freezing them cleanly means freezing the whole title column (a frozen first column), which is Nathan's call, deferred.

**Sidebar — hover-scroll eclipse, gated on actual scroll:** The left-edge fade fired on bare hover, dimming the row icon "as if you were going to scroll." Now the fade is gated behind a `title-scrolled` class that a **native capture-phase scroll listener** toggles on `scrollLeft > 0`. The first attempt used a React `onScroll` prop on the nav — dead, because **React 19 does not delegate `scroll`** (it binds onScroll to the node; scroll doesn't bubble), so an ancestor prop never sees a descendant `.titleText`'s scroll. The review caught it as a blocker. → `Features/Sidebar.md`.

**Performance audit — the table's real debt is architectural:** A thorough audit (agent + self-verified) found the lag sources are structural: **no virtualization** (every row of a collection is in the DOM), **no `React.memo`** on `DataRow`/`Cell`/`GroupHeader` (any re-render rebuilds the whole grid), and a **`source`-identity churn** — `findCollection`/`findSet` (`DetailPane.tsx`) return a new `source` object on every tree swap (watcher push or own `mutate`), invalidating the pipeline/schema/ctx memos → a full repaint on any external change. Plus a per-container-open **fs re-walk** (`loadValues`, no cache). Fixed the two contained wins this pass; the rest is the brainstorm's perf agenda.

**Perf — the contained fixes shipped (reviewed SHIP):** row drag was calling `getBoundingClientRect` over EVERY row on EVERY pointermove (a reflow storm) — now it snapshots all row geometry once at drag activation (rows never displace mid-drag) and re-measures only on scroll. Also memoized the flat `dataRows` + id-maps on `[groups]`. Both verified behavior-identical (the drop mutates real files, so parity mattered).

**The "on every X" hard rule (Nathan's directive):** He flagged the recurring lag anti-pattern — expensive work on every keystroke/input/render/pointer-move, or reloading the *entire* structure when an incremental update suffices. Codified as a hard rule in `.claude/CLAUDE.md`. The row-drag fix is a textbook instance.

**Lessons Learned**

- **React 19 does not delegate `scroll`.** `onScroll` on an ancestor never fires for a descendant's scroll (scroll doesn't bubble; React binds the handler straight to the node). Use a native capture-phase `addEventListener('scroll', …, {capture:true})` — capture *does* traverse down to the scroller. Cost us the sidebar-eclipse blocker.

- **Diagnose the real complaint in code before asking.** I fired an `AskUserQuestion` on the inspector-compress issue built on a half-verified premise (I'd measured the table-view *box* compressing and missed that the *columns* don't reflow). Nathan rejected the tool call — "it doesnt." Reproduce what the user actually sees against the code first, then act. → memory `feedback-diagnose-before-asking`.

- **The perf anti-pattern ("on every X") is THE lag source** — a per-keystroke reparse, a per-move rect read over every row, a per-open fs re-walk, a whole-grid re-render on one selection. Now a hard rule.

**Key Files & Insights**

- `Detail/Views/Table/TableView.tsx` — the render path. The pipeline (`flattenContainer` + `resolveView`) IS memoized; the rows/cells are NOT (no `React.memo`), and there's no virtualization. The elastic-title `minmax` + `reflowWidth` `minWidth` + heading both-side padding are one coupled mechanism.
- `Detail/Views/Table/tableDnd.tsx` — row-drag now snapshots geometry at activation (`measure`/`snapshot`), re-measures on scroll; the slot math is unchanged.
- `Detail/Views/Table/table-tokens.css` — the §G single source for every table dimension (`--cell-padding-x/y` = row height, `--loose-inset`, `--row-indent`, `--gutter`→fold-gutter). `styles.css` holds `--content-gutter` (the un-shadowed content-to-glass alias the full-bleed heading reads).
- `Features/TableView.md` (new) — the table implementation doc, sibling to `MarkdownPM.md`.

**Landmines**

- **The dev app runs against Nathan's REAL Nexus** (`The Nexus`, not `~/test`). A row-drag **drop** calls `mutate`/`viewOrders` and reorders his actual files — never run a live drop test; drag + abort (Escape / pointercancel) only, or drive the Test Nexus instead.
- **Parallel sessions** — stage explicit paths (`git add <paths>`), never `-A`. `.claude/Handoff - B.md` sat modified in the tree this session, untouched by me.

**Session Pointers**

- The review discipline earned its keep twice: the dead `onScroll` (React non-delegation) and a col-drag `zoom` calc that breaks when the title is grabbed while minmax-shrunk. Don't ship interactive wiring on the assumption it fires — verify.

**User Feedback**

- "never write 'on every X'" / "reload entire Y" — the lag anti-pattern; now a hard rule.
- Rejected an `AskUserQuestion` built on a half-diagnosed premise — diagnose in code first, then build-and-show.
- Row grips on horizontal scroll: freezing them = a frozen title column, his call (deferred).

**Uncertain**

- The exact scope of the **redo brainstorm** — whether "what needs to be redone" is the table's **perf architecture** (virtualization / memoization / source-identity / fs-cache), the **three feature subsystems** (remaining View-Settings panes, in-cell editing, ViewPane integration), or both. The Next Session note frames both axes.

---

### Working Notes

- UI iteration runs in **dev mode (HMR)** — CSS hot-swaps, React components Fast-Refresh, but **CM6 widget/extension code needs a full ⌘R / `Page.reload`**, and `src/main` (IPC, native menus, preload) needs a dev-server restart. Don't ⌘Q it.
- The agent **can** screenshot + drive the React UI headlessly (Electron + CDP `--remoteDebuggingPort` → `Page.captureScreenshot` / `Input.dispatchMouseEvent`); scratchpad has `cdp-shot.mjs` (screenshot / eval / `--clip` / `--rect`) + `cdp-hover.mjs` (force `:hover` + scroll + fade diagnostics). **Reading** a screenshot surfaces it to Nathan on mobile; sending doesn't. Nathan is the primary visual verifier.
- **Never run a mutating gesture (drop / rename / edit) against the running app** — it's the real Nexus. Drag-and-abort for hit-test checks.
- **PropertiesV2 code-line baseline (pre-implementation): 20,220 code lines / 264 files at `d0e1fb7`** — `React/src` `.ts/.tsx/.css`, excluding tests, comments, blanks. Method = `scratchpad/count-loc.py` (block-comment-aware, cloc-style code metric). Re-run the *same* script at closeout for the net-diff Nathan wants; don't swap the method or the number stops meaning anything.

### Next Session — The Redo Brainstorm (`studio-brainstorm` → `writing-plans`)

Nathan called for a full brainstorm on "what needs to be redone." Two axes, both grounded:

- **Axis 1 — Table-view performance architecture (the audit is the input).** The table is feature-complete but carries structural perf debt. The redo candidates, ranked by the audit's leverage: (1) **stabilize `source` identity** so an unchanged container keeps object identity across tree swaps (memoize `findCollection`/`findSet`, or key TableView's memos on `source.id` + a content stamp) — the single multiplier behind full repaints on every watcher push / own mutate; (2) **`React.memo` the row/cell path** + stabilize its props (the inline `onSelect`/`colTransform`/`style` defeat memo today); (3) **virtualize** the flat row list (`dataRows` is already the flat array a virtualizer wants; the `Reveal` collapse animation is the wrinkle); (4) **cache `loadValues`** per container in main (invalidated by the watcher) — bridges to the eventual SQLite index read path. This is where the "never on every X" rule bites hardest.

- **Axis 2 — Three feature subsystems (`Planning/7-1 - View Settings + In-Cell Editing + ViewPane — Brainstorm Prep.md`).** (a) The **remaining View-Settings panes** — Grouping, Sort, Filter, Layout, Visibility, View management (the shell + Properties pane already ship; the pipeline already honors the configs, so the gap is authoring). (b) **In-cell editing** — verdict already recorded: extend `Cell` with an edit mode or a sibling `CellEditor` mirroring its one type-aware `switch`, NOT a file-per-property-type; per-type edit *affordances* as small composable pieces. Open: activation gesture, commit/cancel, keyboard nav, coexistence with row-drag-from-title. (c) **ViewPane full integration** — wire every pane to live schema/view state; needs Nathan's framing of "full integration" scope.

### Pending Focuses

- **(Perf) Table-view architecture redo** — see Axis 1. The `source`-identity fix is the highest-leverage single change.
- **(Feature) View Settings remaining panes · in-cell editing · ViewPane integration** — see Axis 2 + `Planning/7-1`.
- **Row grips on horizontal scroll** — freeze them with the title column (frozen first column) if Nathan wants the whole gutter to stay; deferred pending his call.
- **DRY the sidebar row-fade + spring-back onto chips (Tables/UIX).** Chips already share a DRY'd ellipsis-hover-scroll for overflowing labels (`chipLabel` on `truncateHoverScroll`). Extend the sidebar rows' left-edge **scroll-fade eclipse** (`--scroll-fade` gated on `.title-scrolled`) + the **`slideTitleBack` spring-back-on-non-hover** so an overflowing chip label fades + bounces back too — one shared mechanism across sidebar rows, chips, and (eventually) table cells, not a re-implementation.
- **In-cell editing must arm row-reorder from the title cell too**, not only the gutter grip (keep the grip) — memory `project-row-drag-from-title-area`.
- **Block Drag V2 — nesting** (separate spec): interior drop-slots inside callouts, the box-nesting guard table, cross-container re-prefix. V1 shipped; nesting deferred.
- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build.
- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon (internally consistent; the hook doesn't convert). Settle once, in a tree with no parallel edits.

### Fix Log

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either half corrupts the document (`MarkdownPM/editor/blockModel.ts` — test-pinned, unguarded). A real behavioral fix, deliberately excluded from cosmetic passes.
- **Bullet single-word wrap drops the word below the marker** — a `-`/`•`/`+`/`→` item whose content is one long unbroken word; only the `line-height` cap shipped. → `Features/MarkdownPM.md` § Known Issues.
- **Table links non-clickable** — no input handling for a rendered link inside a cell; proposed single-click navigate + right-click edit.

### Handoff Rules

- **Resolve = delete + route, never tag.** When an entry here is genuinely done, push its outcome to the canonical doc (`History.md` / `Features/*` / `Framework.md`) and delete the line — no `(Resolved)` tombstones.
- **One block per session, updated in place.** Compactions bump the `Compactions` count, they don't add sections. Carry still-open Pending Focuses forward to a fresh sequential session.
- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.
- **Parallel sessions share this one doc** — a concurrent React session adds its own labeled block (`### Session Summary - B`, …); the Cornerstone + footer are shared; never edit another session's block. (The Swift build keeps its own separate root handoff.)
