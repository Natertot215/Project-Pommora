import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { autoScroll, findScroller } from '@renderer/design-system/interactions/autoscroll'
import { DEFAULT_FEEL, type Feel } from '@renderer/design-system/interactions/feel'
import { SETTLE_FALLBACK } from '@renderer/design-system/interactions/shared'
import { findTile } from './core/model'
import type { DividerRef, Edge, SurfaceLayout } from './core/model'
import { resolveEdge } from './core/edges'
import { hitTest, type DropTarget } from './core/hitTest'
import { moveTile, moveTileToBand, resizeBandPair, resizeDivider, resizeStackPair, stretchTileHeight } from './core/ops'
import { computeGeometry, type Rect, type SurfaceGeometry } from './core/rects'
import { snapAxis, xCandidates, yCandidates } from './core/snap'
import { startPointerDrag } from './sensors/pointerDrag'
import './surfacepm.css'

// The SurfacePM surface: a layout tree rendered as absolutely-positioned blocks,
// with PommoraDND's interaction feel throughout. Moving a block lifts THE BLOCK
// ITSELF under the pointer (shadowed, 1:1, no ghost) while its siblings reflow
// through the shared Feel transition; releasing settles it into its slot as an
// animation and the layout commits on transitionend (decide-then-animate, with
// the engine's fallback timer). Resizing lives on each block's own edges and
// corners — an edge drag moves the shared boundary it resolves to (core/edges),
// tracking 1:1 with transitions gated off. Every gesture is snapshot → preview →
// commit/abort against the frozen drag-origin layout; Esc settles home.

export interface SurfaceViewProps {
  layout: SurfaceLayout
  onLayoutChange: (layout: SurfaceLayout) => void
  /** MUST be identity-stable (useCallback) — tiles memoize on it. Corollary: it
   *  must not close over mutable per-tile data (the memo would skip the update);
   *  content that changes renders a component that subscribes to its own state. */
  renderTile: (id: string, rect: Rect) => React.ReactNode
  gap?: number
  minTilePx?: number
  /** Band-targeting zone radius (above-first / between-band seams) — a live-tuning knob. */
  bandZonePx?: number
  /** Extra empty room below the last band; dropping there appends a new band. */
  bottomPadPx?: number
  /** Resize boundaries magnetize to other blocks' edges within this many px. */
  snapPx?: number
  /** The displacement feel (defaults to the engine's Smooth). */
  feel?: Feel
  /** Per-tile chassis class (e.g. the host's style variants) — engine-agnostic. */
  tileClassName?: (id: string) => string | undefined
  /** A tile that answers true is STATIC — its drag + resize gestures are frozen (its handle still
   *  opens the menu). The host derives it (e.g. a locked block); the engine only gates the gesture. */
  isTileStatic?: (id: string) => boolean
  /** Click / right-click on a tile's drag handle — the host's menu hook. */
  onHandleMenu?: (id: string, e: React.MouseEvent) => void
  /** Right-click on the surface BACKGROUND — resolved to a semantic create target:
   *  a ragged wedge under a tile (fill it flush to the row bottom) or a plain
   *  append below all content. */
  onBackdrop?: (target: BackdropTarget, e: React.MouseEvent) => void
}

export type BackdropTarget = { kind: 'append' } | { kind: 'wedge'; above: string; fillPx: number }

type TilePhase = 'idle' | 'reflow' | 'lifted' | 'settling'

interface TileDrag {
  id: string
  lift: Rect
}

interface Settle {
  id: string
  to: Rect
  next: SurfaceLayout | null
}

/** How close (px, from the tile's top-left corner) the pointer must be to reveal
 *  a caret-active tile's handle — the proximity affordance knob. */
const HANDLE_REVEAL_PX = 240
// How long the width-tracking flag holds after the ResizeObserver goes quiet (sidebar/inspector settle).
const TRACK_SETTLE_MS = 160

