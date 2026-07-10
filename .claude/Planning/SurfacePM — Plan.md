# SurfacePM Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete SurfacePM — Pommora's in-house tessellated-mosaic layout engine — to live-tunable maturity on the Homepage lab, ready for the (separate, Figma-gated) block-surface feature arc to mount real tile content on it.

**Architecture:** A split-tree layout model (bands of nested row/column ratio splits, tiles as leaves — holes impossible by construction) with pure tessellation-preserving ops, a geometry resolver mapping the tree to pixel rects + divider hit zones, a pointer-capture sensor (rAF-coalesced, Esc-abort), and a controlled `SurfaceView` whose every gesture runs snapshot → preview → commit/abort, hit-testing against the frozen origin geometry. Spec: `7-10 - Block Surfaces — Decision Log.md` (B-1/B-4/B-7) + `7-10 - SurfacePM — RGL Teardown.md`.

**Tech Stack:** React 19 + TypeScript, Vitest, plain CSS (HMR-reliable), design-system tokens. Zero new dependencies.

## Global Constraints

- Branch: `surfacepm`. Gates on every task: `env -u ELECTRON_RUN_AS_NODE npm run typecheck` + `npx vitest run src/renderer/src/SurfacePM` (run from `Pommora/`), commit with explicit paths only (parallel sessions).
- Colors only via design-system tokens (`--separator-border`, `--accent`, `--fill-*`, `--label-*`); never hand-rolled hex.
- Block chassis knobs (Nathan live-tunes; current values): border `2px solid var(--separator-border)`, radius `18px`, inter-block gap `8px` (the `gap` prop default).
- No keyboard shortcuts beyond Esc-abort (the app's gesture law); the surface never captures ⌘Z.
- No per-frame allocations/layout reads in gesture paths — rAF-coalesced moves, previews recomputed from the frozen drag-origin snapshot, never accumulated.
- Biome formats on write — never hand-align; single quotes / no semicolons land automatically.
- Layout ops stay pure and immutable in `core/`; React/DOM only in components + sensors.

## Phase 0 — Built + Committed (recorded, not tasks)

Core (`core/model.ts` · `core/ops.ts` · `core/rects.ts` · `core/edges.ts`, 28 tests green): the band/split/leaf model, `splitAtTile` (same-dir sibling splice, no degenerate nesting) / `removeTile` (sibling absorb + collapse) / `moveTile` / `insertBand` / `moveTileToBand` (band-reorder index compensation, both directions tested) / `resizeDivider` (pair redistribution, min clamp) / `resizeBand`, `resolveEdge` (a block edge → its shared boundary: nearest same-dir ancestor divider, else the band bottom), `computeGeometry`, tessellation-invariant property test. Sensor (`sensors/pointerDrag.ts`): pointer capture, threshold, rAF, Esc/pointercancel abort. `SurfaceView.tsx`: controlled component, **window-style resize on block edges/corners** (corners drive both axes from one origin snapshot; no bars in the gaps), origin-geometry hit-testing, live post-move preview, ghost, the `is-interacting` transition gate. `SurfaceLab.tsx` mounted on the Homepage (`HomepageView.tsx`) + a showcase leaf (`surfacepm`). Chassis CSS per the knobs above, DRY'd to `--duration-*`/`--ease-standard`/`--state-ghost`.

---

### Task 1: Pure Hit-Testing with Between-Band Drop Targets

Drops currently target tile edges and append-at-bottom only; dropping a tile *between* bands (and above the first band) must create a band there. The hit-test also lives inside `SurfaceView.tsx` untested — extract it to core. Two review-forced corrections ride along: **(a)** `bandEdges` in `core/rects.ts` currently emits its `y` at the band bottom **minus** gap/2 (the removed bars' anchor); its only consumer is now hit-testing, so re-emit it as the **seam centerline** — band bottom **plus** gap/2 — and update the `computeGeometry` expectations. **(b)** The zone thresholds are Nathan's live-tuning knobs and must not fuse: `bandZonePx` (targeting: above-first / between / append) is a separate prop from the bottom padding strip (`bottomPadPx`, replacing `bandDropPx`'s double duty); tests must run at the values `SurfaceView` actually passes, not only the default.

**Files:**
- Create: `Pommora/src/renderer/src/SurfacePM/core/hitTest.ts`
- Create: `Pommora/src/renderer/src/SurfacePM/core/hitTest.test.ts`
- Modify: `Pommora/src/renderer/src/SurfacePM/core/rects.ts` (bandEdges → seam centerlines) + `core/ops.test.ts` geometry expectations if touched
- Modify: `Pommora/src/renderer/src/SurfacePM/SurfaceView.tsx` (delete its local `hitTest`, import the core one; `bandDropPx` prop splits into `bandZonePx` + `bottomPadPx`)

**Interfaces:**
- Consumes: `SurfaceGeometry` from `core/rects.ts`, `SurfaceLayout`/`Edge` from `core/model.ts`.
- Produces: `export type DropTarget = { kind: 'tile'; id: string; edge: Edge } | { kind: 'band'; index: number } | null` and `export function hitTest(geometry: SurfaceGeometry, layout: SurfaceLayout, dragId: string, px: number, py: number, bandZonePx?: number): DropTarget` — `SurfaceView` and later consumers import both from `core/hitTest`.

- [ ] **Step 1: Write the failing tests**

```ts
// core/hitTest.test.ts
import { describe, expect, it } from 'vitest'
import { insertBand, splitAtTile } from './ops'
import { computeGeometry } from './rects'
import { hitTest } from './hitTest'

const two = insertBand(insertBand({ bands: [] }, 0, 'a', 200), 1, 'b', 200)
const geo = computeGeometry(two, 1000, 8)

describe('hitTest', () => {
  it('targets a tile edge by nearest normalized distance', () => {
    expect(hitTest(geo, two, 'b', 950, 100)).toEqual({ kind: 'tile', id: 'a', edge: 'e' })
    expect(hitTest(geo, two, 'b', 500, 10)).toEqual({ kind: 'tile', id: 'a', edge: 'n' })
  })
  it('targets the gap between bands as a band insertion', () => {
    expect(hitTest(geo, two, 'b', 500, 204)).toEqual({ kind: 'band', index: 1 })
  })
  it('targets above the first band as index 0', () => {
    expect(hitTest(geo, two, 'b', 500, -2)).toEqual({ kind: 'band', index: 0 })
  })
  it('targets past the bottom as an append', () => {
    expect(hitTest(geo, two, 'b', 500, geo.totalHeight + 10)).toEqual({ kind: 'band', index: 2 })
  })
  it('never targets the dragged tile itself', () => {
    expect(hitTest(geo, two, 'a', 500, 100)).toBeNull()
  })
})
```

- [ ] **Step 2: Run to verify failure** — `npx vitest run src/renderer/src/SurfacePM/core/hitTest.test.ts` → FAIL (module not found).

- [ ] **Step 3: Implement `core/hitTest.ts`**

```ts
import type { Edge, SurfaceLayout } from './model'
import type { SurfaceGeometry } from './rects'

export type DropTarget =
  | { kind: 'tile'; id: string; edge: Edge }
  | { kind: 'band'; index: number }
  | null

/** Resolve a pointer position to a drop target: a band gap (between/above/below
 *  bands, within ±bandZonePx of the seam) wins over the tile underneath it;
 *  otherwise the hovered tile's nearest edge; never the dragged tile itself. */
export function hitTest(
  geometry: SurfaceGeometry,
  layout: SurfaceLayout,
  dragId: string,
  px: number,
  py: number,
  bandZonePx = 10
): DropTarget {
  if (py < bandZonePx) return { kind: 'band', index: 0 }
  if (py > geometry.totalHeight - bandZonePx) return { kind: 'band', index: layout.bands.length }
  for (const seam of geometry.bandEdges.slice(0, -1)) {
    if (Math.abs(py - seam.y) <= bandZonePx) return { kind: 'band', index: seam.band + 1 }
  }
  for (const [id, r] of geometry.tiles) {
    if (id === dragId) continue
    if (px < r.x || px > r.x + r.w || py < r.y || py > r.y + r.h) continue
    const dists: Array<[Edge, number]> = [
      ['w', (px - r.x) / r.w],
      ['e', 1 - (px - r.x) / r.w],
      ['n', (py - r.y) / r.h],
      ['s', 1 - (py - r.y) / r.h]
    ]
    dists.sort((a, b) => a[1] - b[1])
    return { kind: 'tile', id, edge: dists[0]?.[0] ?? 'e' }
  }
  return null
}
```

- [ ] **Step 4: Fix `bandEdges` emission + run tests** — in `core/rects.ts`, emit each band seam at `y + gap / 2` *after* `y += band.height` (the centerline of the visual gap), then run → PASS. Add one hitTest case at `bandZonePx: 10` AND one at the runtime value SurfaceView passes, so the seam zones are proven not to swallow tile interiors at real tuning values.

- [ ] **Step 5: Swap `SurfaceView` to the core hitTest** — delete its local `hitTest` + `DropTarget`, `import { hitTest, type DropTarget } from './core/hitTest'`; split the old `bandDropPx` into `bandZonePx` (targeting, default 10) and `bottomPadPx` (the host's bottom drop-room strip, default 28), threading `bandZonePx` into `hitTest`. Full suite + typecheck.

- [ ] **Step 6: Commit** — `git add Pommora/src/renderer/src/SurfacePM && git commit -m "feat(surfacepm): pure hitTest with between-band drop targets"`

---

### Task 2: Layout Codec + Normalization

The tree will persist inside host sidecars (Decision Log D-3); the engine ships its codec now: a zod schema, a decoder that **repairs** rather than rejects (drifted ratios renormalize, ratio/child count mismatches rebuild uniform, sub-minimum bands floor), and round-trip tests. Foreign-key preservation stays the *block-doc* layer's job (E-1) — this codec is for the `layout` subtree only.

**Files:**
- Create: `Pommora/src/renderer/src/SurfacePM/core/codec.ts`
- Create: `Pommora/src/renderer/src/SurfacePM/core/codec.test.ts`

**Interfaces:**
- Consumes: `SurfaceLayout`/`LayoutNode` from `core/model.ts`; `zod` (already a dependency).
- Produces: `export function decodeLayout(raw: unknown): SurfaceLayout | null` (null = unusable, caller falls back to empty) and `export function encodeLayout(layout: SurfaceLayout): unknown` (plain JSON shape, stable key order not required).

- [ ] **Step 1: Failing tests**

```ts
// core/codec.test.ts
import { describe, expect, it } from 'vitest'
import { validateLayout } from './model'
import { insertBand, splitAtTile } from './ops'
import { decodeLayout, encodeLayout } from './codec'

describe('codec', () => {
  it('round-trips a real layout', () => {
    const l = splitAtTile(insertBand({ bands: [] }, 0, 'a', 200), 'a', 'e', 'b', 0.3)
    expect(decodeLayout(encodeLayout(l))).toEqual(l)
  })
  it('repairs drifted ratios by renormalizing', () => {
    const raw = {
      bands: [
        {
          height: 200,
          node: {
            kind: 'split',
            dir: 'row',
            ratios: [2, 2],
            children: [
              { kind: 'tile', id: 'a' },
              { kind: 'tile', id: 'b' }
            ]
          }
        }
      ]
    }
    const l = decodeLayout(raw)
    expect(l && validateLayout(l)).toEqual([])
    expect(l?.bands[0]?.node).toMatchObject({ ratios: [0.5, 0.5] })
  })
  it('rebuilds a ratio/children count mismatch as uniform', () => {
    const raw = {
      bands: [
        {
          height: 120,
          node: {
            kind: 'split',
            dir: 'column',
            ratios: [1],
            children: [
              { kind: 'tile', id: 'a' },
              { kind: 'tile', id: 'b' }
            ]
          }
        }
      ]
    }
    expect(decodeLayout(raw)?.bands[0]?.node).toMatchObject({ ratios: [0.5, 0.5] })
  })
  it('collapses a single-child split and floors band heights', () => {
    const raw = {
      bands: [
        { height: -5, node: { kind: 'split', dir: 'row', ratios: [1], children: [{ kind: 'tile', id: 'a' }] } }
      ]
    }
    const l = decodeLayout(raw)
    expect(l?.bands[0]).toMatchObject({ height: 80, node: { kind: 'tile', id: 'a' } })
  })
  it('returns null for garbage', () => {
    expect(decodeLayout(42)).toBeNull()
    expect(decodeLayout({ bands: 'no' })).toBeNull()
  })
})
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement `core/codec.ts`**

```ts
import { z } from 'zod'
import type { LayoutNode, SurfaceLayout } from './model'

const MIN_BAND = 80

const tileSchema = z.object({ kind: z.literal('tile'), id: z.string().min(1) })
const splitSchema: z.ZodType<unknown> = z.lazy(() =>
  z.object({
    kind: z.literal('split'),
    dir: z.enum(['row', 'column']),
    ratios: z.array(z.number()),
    children: z.array(z.union([tileSchema, splitSchema])).min(1)
  })
)
const layoutSchema = z.object({
  bands: z.array(z.object({ height: z.number(), node: z.union([tileSchema, splitSchema]) }))
})

function repairNode(node: z.infer<typeof layoutSchema>['bands'][number]['node']): LayoutNode {
  if ((node as { kind: string }).kind === 'tile') return node as LayoutNode
  const split = node as { dir: 'row' | 'column'; ratios: number[]; children: unknown[] }
  const children = split.children.map((c) => repairNode(c as never))
  if (children.length === 1) return children[0] as LayoutNode
  const positive = split.ratios.filter((r) => r > 0)
  const ratios =
    positive.length === children.length
      ? (() => {
          const sum = positive.reduce((a, r) => a + r, 0)
          return positive.map((r) => r / sum)
        })()
      : children.map(() => 1 / children.length)
  return { kind: 'split', dir: split.dir, ratios, children }
}

export function decodeLayout(raw: unknown): SurfaceLayout | null {
  const parsed = layoutSchema.safeParse(raw)
  if (!parsed.success) return null
  return {
    bands: parsed.data.bands.map((b) => ({
      height: Math.max(MIN_BAND, b.height),
      node: repairNode(b.node)
    }))
  }
}

export function encodeLayout(layout: SurfaceLayout): unknown {
  return JSON.parse(JSON.stringify(layout))
}
```

- [ ] **Step 4: Run → PASS.** Type the recursive schema **concretely** per the repo's own precedent (`shared/views.ts:159` types its recursive `FilterGroup` schema as `z.ZodType<FilterGroup>`): declare a raw-shape interface and use `z.ZodType<RawSplit>` rather than `z.ZodType<unknown>` + casts.

- [ ] **Step 5: Commit** — `git commit -m "feat(surfacepm): layout codec — repairing decoder + round-trip"`

---

### Task 3: Render Performance — Memoized Tiles + Drag-Time Transition Gate

Every gesture currently re-renders every tile (inline arrow props), and mid-drag previews animate through the 140ms transition, smearing the feel. Memoize the tile shell on its rect + drag flags, hoist per-tile callbacks, and gate transitions off while a gesture is live.

**Files:**
- Modify: `Pommora/src/renderer/src/SurfacePM/SurfaceView.tsx`
- Modify: `Pommora/src/renderer/src/SurfacePM/surfacepm.css`

**Interfaces:**
- Consumes: existing internals only.
- Produces: no API change; `SurfaceView` gains `<div className="spm-surface is-interacting">` while any gesture is live.

- [ ] **Step 1: Extract a memoized `TileShell`** inside `SurfaceView.tsx`:

```tsx
const TileShell = React.memo(function TileShell({
  id,
  rect,
  dragging,
  targetEdge,
  onHandleDown,
  children
}: {
  id: string
  rect: Rect
  dragging: boolean
  targetEdge: Edge | null
  onHandleDown: (id: string) => (e: React.PointerEvent) => void
  children: React.ReactNode
}) {
  return (
    <div
      className={`spm-tile${dragging ? ' is-dragging' : ''}${targetEdge ? ` is-target edge-${targetEdge}` : ''}`}
      style={{ transform: `translate(${rect.x}px, ${rect.y}px)`, width: rect.w, height: rect.h }}
    >
      <div className="spm-handle" onPointerDown={onHandleDown(id)} />
      <div className="spm-tile-body">{children}</div>
    </div>
  )
}, (a, b) =>
  a.id === b.id &&
  a.dragging === b.dragging &&
  a.targetEdge === b.targetEdge &&
  a.onHandleDown === b.onHandleDown &&
  a.rect.x === b.rect.x && a.rect.y === b.rect.y && a.rect.w === b.rect.w && a.rect.h === b.rect.h &&
  a.children === b.children
)
```

Make `onHandleDown` (and `onEdgeDown`) stable `useCallback`s reading live state through refs — **every live value they touch, not just `layout`** (review round 1 falsified the layout-ref-suffices shortcut: a mount-frozen `originGeometry` makes tiles added after mount undraggable and targets stale rects). Concretely: `const liveRef = useRef({ layout, originGeometry, commit, bandZonePx }); liveRef.current = { … }` — the down handler snapshots `liveRef.current` once at gesture start; nothing inside the gesture reads a closed-over prop/memo directly.

Drop `children` from the comparator entirely (a `renderTile` call mints a fresh element every render, so a `children` identity check makes the memo inert) — instead `TileShell` receives `renderTile` itself and calls it internally, with the memo comparing `renderTile` by identity. `SurfaceLab` (and any consumer) must pass a `useCallback`-stable `renderTile`; note this in the `SurfaceViewProps` doc comment.

- [ ] **Step 2: Verify the gesture transition gate** — `.spm-surface.is-interacting .spm-tile { transition: none }` and the `is-interacting` class (off `tileDrag || resizingId`) already shipped with the edge-resize rework; this step only confirms it survives the TileShell restructure (previews track the pointer 1:1; the ease belongs to committed settles only).

- [ ] **Step 3: Stress preset** — in `SurfaceLab.tsx`, add a `Stress (60)` button: builds 6 bands × alternating splits down to ~60 tiles via a loop of `splitAtTile`. Verify by feel in the lab: divider drags stay smooth, tile drag previews don't animate.

- [ ] **Step 4: Gates + commit** — full suite + typecheck; `git commit -m "perf(surfacepm): memoized tiles + gesture transition gate + stress preset"`

---

### Task 4: Sensor + Gesture Hardening Tests

The sensor and the gesture lifecycle carry the engine's correctness guarantees (Esc law, snapshot discipline) with zero test coverage. Cover them headlessly.

**Files:**
- Create: `Pommora/src/renderer/src/SurfacePM/sensors/pointerDrag.test.ts`

**Interfaces:** consumes `startPointerDrag` only; no new API.

- [ ] **Step 1: Failing tests** — **line 1 of the file MUST be `// @vitest-environment jsdom`** (the repo's vitest default is `environment: 'node'`; every DOM test opts in per-file — without the pragma this suite dies on `document is not defined` before a single assertion). vitest's jsdom is `pretendToBeVisual`, so `cancelAnimationFrame` exists. Stub `setPointerCapture`/`hasPointerCapture`/`releasePointerCapture` on the element:

```ts
// @vitest-environment jsdom
import { describe, expect, it, vi } from 'vitest'
import { startPointerDrag } from './pointerDrag'

function harness() {
  const el = document.createElement('div')
  el.setPointerCapture = vi.fn()
  el.releasePointerCapture = vi.fn()
  el.hasPointerCapture = vi.fn(() => true)
  document.body.appendChild(el)
  const moves: Array<[number, number]> = []
  let ended: boolean | null = null
  const start = (): void =>
    startPointerDrag(
      { currentTarget: el, pointerId: 1, clientX: 100, clientY: 100 } as unknown as React.PointerEvent,
      { threshold: 3, onMove: (dx, dy) => moves.push([dx, dy]), onEnd: (c) => (ended = c) }
    )
  const fire = (type: string, x: number, y: number): void => {
    el.dispatchEvent(Object.assign(new Event(type), { clientX: x, clientY: y, pointerId: 1 }))
  }
  return { el, moves, endedRef: () => ended, start, fire }
}

describe('startPointerDrag', () => {
  it('does not arm under the threshold and reports an unarmed release as abort', () => {
    const h = harness()
    h.start()
    h.fire('pointermove', 101, 101)
    h.fire('pointerup', 101, 101)
    expect(h.moves).toEqual([])
    expect(h.endedRef()).toBe(false)
  })
  it('arms past the threshold, coalesces to rAF, commits on up', async () => {
    vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => (cb(0), 1))
    const h = harness()
    h.start()
    h.fire('pointermove', 120, 100)
    h.fire('pointerup', 120, 100)
    expect(h.moves.at(-1)).toEqual([20, 0])
    expect(h.endedRef()).toBe(true)
    vi.unstubAllGlobals()
  })
  it('aborts on Escape without firing commit', () => {
    vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => (cb(0), 1))
    const h = harness()
    h.start()
    h.fire('pointermove', 130, 100)
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
    expect(h.endedRef()).toBe(false)
    h.fire('pointermove', 200, 100)
    expect(h.moves.at(-1)).toEqual([30, 0])
    vi.unstubAllGlobals()
  })
})
```

- [ ] **Step 2: Run → adjust the sensor if a real defect surfaces** (expected: the unarmed-release case currently calls `finish(armed)` with `armed === false` → abort ✓; the post-abort move listener must already be removed — the test's final assertion pins that). Fix any listener leak found; the tests are the spec.

- [ ] **Step 3: Commit** — `git commit -m "test(surfacepm): sensor lifecycle — threshold, rAF coalesce, Esc abort"`

---

### Task 5: Band-Resize Semantics Toggle (Nathan's Live A/B)

The decision log deliberately leaves vertical feel to live tuning. Give the lab the A/B: band bottom-edge drag either **flows** (page grows/shrinks — current behavior) or **redistributes** with the next band (total height constant, splitter-style).

**Files:**
- Modify: `Pommora/src/renderer/src/SurfacePM/core/ops.ts` (add `resizeBandPair`)
- Modify: `Pommora/src/renderer/src/SurfacePM/core/ops.test.ts`
- Modify: `Pommora/src/renderer/src/SurfacePM/SurfaceView.tsx` (a `bandResizeMode?: 'flow' | 'redistribute'` prop, default `'flow'`)
- Modify: `Pommora/src/renderer/src/SurfacePM/SurfaceLab.tsx` (mode toggle)

**Interfaces:**
- Produces: `export function resizeBandPair(layout: SurfaceLayout, band: number, deltaPx: number, minPx: number): SurfaceLayout` — grows `band` by `deltaPx`, shrinks `band + 1` by the same amount, both clamped to `minPx`; the last band's edge always flows.

- [ ] **Step 1: Failing tests**

```ts
describe('resizeBandPair', () => {
  const two = insertBand(insertBand({ bands: [] }, 0, 'a', 200), 1, 'b', 200)
  it('redistributes between neighbors, total constant', () => {
    const l = resizeBandPair(two, 0, 50, 80)
    expect(l.bands[0]?.height).toBe(250)
    expect(l.bands[1]?.height).toBe(150)
  })
  it('clamps both sides to the minimum', () => {
    const l = resizeBandPair(two, 0, 500, 80)
    expect(l.bands[1]?.height).toBe(80)
    expect(l.bands[0]?.height).toBe(320)
  })
  it('flows on the last band (no next neighbor)', () => {
    const l = resizeBandPair(two, 1, 70, 80)
    expect(l.bands[1]?.height).toBe(270)
    expect(l.bands[0]?.height).toBe(200)
  })
})
```

- [ ] **Step 2: Implement** —

```ts
export function resizeBandPair(
  layout: SurfaceLayout,
  band: number,
  deltaPx: number,
  minPx: number
): SurfaceLayout {
  const a = layout.bands[band]
  const b = layout.bands[band + 1]
  if (!a) return layout
  if (!b) return resizeBand(layout, band, deltaPx, minPx)
  const delta = clamp(deltaPx, minPx - a.height, b.height - minPx)
  const next = cloneLayout(layout)
  ;(next.bands[band] as Band).height = a.height + delta
  ;(next.bands[band + 1] as Band).height = b.height - delta
  return next
}
```

- [ ] **Step 3: Wire the prop + lab toggle** — `onBandEdgeDown` picks `resizeBand` vs `resizeBandPair` off the prop; the lab renders a two-option toggle labeled `Band Resize: Flow / Redistribute`.

- [ ] **Step 4: Gates + commit** — `git commit -m "feat(surfacepm): band-resize A/B — flow vs redistribute, lab toggle"`

---

### Task 6: Module README + Attribution

**Files:**
- Create: `Pommora/src/renderer/src/SurfacePM/README.md`

**Interfaces:** none.

- [ ] **Step 1: Write it** — what SurfacePM is (the tessellation invariant, the split-tree model, snapshot→preview→commit), the module map (core / sensors / SurfaceView / SurfaceLab), the chassis knobs and where they live, and the provenance note: *engineered against a full teardown of react-grid-layout v2.2.3 (MIT) — patterns studied, no code copied; teardown record → `.claude/Planning/7-10 - SurfacePM — RGL Teardown.md`.* Name tokens, never literal values (docs name; code holds exacts).

- [ ] **Step 2: Commit** — `git commit -m "docs(surfacepm): module README + provenance"`
