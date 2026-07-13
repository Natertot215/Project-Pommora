## SurfacePM

The block-surface layout engine: a mosaic of draggable, resizable tiles rendered from a pure
layout tree. It is the host-agnostic half of Block Surfaces — it knows nothing about what a
tile contains (markdown, page embed, view embed) or where the tree persists; hosts supply
both through the `SurfaceView` props seam.

#### Provenance

Built after a full teardown of **react-grid-layout v2.2.3** (`.claude/Planning/7-10 - SurfacePM
— RGL Teardown.md`). RGL was studied for its patterns — collision semantics, resize-handle
geometry, controlled-layout data flow — and then retired: **no RGL code was copied**. Its
grid-cell model (units + compaction + tetris holes) was rejected in favor of a split tree,
and its synthetic drag core was replaced by PommoraDND's capture discipline.

#### The Model (`core/model.ts`)

A page is a vertical stack of **bands**. Inside a band, a **row** divides width by zero-sum
ratios, a **column** stacks children, and every **tile** owns its height in pixels. The two
axes deliberately obey different physics:

- **Width is relative** — a row's ratios always sum to 1, so resizing one tile is a splitter
  negotiation with its neighbor and the row always fills the surface.
- **Height is absolute** — stretching a tile never deforms a neighbor; columns flow
  independently and a shorter column simply ends. Ragged row ends are legal; trapped holes
  are impossible by construction, so no compaction pass exists.

#### Module Map

| File | Role |
| --- | --- |
| `core/model.ts` | Tree types, height derivation, lookup, validation |
| `core/ops.ts` | Pure tree operations — split, move, remove, band ops, the three resize ops |
| `core/rects.ts` | Tree → per-tile pixel rects, divider hit zones, band seam centerlines |
| `core/edges.ts` | A tile edge → the shared boundary it actually moves |
| `core/hitTest.ts` | Drag pointer → drop target (band seam or tile edge, with hysteresis) |
| `core/snap.ts` | Alignment magnetism — boundaries lock to other tiles' edges |
| `core/codec.ts` | Persistence codec — decoding repairs (renormalize, collapse, dedupe) rather than rejects |
| `sensors/pointerDrag.ts` | One-shot pointer-capture drag primitive (PommoraDND vocabulary) |
| `SurfaceView.tsx` | The React surface — gestures, preview, settle, placement tint |
| `SurfaceLab.tsx` | Dev harness (demo + stress layouts) |

#### Resize Semantics

Resizing lives on each block's own edges and corners — window-style, never bars in the gaps.
Each edge resolves to a different op:

- **South** stretches the tile itself; nothing else moves, the page flows.
- **North** negotiates with the stacked tile directly above (pair clamp); nested-split
  neighbors decline and the edge falls back to nothing.
- **East/west** move the nearest ancestor row divider (ratio splitter, min-width clamp).
- Every boundary magnetizes to other tiles' edges within the `snapPx` radius.

#### Interaction Invariants

These are load-bearing; the comments at each site say why. Summarized:

- **Every gesture is snapshot → preview → commit/abort.** Deltas recompute from the frozen
  drag-origin layout — never accumulated against the preview. Hit-testing runs against the
  origin geometry so a shifting preview can't retarget the gesture.
- **Tiles render in stable id order, never tree order.** Reordering keyed DOM nodes mid-drag
  silently releases pointer capture — the pointerup never lands and the gesture zombies.
  Position is absolute, so DOM order costs nothing.
- **Decide-then-animate.** Releasing settles the block into its decided slot as a transition;
  the layout commits on `transitionend` with the engine's fallback timer, outside any React
  state updater.
- **The sensor aborts on Esc, `pointercancel`, and `lostpointercapture`** — capture torn away
  mid-gesture is an abort, never a zombie.
- **PommoraDND is the interaction vocabulary**: the shared `ACTIVATION` threshold,
  `suppressNextClick`, `HYSTERESIS` edge-hold, `findScroller`/`autoScroll`, and the shared
  `Feel` for reflow/settle. The sensor exists because the surface's free-2D gestures don't
  fit the engine's list-slot Zones — it reuses the discipline, not the machinery.
- **Handlers are identity-stable**, reading all live values through a per-render ref, so the
  memoized `TileShell` never re-renders for a callback identity change. The `renderTile`
  prop carries the same contract: identity-stable, no mutable per-tile closures.

#### Persistence Seam

`SurfaceView` is fully controlled: `layout` in, `onLayoutChange` out. The codec
round-trips the tree and repairs foreign or hand-edited input instead of blanking the host;
block payloads, unknown-key preservation, and the surrounding block document belong to the
block-doc layer above, not here.