const EDGE_ZONES: Array<{ zone: string; edges: Edge[] }> = [
  { zone: 'n', edges: ['n'] },
  { zone: 's', edges: ['s'] },
  { zone: 'e', edges: ['e'] },
  { zone: 'w', edges: ['w'] },
  { zone: 'ne', edges: ['n', 'e'] },
  { zone: 'nw', edges: ['n', 'w'] },
  { zone: 'se', edges: ['s', 'e'] },
  { zone: 'sw', edges: ['s', 'w'] }
]

const refKey = (ref: { band: number; path: number[]; index: number }): string =>
  `${ref.band}|${ref.path.join('.')}|${ref.index}`

interface LiveState {
  layout: SurfaceLayout
  originGeometry: SurfaceGeometry
  bandZonePx: number
  minTilePx: number
  gap: number
  snapPx: number
  feel: Feel
}

const TileShell = memo(
  function TileShell({
    id,
    rect,
    phase,
    feel,
    resizing,
    extraClass,
    renderTile,
    onHandleDown,
    onHandleMenu,
    onEdgeDown,
    onSettled
  }: {
    id: string
    rect: Rect
    phase: TilePhase
    feel: Feel
    resizing: boolean
    extraClass?: string
    renderTile: (id: string, rect: Rect) => React.ReactNode
    onHandleDown: (id: string, e: React.PointerEvent) => void
    onHandleMenu?: (id: string, e: React.MouseEvent) => void
    onEdgeDown: (id: string, edges: Edge[], e: React.PointerEvent) => void
    onSettled: (id: string) => void
  }) {
    const transition =
      phase === 'lifted'
        ? 'none'
        : phase === 'reflow' || phase === 'settling'
          ? `transform ${feel.duration}ms ${feel.easing}, width ${feel.duration}ms ${feel.easing}, height ${feel.duration}ms ${feel.easing}`
          : undefined
    // Proximity reveal: distance from the tile's top-left corner, rect cached on
    // enter (no per-move layout reads), state flips only on threshold crossing.
    // CSS decides who uses it (caret-active tiles reveal their handle by it).
    const [handleNear, setHandleNear] = useState(false)
    const cornerRef = useRef<{ x: number; y: number } | null>(null)
    return (
      <div
        className={`spm-tile${phase === 'lifted' || phase === 'settling' ? ' is-lifted' : ''}${
          resizing ? ' is-resizing' : ''
        }${extraClass ? ` ${extraClass}` : ''}${handleNear ? ' handle-near' : ''}`}
        onPointerEnter={(e) => {
          const r = e.currentTarget.getBoundingClientRect()
          cornerRef.current = { x: r.left, y: r.top }
        }}
        onPointerMove={(e) => {
          const c = cornerRef.current
          if (!c) return
          const near = Math.hypot(e.clientX - c.x, e.clientY - c.y) < HANDLE_REVEAL_PX
          if (near !== handleNear) setHandleNear(near)
        }}
        onPointerLeave={() => {
          cornerRef.current = null
          if (handleNear) setHandleNear(false)
        }}
        style={{
          transform: `translate(${rect.x}px, ${rect.y}px)`,
          width: rect.w,
          height: rect.h,
          transition
        }}
        onTransitionEnd={(e) => {
          // Target-guarded: tile CONTENT animating a transform bubbles its
          // transitionend up here — only the shell's own settle may commit.
          if (phase === 'settling' && e.target === e.currentTarget && e.propertyName === 'transform')
            onSettled(id)
        }}
      >
        {/* Unarmed clicks pass through the sensor (suppressNextClick fires only on
            armed drags) — click and right-click both open the host's handle menu. */}
        <div
          className="spm-handle"
          onPointerDown={(e) => onHandleDown(id, e)}
          onClick={(e) => onHandleMenu?.(id, e)}
          onContextMenu={(e) => {
            e.preventDefault()
            onHandleMenu?.(id, e)
          }}
        />
        {EDGE_ZONES.map(({ zone, edges }) => (
          <div
            key={zone}
            className={`spm-edge spm-edge-${zone}`}
            onPointerDown={(e) => onEdgeDown(id, edges, e)}
          />
        ))}
        <div className="spm-tile-body">{renderTile(id, rect)}</div>
      </div>
    )
  },
  (a, b) =>
    a.id === b.id &&
    a.phase === b.phase &&
    a.feel === b.feel &&
    a.resizing === b.resizing &&
    a.extraClass === b.extraClass &&
    a.renderTile === b.renderTile &&
    a.onHandleDown === b.onHandleDown &&
    a.onHandleMenu === b.onHandleMenu &&
    a.onEdgeDown === b.onEdgeDown &&
    a.onSettled === b.onSettled &&
    a.rect.x === b.rect.x &&
    a.rect.y === b.rect.y &&
    a.rect.w === b.rect.w &&
    a.rect.h === b.rect.h
)

