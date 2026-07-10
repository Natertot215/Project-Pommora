## SurfacePM — RGL Teardown

> The methodical dissection of react-grid-layout v2.2.3 (cloned at tag `2.2.3`, all non-test source read) grounding the SurfacePM reconstruction: what we inherit, rebuild, forget, and modify. Companion to `7-10 - Block Surfaces — Decision Log.md` (B-7). Open questions at the bottom block the SurfacePM plan until answered.

### Architecture Map

RGL v2 is **8,771 non-test lines in two decks**:

- **`src/core/` (~2,600 lines)** — pure TypeScript math, zero React imports, published as its own entry. The data model is `LayoutItem { i, x, y, w, h, minW/maxW/minH/maxH, static, isDraggable, isResizable, resizeHandles, constraints, moved }` over an immutable-by-convention `Layout` array.
- **`src/react/` + `extras/` + `legacy/` (~6,100 lines)** — components and hooks built on **react-draggable + react-resizable** (the React-19-fragile chain), plus responsive/legacy/perf extras.

**The interaction pipeline** (one drag move): pointer event → DraggableCore (pixel delta) → `calcXYRaw` (pixel→grid units) → constraint chain (`gridBounds` → `minMaxSize` → per-item) → `moveElement` (recursive collision cascade — collided items push down/along the compaction axis) → `compactor.compact` (gravity pass) → setState → every tile renders via `calcGridItemPosition` → `transform: translate` styles. The dragged tile itself renders at raw pixel position while a **placeholder ghost** renders at its computed grid slot; on drop the tile snaps to the ghost.

### Inherit (keep, near-verbatim — the battle-tested math)

- `core/collision.ts` (65) — `collides`/`getFirstCollision`/`getAllCollisions`. Trivial and perfect.
- `core/sort.ts` (82) — reading-order sorts.
- `core/layout.ts` (509) — `bottom`, `getLayoutItem`, `cloneLayout(Item)`, `modifyLayout`/`withLayoutItem`, `correctBounds`, and the heart: **`moveElement` + `moveElementAwayFromCollision`** (the recursive push cascade with the try-up-first user-action heuristic). Drop `validateLayout` (zod at our IPC boundary already owns validation).
- `core/compactors.ts` — `verticalCompactor` + its helpers (`resolveCompactionCollision`, `compactItemVertical`, `compactItemHorizontal` as reference for the left-pack pass). Drop the overlap variants and the `getCompactor` string factory.
- `core/calculate.ts` (419) — the px↔grid conversions, **including the margin-rounding consistency correction** (adjusts width/height so rounded gaps stay exactly `margin` — subtle, battle-tested, keep verbatim) and `calcGridCellDimensions` (grid-visualization math).
- `core/position.ts` (332) — **`resizeItemInDirection` + the eight per-direction handlers** (the all-sides resize brain: north/west resizes move origin while growing size, corners compose) and `setTransform`. The **scaled-strategy pointer math** (`clientRect/scale`) is kept as a concept — it's how drag stays accurate inside zoomed content (G-10).
- `core/constraints.ts` — `gridBounds` + `minMaxSize` only.
- MIT attribution rides with all of it.

### Rebuild (replace with our own — the interaction + render layer)

