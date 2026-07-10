import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { autoScroll, findScroller } from '@renderer/design-system/interactions/autoscroll'
import type { Edge, SurfaceLayout } from './core/model'
import { resolveEdge } from './core/edges'
import { hitTest, type DropTarget } from './core/hitTest'
import { moveTile, moveTileToBand, resizeBand, resizeDivider } from './core/ops'
import { computeGeometry, type Rect, type SurfaceGeometry } from './core/rects'
import { startPointerDrag } from './sensors/pointerDrag'
import './surfacepm.css'

// The SurfacePM surface: a layout tree rendered as absolutely-positioned blocks.
// Resizing lives on each block's own edges and corners (window-style — never bars
// in the gaps): an edge drag moves the shared boundary it resolves to (core/edges),
// a corner drives both axes at once, and the grabbed block's border carries the
// accent highlight. Moving is the border handle; drops preview the real post-move
// tessellation. Every gesture is snapshot → preview → commit/abort: recomputed from
// the frozen drag-origin layout each move, hit-tested against the origin geometry,
// Esc restores. Gesture handlers are identity-stable (tiles memoize on them) and
// read every live value through a per-render ref at gesture start.

export interface SurfaceViewProps {
  layout: SurfaceLayout
  onLayoutChange: (layout: SurfaceLayout) => void
  /** MUST be identity-stable (useCallback) — tiles memoize on it. */
  renderTile: (id: string, rect: Rect) => React.ReactNode
  gap?: number
  minTilePx?: number
  minBandPx?: number
  /** Band-targeting zone radius (above-first / between-band seams) — a live-tuning knob. */
  bandZonePx?: number
  /** Extra empty room below the last band; dropping there appends a new band. */
  bottomPadPx?: number
}

interface TileDrag {
  id: string
  pointer: { x: number; y: number }
  offset: { x: number; y: number }
  size: { w: number; h: number }
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
  commit: (next: SurfaceLayout | null) => void
  bandZonePx: number
  minTilePx: number
  minBandPx: number
}

