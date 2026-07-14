## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — detail lives in `Features/*` + `History.md`.

- **Block Surfaces — SurfacePM (shipped + merged to main, `8fca70cd`).** The host-agnostic block/tile system: split-tree layout, window-style edge resize, PommoraDND feel, markdown/page/view tiles behind the BlockHost seam (locked read-merge-writes), CM6-portal page embeds (every prose tile a read-only MarkdownPM view), block `[[links]]` as first-class edges, geometry-only homepage lock, homepage/context identity settings, and per-block Scale (freeze-inset, view-agnostic). → [[SurfacePM]] + `History.md`.

- **Tables — cell + group system + grouping/sorting.** The cell-gesture matrix, per-view looks/formats in `column_styles`, band drag, the reusable editors in `Detail/Views/PropertyEditing/`, and grouping + sorting end-to-end (pane · pipeline · Location order writing the real filesystem · drag surfaces). → [[TableView]] + [[Views]].

- **PropertiesV2 — nexus-wide registry.** Defs in `.nexus/properties.json`; a Collection's sidecar holds only its assignment-id array; `readNexus` joins them so every surface gets a resolved schema. SQLite mirrors it as a regeneratable accelerator.

- **Multi-View scaffolding + per-type editors.** ViewDropdown · ViewPane · two-door ViewSettings, the G-1 invariant (views never empty where visible), and Date/Checkbox/Number/Status/Link editor panes. → [[Views]] + [[Properties]].

- **Icon Picker + Sidebar Ribbon.** Full-Lucide picker in the shared PickerMenu; ribbon + mode-switched sidebar (surface-launcher model, lazy `agenda:list`, right-click create). → [[Icons]] + [[Sidebar]].

### Session Summary — Block-Surface Arc → Merged, then Post-Merge Table Polish

**Session ID:** abc3bafe-70bc-41e4-adfd-aa052cfee424
**Dates:** 07-10-2026 → 07-13-2026
**Model:** Fable 5 → Opus 4.8 (1M)
**Compactions:** 7
**Connectors:** none
**Commands:** /clear · /handoff · /compact · /loop
**Agents:** build-breaking-agent (17x) · general-purpose (5x) · code-simplifier (3x) · Explore (1x) · comment-killer (1x)
**Skills:** studio-brainstorm · superpowers:writing-plans · superpowers:executing-plans · superpowers:systematic-debugging · handoff

One long session: the Contexts rethink became a certified spec, the spec became SurfacePM, SurfacePM became a live block system, and the whole arc merged to main — then a post-merge table-polish tail.

**The block-surface arc (now merged, → Recent Work + `History.md`):** a certified spec (`Planning/7-10 - Block Surfaces — Decision Log.md`, three adversarial rounds) drove SurfacePM built from scratch, its plumbing (Tasks 0–3 + the CM6-portal redirect), the H-5 view-embed chrome + edge-release scroll, the link graph, the geometry-only homepage lock, the homepage/context identity settings, and per-block Scale — closed with a doc pass and a `--no-ff` merge (main green, 1492 tests). The detail is in [[SurfacePM]] + `History.md`; don't re-narrate it.

**Hide Borders + borderless reveals (`cf03d9fc`):** a per-view table toggle (Layout) that strips the body grid lines — row dividers + vertical column hairlines — while the heading row keeps its seam + segment bars. With borders off, structure surfaces on demand: the vertical dividers fade in while a column is resized or reordered (grid-level `col-resizing-active` / the existing `col-dragging-active`), and the cell being edited wears a rounded accent ring. Landed through a live UIX loop — Nathan corrected the heading (kept), the divider trigger (hover → resize/reorder only), and the accent (a 4px ring, not an inside fill). All reveals ride `--ease-standard`. → [[TableView]].

**Date-cell clearing fixed — two React port gaps (`9d6e0346` + `cf03d9fc`):** systematic-debugging found every code path intact and unchanged since the rename, so the bugs sat in the interaction layer + one type gate. (1) Clicking a selected calendar date did nothing: arming the drag-reposition pointer-captured the grid, retargeting the day button's click, so the clear was swallowed — now the no-move clear runs on `pointerup`. (2) Date cells had no menu Clear: `datetime` was grouped with the inline-clearable types instead of the picker-based ones — moved in with `status`. And Clear/Remove now shows only on a filled cell, via a shared `isBlankValue` predicate (DRY with `applyPropertyValue`). **Both need Nathan's live eyes** — jsdom stubs `setPointerCapture`, so the calendar path can't be unit-verified.

**Picker outline scope fix (`6e60d514`):** the block handle menu's `accentOutline` ringed the whole menu; scoped it to just the nested Scale dropdown (the input field).

**Lessons Learned**

- **A transformed ancestor breaks `position:fixed`** — SurfacePM tiles ride `translate()`, so ANY fixed-position UI inside a tile subtree misplaces + clips. Popups must portal to body; bites every future in-tile surface.

- **jsdom can't reproduce real-DOM interaction bugs** — `setPointerCapture` is a no-op stub and `elementFromPoint` is faked, so the calendar click-to-clear stayed green in the suite while broken in the app. Pointer-capture / hit-testing / native-menu paths are verified by Nathan's hands, never by a passing test.

- **The pipefail trap keeps biting** — `typecheck 2>&1 | tail` returns tail's `0` and hides a red build. Capture the real `$?` into a file; never trust a piped exit code.

- **A clean subsystem resists the sweep — that's the signal, not a miss.** Cleanup passes that come back near-empty mean the code was already disciplined; don't manufacture churn to look thorough.

**Key Files & Insights**