- **`GridItem.tsx` (883) → the SurfacePM tile.** Today it's a thin adapter: DraggableCore + Resizable wrap the child, convert pixels to grid units, hold `dragPositionRef`/`resizePositionRef` for free mid-gesture motion. Ours: PommoraDND-pattern pointer capture (capture / activation threshold / rAF / teardown), the **border drag handle** (B-6) instead of whole-tile drag, **border-edge resize hit zones on all sides** instead of react-resizable's corner spans, native **Esc-abort** (restore the drag-start snapshot — E-7). Keeps calling the inherited math (`calcGridItemPosition`, `calcXYRaw`, `resizeItemInDirection`, constraints). The flushSync batching-jitter class (Grafana's patch) dies with react-draggable.
- **`GridLayout.tsx` (1,130) → the SurfacePM grid.** Renders from the **block document** — the children+`data-grid` reconciliation (`synchronizeLayoutWithChildren`, `childrenEqual`) dies entirely; tiles are data, not reconciled children. Keep: `autoSize` container height from `bottom()`, the placeholder ghost, the drag/resize orchestration shape.
- **`useGridLayout.ts` (473) → our own state owner** — RGL ships the state logic TWICE (the hook and the component each implement it, unshared); we write it once.
- **`useContainerWidth` (151) → ~30-line ResizeObserver hook** (native RO in Electron; their version carries polyfill + SSR + measureBeforeMount ceremony).
- **CSS** — their `styles.css` (placeholder look, handle spans) re-tokened: `--separator-border` tiles, accent resize highlight (G-1), our ghost styling.

### Forget (bloat deleted outright)

- **All responsive machinery** — `ResponsiveGridLayout` (472) + `useResponsiveLayout` (298) + `core/responsive.ts` (203) + `WidthProvider` (136): breakpoints/SSR for a single-window desktop app.
- **`legacy/`** (~600) + **`compact-compat.ts`** (232) — v1 API + v1-algorithm parity layers.
- **Overlap support** — `allowOverlap` paths + the three overlap compactors + `preventCollision` snap-back mode: we always compact; locks handle "don't move."
- **`wrapCompactor`** (156) — the flow-like-words mode assumes uniform 1×1 tiles and ignores heights when flowing; wrong model for variable-height tiles.
- **Fast compactors** (469) — O(n log n) for 200+ tiles; a Space never holds that. Prospect if ever real.
- **The external-drop path** (`droppingItem`/`onDropDragOver`/`__dropping-elem__`) — our insert flow is the right-click menu (G-9), not HTML5 drag-in. Prospect if a palette ever wants drag-to-place.
- **Dependencies, all six:** react-draggable + react-resizable (replaced by our sensors), resize-observer-polyfill (native in Chromium), prop-types (TS), clsx (trivial), fast-equals (one small layout-equality helper).
- **Misc:** percentage positioning, `absoluteStrategy` top/left mode (transform only), vendor prefixes (`MozTransform`/`msTransform`… — Chromium-only app), `data-grid` prop parsing.

### Modify (divergences — where SurfacePM is better, not just smaller)

- **Fix the drag-accumulation bug at the source.** Both implementations run `moveElement` against the **current mid-drag layout** every move event — the drag-start snapshot (`oldLayout`/`oldLayoutRef`) is stored but never used for moves, only for end-of-drag change detection. That accumulation is the documented oscillating-placeholder class (upstream #750). SurfacePM recomputes each move **from the snapshot**: `preview = compact(moveElement(snapshot, item, x, y))` — stateless per move, oscillation impossible by construction.
- **The compactor is custom** — Nathan's no-dangling-spaces both-axis compaction (→ Q1 below; the one genuinely new algorithm).
- **Resize perf** — upstream recompacts the whole layout on every resize move and re-renders every tile (their open regression discussion #2228); ours: rAF-coalesced preview + tiles memoized on their own LayoutItem identity.
- **Resize-into-neighbor semantics** need defining under both-axis compaction (→ Q2).
- **No a11y exists upstream** (zero aria/keyboard in the entire react layer) — nothing lost; keyboard interactions stay out per the no-shortcuts-without-sign-off rule, Prospect later.
- **Packaging:** `SurfacePM/` as its own module family beside MarkdownPM — `core/` (inherited math + our compactor) and the components — behind the engine seam (B-7); the `Blocks/` component family consumes it (G-2).

**Size honesty:** post-prune inherit ≈ 1,200–1,400 lines of math; rebuild ≈ 600–900 lines of sensors/components/state. SurfacePM lands around **2k owned lines** replacing an 8.8k-line dependency plus its two drag libraries.

### The Geometry Verdict (resolved with Nathan, by example images)

- **Q1 resolved — the surface is a tessellated mosaic, not a compacted grid.** Nathan's target (shown by example): tiles span freely (a tile can stretch under two neighbors, edges don't globally align), rows/regions can run different lengths — but **interior empty space cannot exist**; every region is covered by exactly one tile. Not column-stacks, not both-axis compaction: a **tessellation invariant**.

- **The implementation model is a split tree** (the tiling-window-manager lineage — i3/tmux/react-mosaic's family): the layout is nested splits (`row`/`column` nodes with ratio arrays) with tiles as leaves. The invariant holds *by construction*: deletion → the sibling absorbs the space (holes impossible); insertion/drop-on-edge → the target region splits; **resize = changing one node's ratio** — the shared divider moves and everything bordering it adjusts together (Nathan's confirmed splitter semantics, min-size clamped), which also dissolves the T-junction ambiguity a free x/y/w/h grid would suffer.

- **Q2 resolved:** shared-edge redistribution with a minimum-size clamp is THE resize model. Q3: drag-time boundary/region visualization kept, color DRY'd to an existing token. Q4: no per-tile pinning — locking stays the block/host lock mechanism only.

- **Deliberately build-tuned (Nathan):** the exact vertical semantics — stack-internal edge behavior, ragged region ends, how the flowing page bottom behaves — are played with live once the build stands, not spec'd in prose.

### Inheritance Verdict, Revised

The tessellation model **retires RGL's brain**: collision cascades, gravity compaction, `moveElement`, and x/y/w/h coordinate math all exist to manage tiles floating on a grid *with* empty space — a problem SurfacePM's geometry doesn't have. What survives from the teardown:

- **Patterns, not code:** the placeholder-ghost-during-drag pattern, drag/resize state orchestration (snapshot-on-start → preview → commit/abort), the scale-aware pointer math concept (`clientRect / scale` — for zoomed content, G-10), and the recompute-from-snapshot discipline (their accumulation bug stays instructive).
- **Possibly small verbatim pieces:** the eight-direction resize-edge composition idea (`resizeItemInDirection`'s shape, simplified — dividers are single-axis in a tree), the ResizeObserver container-width hook shape.
- **The clone stays as reference** (`scratchpad/rgl-src`, MIT) — but SurfacePM is now a genuine in-house engine: a split-tree layout model + PommoraDND-pattern sensors + flex/percent rendering. Simpler than the grid it replaces: no collision solver, no compactor, insertion is a tree splice, resize is one ratio write.
- **The block document's geometry** (Decision Log D-3) becomes the layout tree + per-leaf tile payloads — not per-tile `x,y,w,h`. → amended in the decision log.