export function SurfaceView({
  layout,
  onLayoutChange,
  renderTile,
  gap = 8,
  minTilePx = 64,
  bandZonePx = 10,
  bottomPadPx = 28,
  snapPx = 9,
  feel = DEFAULT_FEEL,
  tileClassName,
  isTileStatic,
  onHandleMenu,
  onBackdrop
}: SurfaceViewProps): React.JSX.Element {
  const hostRef = useRef<HTMLDivElement | null>(null)
  const [width, setWidth] = useState(0)
  const [draft, setDraft] = useState<SurfaceLayout | null>(null)
  const [tileDrag, setTileDrag] = useState<TileDrag | null>(null)
  const [settle, setSettle] = useState<Settle | null>(null)
  const [resizingId, setResizingId] = useState<string | null>(null)

  // While the surface WIDTH is animating (sidebar/inspector toggling), tiles must
  // track 1:1 — their own width transition would lag the pane. `tracking` holds
  // until the observer goes quiet.
  const [tracking, setTracking] = useState(false)
  const trackingSettle = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => {
    const el = hostRef.current
    if (!el) return
    setWidth(el.clientWidth)
    const ro = new ResizeObserver(() => {
      setWidth(el.clientWidth)
      setTracking(true)
      if (trackingSettle.current) clearTimeout(trackingSettle.current)
      trackingSettle.current = setTimeout(() => setTracking(false), TRACK_SETTLE_MS)
    })
    ro.observe(el)
    return () => {
      ro.disconnect()
      if (trackingSettle.current) clearTimeout(trackingSettle.current)
    }
  }, [])

  const shown = draft ?? layout
  const geometry = useMemo(
    () => computeGeometry(shown, Math.max(0, width), gap),
    [shown, width, gap]
  )
  // Hit-testing and boundary extents run against the frozen origin's geometry —
  // a preview shifting under the pointer must never retarget the gesture.
  const originGeometry = useMemo(
    () => computeGeometry(layout, Math.max(0, width), gap),
    [layout, width, gap]
  )

  // Every live value a gesture reads, refreshed each render — the handlers stay
  // identity-stable while never seeing a stale layout, geometry, or knob.
  const live = useRef<LiveState>({
    layout,
    originGeometry,
    bandZonePx,
    minTilePx,
    gap,
    snapPx,
    feel
  })
  live.current = { layout, originGeometry, bandZonePx, minTilePx, gap, snapPx, feel }

  const layoutRef = useRef(layout)
  layoutRef.current = layout
  const onLayoutChangeRef = useRef(onLayoutChange)
  onLayoutChangeRef.current = onLayoutChange
  // Static tiles freeze their gestures — read through a ref so the memoized gesture callbacks stay
  // identity-stable (a changing predicate must not re-render every tile).
  const isTileStaticRef = useRef(isTileStatic)
  isTileStaticRef.current = isTileStatic

  // Decide-then-animate: the settle transition ends (or the engine's fallback
  // timer fires) → the decided layout commits and the gesture state clears. The
  // ref mirrors the state so the commit runs as a plain event side effect —
  // never inside a state updater (React forbids cross-component updates there).
  const settleRef = useRef<Settle | null>(null)
  const finishSettle = useCallback((id: string) => {
    const s = settleRef.current
    if (!s || s.id !== id) return
    settleRef.current = null
    setSettle(null)
    setDraft(null)
    if (s.next && s.next !== layoutRef.current) onLayoutChangeRef.current(s.next)
  }, [])

  useEffect(() => {
    if (!settle) return
    const t = setTimeout(() => finishSettle(settle.id), live.current.feel.duration + SETTLE_FALLBACK)
    return () => clearTimeout(t)
  }, [settle, finishSettle])

  // A gesture starting during a live settle takes over: finalize the pending
  // commit NOW and hand back the decided layout — the parent hasn't re-rendered
  // yet, so live.current still holds the pre-commit origin, and a gesture built
  // on that stale origin would silently erase the just-dropped move.
  const takePendingSettle = useCallback((): SurfaceLayout | null => {
    const s = settleRef.current
    if (!s) return null
    finishSettle(s.id)
    return s.next
  }, [finishSettle])

  // The boundary's own edge is always among the snap candidates — left in, it
  // magnetizes the drag back to its start and makes sub-snapPx adjustment
  // impossible (a dead band on every resize). Filter it per action.
  const withoutOwn = (candidates: number[], start: number): number[] =>
    candidates.filter((c) => Math.abs(c - start) > 0.5)

  const onEdgeDown = useCallback((id: string, edges: Edge[], e: React.PointerEvent) => {
    if (e.button !== 0 || isTileStaticRef.current?.(id)) return
    e.preventDefault()
    e.stopPropagation()
    const pending = takePendingSettle()
    const { minTilePx: minT, snapPx: snap } = live.current
    const origin = pending ?? live.current.layout
    const host = hostRef.current
    const g =
      pending && host
        ? computeGeometry(pending, Math.max(0, host.clientWidth), live.current.gap)
        : live.current.originGeometry
    const ownRect = g.tiles.get(id)
    if (!ownRect) return
    const extents = new Map(g.dividers.map((d) => [refKey(d.ref), d.extentPx]))
    const dividerX = new Map(g.dividers.map((d) => [refKey(d.ref), d.x]))
    const snapX = xCandidates(g)
    const snapY = yCandidates(g)
    // South edges STRETCH — exactly one tile grows, the page flows. North edges
    // negotiate the stacked boundary above; east/west move the row splitter.
    // Each action carries its boundary's start px + own-edge-filtered candidates
    // so its delta can magnetize to OTHER blocks' edges (the alignment form-lock).
    type Action =
      | { edge: Edge; kind: 'stretch'; start: number; cands: number[] }
      | { edge: Edge; kind: 'divider'; ref: DividerRef; start: number; cands: number[] }
      | { edge: Edge; kind: 'stack'; ref: DividerRef; start: number; cands: number[] }
      | { edge: Edge; kind: 'bandpair'; above: number; start: number; cands: number[] }
    const actions: Action[] = []
    for (const edge of edges) {
      if (edge === 's') {
        const start = ownRect.y + ownRect.h
        actions.push({ edge, kind: 'stretch', start, cands: withoutOwn(snapY, start) })
        continue
      }
      const boundary = resolveEdge(origin, id, edge)
      if (!boundary) continue
      if (boundary.kind === 'bandpair') {
        const start = ownRect.y
        actions.push({ edge, kind: 'bandpair', above: boundary.above, start, cands: withoutOwn(snapY, start) })
        continue
      }
      const start =
        boundary.kind === 'divider'
          ? (dividerX.get(refKey(boundary.ref)) ?? ownRect.x)
          : ownRect.y
      const axis = boundary.kind === 'divider' ? snapX : snapY
      actions.push({ edge, kind: boundary.kind, ref: boundary.ref, start, cands: withoutOwn(axis, start) })
    }
    if (actions.length === 0) return

    setResizingId(id)
    let latest: SurfaceLayout = origin
    startPointerDrag(e, {
      threshold: 0,
      onMove: (dx, dy) => {
        latest = actions.reduce((acc, action) => {
          const raw = action.kind === 'divider' ? dx : dy
          const delta = snapAxis(action.start + raw, action.cands, snap) - action.start
          if (action.kind === 'stretch') return stretchTileHeight(acc, id, delta, minT)
          if (action.kind === 'stack') return resizeStackPair(acc, action.ref, delta, minT)
          if (action.kind === 'bandpair') return resizeBandPair(acc, action.above, delta, minT)
          const extent = extents.get(refKey(action.ref)) ?? 0
          return resizeDivider(acc, action.ref, delta, extent, minT)
        }, origin)
        setDraft(latest)
      },
      onEnd: (commitDrag) => {
        setResizingId(null)
        setDraft(null)
        if (commitDrag && latest !== origin) onLayoutChangeRef.current(latest)
      }
    })
  }, [])

  const onHandleDown = useCallback((id: string, e: React.PointerEvent) => {
    if (e.button !== 0 || isTileStaticRef.current?.(id)) return
    e.preventDefault()
    e.stopPropagation()
    const pending = takePendingSettle()
    const zone = live.current.bandZonePx
    const origin = pending ?? live.current.layout
    const host = hostRef.current
    if (!host) return
    const g = pending
      ? computeGeometry(pending, Math.max(0, host.clientWidth), live.current.gap)
      : live.current.originGeometry
    const rect = g.tiles.get(id)
    if (!rect) return
    const downBox = host.getBoundingClientRect()
    // The grab offset is frozen at the down event — recomputing it per move would
    // cancel the pointer delta and pin the lifted block to its origin.
    const grab = {
      x: e.clientX - downBox.left - rect.x,
      y: e.clientY - downBox.top - rect.y
    }
    // Scroll compensation reads the REAL scroll ancestor's delta (the host never
    // scrolls itself) — cheap per move, no forced layout, and it also folds our
    // own autoscroll back into the pointer math. A mid-gesture WIDTH change stays
    // deliberately frozen (the origin-snapshot semantics; rare, self-corrects on
    // the next gesture).
    const scroller = findScroller(host)
    const scroll0 = { x: scroller?.scrollLeft ?? 0, y: scroller?.scrollTop ?? 0 }
    let latest: SurfaceLayout = origin
    let target: DropTarget = null
    let moved = false

    startPointerDrag(e, {
      onMove: (_dx, _dy, ev) => {
        moved = true
        if (scroller) autoScroll(scroller, ev.clientX, ev.clientY)
        const dsx = (scroller?.scrollLeft ?? 0) - scroll0.x
        const dsy = (scroller?.scrollTop ?? 0) - scroll0.y
        const px = ev.clientX - downBox.left + dsx
        const py = ev.clientY - downBox.top + dsy
        setTileDrag({ id, lift: { x: px - grab.x, y: py - grab.y, w: rect.w, h: rect.h } })
        target = hitTest(g, origin, id, px, py, zone, target)
        latest = applyTarget(origin, id, target)
        setDraft(latest === origin ? null : latest)
      },
      onEnd: (commitDrag) => {
        const decided = commitDrag && target && latest !== origin ? latest : null
        // An unarmed click never moved anything — a settle here would only flash
        // the lifted styling and stall a pointless commit pass on the timer.
        if (!moved && !decided) return
        // Settle into the decided slot (the final layout's rect), or back home.
        const finalGeometry = decided
          ? computeGeometry(decided, Math.max(0, host.clientWidth), live.current.gap)
          : g
        const to = finalGeometry.tiles.get(id) ?? rect
        setTileDrag(null)
        if (!decided) setDraft(null)
        const s: Settle = { id, to, next: decided }
        settleRef.current = s
        setSettle(s)
      }
    })
  }, [])

  const dragId = tileDrag?.id ?? settle?.id ?? null
  const interacting = resizingId !== null || tracking

  // A background right-click resolves to a semantic create target: the ragged
  // wedge under the tile above the point (fill flush to the row bottom), or a
  // plain append when nothing sits above. Tiles swallow their own right-clicks.
  const onSurfaceContextMenu = (e: React.MouseEvent): void => {
    if (!onBackdrop || e.target !== e.currentTarget) return
    e.preventDefault()
    const host = hostRef.current
    if (!host) return
    const box = host.getBoundingClientRect()
    const px = e.clientX - box.left
    const py = e.clientY - box.top
    const g = live.current.originGeometry
    let above: { id: string; bottom: number; band: number } | null = null
    for (const [id, r] of g.tiles) {
      const bottom = r.y + r.h
      if (px >= r.x && px <= r.x + r.w && py >= bottom && (!above || bottom > above.bottom)) {
        const at = findTile(live.current.layout, id)
        if (at) above = { id, bottom, band: at.band }
      }
    }
    if (!above) {
      onBackdrop({ kind: 'append' }, e)
      return
    }
    // The band's bottom = its seam centerline minus half the gap.
    const seam = g.bandEdges[above.band]
    const bandBottom = seam ? seam.y - live.current.gap / 2 : g.totalHeight
    const fillPx = bandBottom - above.bottom - live.current.gap
    if (fillPx < live.current.minTilePx || py > bandBottom) onBackdrop({ kind: 'append' }, e)
    else onBackdrop({ kind: 'wedge', above: above.id, fillPx }, e)
  }

  return (
    <div
      ref={hostRef}
      className={`spm-surface${interacting ? ' is-interacting' : ''}`}
      style={{ height: geometry.totalHeight + bottomPadPx }}
      onContextMenu={onSurfaceContextMenu}
    >
      {/* Tiles render in STABLE id order, never tree order — a mid-drag preview
          reorders the tree, and letting React move the keyed DOM nodes to match
          silently releases pointer capture (the pointerup never lands → zombie
          gesture, stuck floating tile). Position is absolute; DOM order is moot. */}
      {[...geometry.tiles.entries()]
        .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
        .map(([id, rect]) => {
        const lifted = tileDrag?.id === id
        const settling = settle?.id === id
        const phase: TilePhase = lifted
          ? 'lifted'
          : settling
            ? 'settling'
            : dragId !== null
              ? 'reflow'
              : 'idle'
        const shownRect = lifted
          ? (tileDrag as TileDrag).lift
          : settling
            ? (settle as Settle).to
            : rect
        return (
          <TileShell
            key={id}
            id={id}
            rect={shownRect}
            phase={phase}
            feel={feel}
            resizing={resizingId === id}
            extraClass={tileClassName?.(id)}
            renderTile={renderTile}
            onHandleDown={onHandleDown}
            onHandleMenu={onHandleMenu}
            onEdgeDown={onEdgeDown}
            onSettled={finishSettle}
          />
        )
      })}

      {/* The placement preview — the area the lifted block will occupy, washed in
          the accent tint. Reads off the draft geometry, so it IS the future slot. */}
      {tileDrag &&
        draft &&
        (() => {
          const slot = geometry.tiles.get(tileDrag.id)
          return slot ? (
            <div
              className="spm-placement"
              style={{
                transform: `translate(${slot.x}px, ${slot.y}px)`,
                width: slot.w,
                height: slot.h
              }}
            />
          ) : null
        })()}
    </div>
  )
}

function applyTarget(origin: SurfaceLayout, id: string, target: DropTarget): SurfaceLayout {
  if (!target) return origin
  if (target.kind === 'band') return moveTileToBand(origin, id, target.index)
  return moveTile(origin, id, target.id, target.edge)
}
