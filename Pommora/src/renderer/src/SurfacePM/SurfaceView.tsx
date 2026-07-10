import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { autoScroll, findScroller } from '@renderer/design-system/interactions/autoscroll'
import { DEFAULT_FEEL, type Feel } from '@renderer/design-system/interactions/feel'
import { SETTLE_FALLBACK } from '@renderer/design-system/interactions/shared'
import type { Edge, SurfaceLayout } from './core/model'
import { resolveEdge } from './core/edges'
import { hitTest, type DropTarget } from './core/hitTest'
import { moveTile, moveTileToBand, resizeBand, resizeDivider } from './core/ops'
import { computeGeometry, type Rect, type SurfaceGeometry } from './core/rects'
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
  minBandPx?: number
  /** Band-targeting zone radius (above-first / between-band seams) — a live-tuning knob. */
  bandZonePx?: number
  /** Extra empty room below the last band; dropping there appends a new band. */
  bottomPadPx?: number
  /** The displacement feel (defaults to the engine's Smooth). */
  feel?: Feel
}

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
  minBandPx: number
  gap: number
  feel: Feel
}

const TileShell = memo(
  function TileShell({
    id,
    rect,
    phase,
    feel,
    targetEdge,
    resizing,
    renderTile,
    onHandleDown,
    onEdgeDown,
    onSettled
  }: {
    id: string
    rect: Rect
    phase: TilePhase
    feel: Feel
    targetEdge: Edge | null
    resizing: boolean
    renderTile: (id: string, rect: Rect) => React.ReactNode
    onHandleDown: (id: string, e: React.PointerEvent) => void
    onEdgeDown: (id: string, edges: Edge[], e: React.PointerEvent) => void
    onSettled: (id: string) => void
  }) {
    const transition =
      phase === 'lifted'
        ? 'none'
        : phase === 'reflow' || phase === 'settling'
          ? `transform ${feel.duration}ms ${feel.easing}, width ${feel.duration}ms ${feel.easing}, height ${feel.duration}ms ${feel.easing}`
          : undefined
    return (
      <div
        className={`spm-tile${phase === 'lifted' || phase === 'settling' ? ' is-lifted' : ''}${
          resizing ? ' is-resizing' : ''
        }${targetEdge ? ` is-target edge-${targetEdge}` : ''}`}
        style={{
          transform: `translate(${rect.x}px, ${rect.y}px)`,
          width: rect.w,
          height: rect.h,
          transition
        }}
        onTransitionEnd={(e) => {
          if (phase === 'settling' && e.propertyName === 'transform') onSettled(id)
        }}
      >
        <div className="spm-handle" onPointerDown={(e) => onHandleDown(id, e)} />
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
    a.targetEdge === b.targetEdge &&
    a.resizing === b.resizing &&
    a.renderTile === b.renderTile &&
    a.onHandleDown === b.onHandleDown &&
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
  minBandPx = 80,
  bandZonePx = 10,
  bottomPadPx = 28,
  feel = DEFAULT_FEEL
}: SurfaceViewProps): React.JSX.Element {
  const hostRef = useRef<HTMLDivElement | null>(null)
  const [width, setWidth] = useState(0)
  const [draft, setDraft] = useState<SurfaceLayout | null>(null)
  const [tileDrag, setTileDrag] = useState<TileDrag | null>(null)
  const [settle, setSettle] = useState<Settle | null>(null)
  const [dropTarget, setDropTarget] = useState<DropTarget>(null)
  const [resizingId, setResizingId] = useState<string | null>(null)

  useEffect(() => {
    const el = hostRef.current
    if (!el) return
    setWidth(el.clientWidth)
    const ro = new ResizeObserver(() => setWidth(el.clientWidth))
    ro.observe(el)
    return () => ro.disconnect()
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
    minBandPx,
    gap,
    feel
  })
  live.current = { layout, originGeometry, bandZonePx, minTilePx, minBandPx, gap, feel }

  const layoutRef = useRef(layout)
  layoutRef.current = layout
  const onLayoutChangeRef = useRef(onLayoutChange)
  onLayoutChangeRef.current = onLayoutChange

  // Decide-then-animate: the settle transition ends (or the engine's fallback
  // timer fires) → the decided layout commits and the gesture state clears.
  const finishSettle = useCallback((id: string) => {
    setSettle((s) => {
      if (!s || s.id !== id) return s
      if (s.next && s.next !== layoutRef.current) onLayoutChangeRef.current(s.next)
      setDraft(null)
      return null
    })
  }, [])

  useEffect(() => {
    if (!settle) return
    const t = setTimeout(() => finishSettle(settle.id), live.current.feel.duration + SETTLE_FALLBACK)
    return () => clearTimeout(t)
  }, [settle, finishSettle])

  const onEdgeDown = useCallback((id: string, edges: Edge[], e: React.PointerEvent) => {
    if (e.button !== 0) return
    e.preventDefault()
    e.stopPropagation()
    const { layout: origin, originGeometry: g, minTilePx: minT, minBandPx: minB } = live.current
    const extents = new Map(g.dividers.map((d) => [refKey(d.ref), d.extentPx]))
    const boundaries = edges
      .map((edge) => ({ edge, boundary: resolveEdge(origin, id, edge) }))
      .filter((b) => b.boundary !== null)
    if (boundaries.length === 0) return

    setResizingId(id)
    let latest: SurfaceLayout = origin
    startPointerDrag(e, {
      threshold: 0,
      onMove: (dx, dy) => {
        latest = boundaries.reduce((acc, { edge, boundary }) => {
          const delta = edge === 'e' || edge === 'w' ? dx : dy
          if (boundary?.kind === 'band') return resizeBand(acc, boundary.band, delta, minB)
          if (boundary?.kind === 'divider') {
            const extent = extents.get(refKey(boundary.ref)) ?? 0
            return resizeDivider(acc, boundary.ref, delta, extent, minT)
          }
          return acc
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
    if (e.button !== 0) return
    e.preventDefault()
    e.stopPropagation()
    const { layout: origin, originGeometry: g, bandZonePx: zone } = live.current
    const host = hostRef.current
    const rect = g.tiles.get(id)
    if (!host || !rect) return
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

    startPointerDrag(e, {
      onMove: (_dx, _dy, ev) => {
        if (scroller) autoScroll(scroller, ev.clientX, ev.clientY)
        const dsx = (scroller?.scrollLeft ?? 0) - scroll0.x
        const dsy = (scroller?.scrollTop ?? 0) - scroll0.y
        const px = ev.clientX - downBox.left + dsx
        const py = ev.clientY - downBox.top + dsy
        setTileDrag({ id, lift: { x: px - grab.x, y: py - grab.y, w: rect.w, h: rect.h } })
        target = hitTest(g, origin, id, px, py, zone, target)
        setDropTarget(target)
        latest = applyTarget(origin, id, target)
        setDraft(latest === origin ? null : latest)
      },
      onEnd: (commitDrag) => {
        const decided = commitDrag && target && latest !== origin ? latest : null
        // Settle into the decided slot (the final layout's rect), or back home.
        const finalGeometry = decided
          ? computeGeometry(decided, Math.max(0, host.clientWidth), live.current.gap)
          : g
        const to = finalGeometry.tiles.get(id) ?? rect
        setTileDrag(null)
        setDropTarget(null)
        if (!decided) setDraft(null)
        setSettle({ id, to, next: decided })
      }
    })
  }, [])

  const dragId = tileDrag?.id ?? settle?.id ?? null
  const interacting = resizingId !== null

  return (
    <div
      ref={hostRef}
      className={`spm-surface${interacting ? ' is-interacting' : ''}`}
      style={{ height: geometry.totalHeight + bottomPadPx }}
    >
      {[...geometry.tiles.entries()].map(([id, rect]) => {
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
            targetEdge={
              dropTarget?.kind === 'tile' && dropTarget.id === id ? dropTarget.edge : null
            }
            renderTile={renderTile}
            onHandleDown={onHandleDown}
            onEdgeDown={onEdgeDown}
            onSettled={finishSettle}
          />
        )
      })}
    </div>
  )
}

function applyTarget(origin: SurfaceLayout, id: string, target: DropTarget): SurfaceLayout {
  if (!target) return origin
  if (target.kind === 'band') return moveTileToBand(origin, id, target.index, 160)
  return moveTile(origin, id, target.id, target.edge)
}