- `SurfacePM/` — the engine (README = module map + invariants); `Blocks/` — the tile family; `Embeds/PageEmbed.tsx` — the shared embed framework (`EMBED_SCALE` is THE knob).
- `shared/blocks.ts` — cross-process block contract; `main/blocks.ts` — every doc mutation through one locked read-merge-write.
- `shared/propertyValue.ts` — `isBlankValue` is the one set/clear + "is this cell filled" predicate; `Detail/Views/Table/table-tokens.css` — every table number (§G: no raw px in `Table.css`).
- Knobs Nathan tunes live: `--tile-border` / `--handle-w` / `--grip-size` (surfacepm.css) · `EMBED_SCALE` · `--mdpm-scale` at :root · `--cell-active-radius` (borderless ring).

**User Feedback**

- Nathan live-drives and drip-feeds mid-turn corrections — fold each immediately, batch-commit, bundle his tunes; his effect-words are literal.
- Confirm the layer before fixing (UIX vs data), and ask before any design/interaction call — don't guess how something looks or behaves.

---

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a full dev-process restart**. Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`; relaunch with `-- --remote-debugging-port=9222` to keep CDP.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. Plain `.css` DOES HMR reliably.

- **The dev app runs against Nathan's REAL Nexus** (`/Users/nathantaichman/The Nexus`). UI value writes are his data; CDP must open + Esc only, never pick/commit unless he authorizes it. Native OS menus don't render in the DOM; reach those ops through `window.nexus.*` via `Runtime.evaluate`.

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A`. Unattributed `M`/`D` files are almost always Nathan's, left uncommitted on purpose. **main is ahead of origin, unpushed** — Nathan pushes in batches; merge ≠ push.

- **Detail insets split by surface kind:** block surfaces run tight `--surface-inset` (8px body) + `--surface-banner-inset` (12px banner) via an `is-surface` class (`isSurfaceKind`, `Detail/Scope.ts`); page/table views keep `--content-inset` + `--fold-gutter`.

### Next Session

**SurfacePM is MERGED — a finished, stable substrate.** The strategic point (Nathan's): lock the surface *before* future plans decide what mounts it, then pivot to the foundational layer.

**The pivot — Navigation · Tabs · Agenda (Nathan's stated next).** Navigation is the Window + Dropdown + Inspector surface (→ [[Navigation]] + [[Inspector]]); it reuses the shared `state.json` recents record (the same plumbing the block Insert / Link-Page flow wants). Each starts with brainstorm → plan → build, building *against* the now-settled surface.

**Verify the two date-clear fixes live** — click a selected calendar date to clear it, and right-click a filled vs empty date cell (Clear present vs absent). Neither is unit-verifiable.

**SurfacePM post-merge polish (no longer blocking):** page banners on embeds (+ per-tile lock home) · the Insert menu (G-9) + Link-Page search pane + shared recents (G-16, pairs with Navigation) · the shared debounced-save hook (`MarkdownBlock` ↔ `PageEmbed` ~35 LOC, a real save-boundary refactor, best with the future `![[]]` consumer in hand) · robustness adds (per-tile error boundary, lazy-mount embeds, layout undo) · interaction foolproofing under drag-heavy gestures (incl. the `.spm-edge` overlap near tile borders — at-rest selection is fixed, the edge-zone tail unconfirmed).

**Other consumers (post-foundational):** Page/View Previews · Filter-pane redesign · Page-Embedding `![[]]` · Gallery/Card view · the standing relation/context pickers. A new view type opts into Scale with one line — `zoom: calc(var(--zoom) * var(--block-zoom,1))` in its grid CSS.

**Parked by design:** the contexts-resolution brainstorm (sidebar, contexts-as-hosts, Homepage's final shape — the graph-view host with widgets stays the current direction; do NOT strip it).

### Pending Focuses

- **User Sections CRUD (the "Add Heading" feature).** Collections render user sections but there's no way to make one (`mutate.ts` has zero section ops). Own brainstorm→plan→build. → `Sidebar.md`.

- **"None"/flat grouping + Flatten + Hide Location** — the flattened-mode bundle, deferred (→ [[Views]]; `flat` GroupConfig kind stays reserved).

- **(Perf) Standing debt:** no row virtualization (every row MOUNTS — bites at thousands); external VALUE edits don't live-refresh an open table. Container-surgical reconcile is the designed escalation at scale.

- **Number editor eyeball items (tune, not bugs):** decimals "Hidden", fraction wording, bar clamp edges, strokeless bar, field widths. Knobs in `numberEditor.css.ts` / `textPicker.css.ts` / `formatValue.ts`.

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build. Free-placement drawing inside Pages; distinct from Block Surfaces.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the code is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **Automatic scrolling** — must-have for views + MarkdownPM.

- **iCloud-sync readiness (future):** `serializeOnFile` can't coordinate with the iCloud daemon (last-writer-wins); `.nexus/index.db` needs sync-exclusion; the walk must skip `.icloud` placeholders.

- **Mobile iOS companion (parked):** spec at `.claude/Mobile/MobileSpec.md`; step 1 a `window.nexus` bridge shim + native iCloud Swift plugin. No build commitment.

### Fix Log

- **`.nexus/activeViews.json` + per-machine siblings aren't gitignored (live).** Neither it nor `folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles` are ignored — using the switcher on a fresh container creates a would-sync file. Add to the Nexus `.gitignore`.

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED)** — a visual inset, not a stored char.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either corrupts the doc (`MarkdownPM/editor/blockModel.ts`, test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → [[MarkdownPM]].

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so; silently fix what contradicts it — a fresh agent shouldn't be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry's done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count; a merged arc compresses into Recent Work. Carry still-open Pending + Fix Log forward.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this doc** — a concurrent session adds its own labeled block; Cornerstone + footer shared; never edit another's block.