const TileShell = memo(
  function TileShell({
    id,
    rect,
    dragging,
    resizing,
    targetEdge,
    renderTile,
    onHandleDown,
    onEdgeDown
  }: {
    id: string
    rect: Rect
    dragging: boolean
    resizing: boolean
    targetEdge: Edge | null
    renderTile: (id: string, rect: Rect) => React.ReactNode
    onHandleDown: (id: string, e: React.PointerEvent) => void
    onEdgeDown: (id: string, edges: Edge[], e: React.PointerEvent) => void
  }) {
    return (
      <div
        className={`spm-tile${dragging ? ' is-dragging' : ''}${resizing ? ' is-resizing' : ''}${
          targetEdge ? ` is-target edge-${targetEdge}` : ''
        }`}
        style={{
          transform: `translate(${rect.x}px, ${rect.y}px)`,
          width: rect.w,
          height: rect.h
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
    a.dragging === b.dragging &&
    a.resizing === b.resizing &&
    a.targetEdge === b.targetEdge &&
    a.renderTile === b.renderTile &&
    a.onHandleDown === b.onHandleDown &&
    a.onEdgeDown === b.onEdgeDown &&
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
  bottomPadPx = 28
}: SurfaceViewProps): React.JSX.Element {
  const hostRef = useRef<HTMLDivElement | null>(null)
  const [width, setWidth] = useState(0)
  const [draft, setDraft] = useState<SurfaceLayout | null>(null)
  const [tileDrag, setTileDrag] = useState<TileDrag | null>(null)
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

  const commit = useCallback(
    (next: SurfaceLayout | null) => {
      setDraft(null)
      setResizingId(null)
      if (next && next !== layout) onLayoutChange(next)
    },
    [layout, onLayoutChange]
  )

  // Every live value a gesture reads, refreshed each render — the handlers stay
  // identity-stable while never seeing a stale layout, geometry, or knob.
  const live = useRef<LiveState>({
    layout,
    originGeometry,
    commit,
    bandZonePx,
    minTilePx,
    minBandPx
  })
  live.current = { layout, originGeometry, commit, bandZonePx, minTilePx, minBandPx }

  const onEdgeDown = useCallback((id: string, edges: Edge[], e: React.PointerEvent) => {
    if (e.button !== 0) return
    e.preventDefault()
    e.stopPropagation()
    const { layout: origin, originGeometry: g, commit: end, minTilePx: minT, minBandPx: minB } =
      live.current
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
      onEnd: (commitDrag) => end(commitDrag ? latest : null)
    })
  }, [])

  const onHandleDown = useCallback((id: string, e: React.PointerEvent) => {
    if (e.button !== 0) return
    e.preventDefault()
    e.stopPropagation()
    const { layout: origin, originGeometry: g, commit: end, bandZonePx: zone } = live.current
    const host = hostRef.current
    const rect = g.tiles.get(id)
    if (!host || !rect) return
    const downBox = host.getBoundingClientRect()
    // The grab offset is frozen at the down event — recomputing it per move would
    // cancel the pointer delta and pin the ghost to the tile's origin.
    const grab = {
      x: e.clientX - downBox.left - rect.x,
      y: e.clientY - downBox.top + host.scrollTop - rect.y
    }
    const scroller = findScroller(host)
    let latest: SurfaceLayout = origin
    let target: DropTarget = null

    startPointerDrag(e, {
      onMove: (_dx, _dy, ev) => {
        if (scroller) autoScroll(scroller, ev.clientX, ev.clientY)
        // The host box is re-read per move — an ancestor scroll (incl. our own
        // autoscroll) or a window resize mid-drag shifts it.
        const hostBox = host.getBoundingClientRect()
        const px = ev.clientX - hostBox.left
        const py = ev.clientY - hostBox.top + host.scrollTop
        setTileDrag({
          id,
          pointer: { x: px, y: py },
          offset: grab,
          size: { w: rect.w, h: rect.h }
        })
        target = hitTest(g, origin, id, px, py, zone, target)
        setDropTarget(target)
        latest = applyTarget(origin, id, target)
        setDraft(latest === origin ? null : latest)
      },
      onEnd: (commitDrag) => {
        setTileDrag(null)
        setDropTarget(null)
        end(commitDrag && target ? latest : null)
      }
    })
  }, [])

  const dragRect = tileDrag ? originGeometry.tiles.get(tileDrag.id) : undefined
  const interacting = tileDrag !== null || resizingId !== null

  return (
    <div
      ref={hostRef}
      className={`spm-surface${interacting ? ' is-interacting' : ''}`}
      style={{ height: geometry.totalHeight + bottomPadPx }}
    >
      {[...geometry.tiles.entries()].map(([id, rect]) => (
        <TileShell
          key={id}
          id={id}
          rect={rect}
          dragging={tileDrag?.id === id}
          resizing={resizingId === id}
          targetEdge={dropTarget?.kind === 'tile' && dropTarget.id === id ? dropTarget.edge : null}
          renderTile={renderTile}
          onHandleDown={onHandleDown}
          onEdgeDown={onEdgeDown}
        />
      ))}

      {tileDrag && dragRect && (
        <div
          className="spm-ghost"
          style={{
            transform: `translate(${tileDrag.pointer.x - tileDrag.offset.x}px, ${
              tileDrag.pointer.y - tileDrag.offset.y
            }px)`,
            width: tileDrag.size.w,
            height: tileDrag.size.h
          }}
        />
      )}
    </div>
  )
}

function applyTarget(origin: SurfaceLayout, id: string, target: DropTarget): SurfaceLayout {
  if (!target) return origin
  if (target.kind === 'band') return moveTileToBand(origin, id, target.index, 160)
  return moveTile(origin, id, target.id, target.edge)
}
