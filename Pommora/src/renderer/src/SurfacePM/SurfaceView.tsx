import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { DividerRef, Edge, SurfaceLayout } from './core/model'
import { resolveEdge } from './core/edges'
import { moveTile, moveTileToBand, resizeBand, resizeDivider } from './core/ops'
import { computeGeometry, type Rect } from './core/rects'
import { startPointerDrag } from './sensors/pointerDrag'
import './surfacepm.css'

// The SurfacePM surface: a layout tree rendered as absolutely-positioned blocks.
// Resizing lives on each block's own edges and corners (window-style — never bars
// in the gaps): an edge drag moves the shared boundary it resolves to (core/edges),
// a corner drives both axes at once, and the grabbed block's border carries the
// accent highlight. Moving is the border handle; drops preview the real post-move
// tessellation. Every gesture is snapshot → preview → commit/abort: recomputed from
// the frozen drag-origin layout each move, hit-tested against the origin geometry,
// Esc restores.

export interface SurfaceViewProps {
  layout: SurfaceLayout
  onLayoutChange: (layout: SurfaceLayout) => void
  renderTile: (id: string, rect: Rect) => React.ReactNode
  gap?: number
  minTilePx?: number
  minBandPx?: number
  /** Bottom strip height for "drop here as a new band" targeting during moves. */
  bandDropPx?: number
}

interface TileDrag {
  id: string
  pointer: { x: number; y: number }
  offset: { x: number; y: number }
  size: { w: number; h: number }
}

type DropTarget =
  | { kind: 'tile'; id: string; edge: Edge }
  | { kind: 'band'; index: number }
  | null

/** The resize affordances a block offers: four edges + four corners. */
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

const refKey = (ref: DividerRef): string => `${ref.band}|${ref.path.join('.')}|${ref.index}`

export function SurfaceView({
  layout,
  onLayoutChange,
  renderTile,
  gap = 8,
  minTilePx = 64,
  minBandPx = 80,
  bandDropPx = 28
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

  const onEdgeDown = (id: string, edges: Edge[]) => (e: React.PointerEvent) => {
    if (e.button !== 0) return
    e.preventDefault()
    e.stopPropagation()
    const origin = layout
    const extents = new Map(originGeometry.dividers.map((d) => [refKey(d.ref), d.extentPx]))
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
          if (boundary?.kind === 'band') return resizeBand(acc, boundary.band, delta, minBandPx)
          if (boundary?.kind === 'divider') {
            const extent = extents.get(refKey(boundary.ref)) ?? 0
            return resizeDivider(acc, boundary.ref, delta, extent, minTilePx)
          }
          return acc
        }, origin)
        setDraft(latest)
      },
      onEnd: (commitDrag) => commit(commitDrag ? latest : null)
    })
  }

  const onHandleDown = (id: string) => (e: React.PointerEvent) => {
    if (e.button !== 0) return
    e.preventDefault()
    e.stopPropagation()
    const origin = layout
    const host = hostRef.current
    const rect = originGeometry.tiles.get(id)
    if (!host || !rect) return
    const hostBox = host.getBoundingClientRect()
    let latest: SurfaceLayout = origin
    let target: DropTarget = null

    startPointerDrag(e, {
      onMove: (_dx, _dy, ev) => {
        const px = ev.clientX - hostBox.left
        const py = ev.clientY - hostBox.top + host.scrollTop
        setTileDrag({
          id,
          pointer: { x: px, y: py },
          offset: { x: ev.clientX - hostBox.left - rect.x, y: ev.clientY - hostBox.top - rect.y },
          size: { w: rect.w, h: rect.h }
        })
        target = hitTest(originGeometry, origin, id, px, py, bandDropPx)
        setDropTarget(target)
        latest = applyTarget(origin, id, target)
        setDraft(latest === origin ? null : latest)
      },
      onEnd: (commitDrag) => {
        setTileDrag(null)
        setDropTarget(null)
        commit(commitDrag && target ? latest : null)
      }
    })
  }

  const dragRect = tileDrag ? originGeometry.tiles.get(tileDrag.id) : undefined
  const interacting = tileDrag !== null || resizingId !== null

  return (
    <div
      ref={hostRef}
      className={`spm-surface${interacting ? ' is-interacting' : ''}`}
      style={{ height: geometry.totalHeight + bandDropPx }}
    >
      {[...geometry.tiles.entries()].map(([id, rect]) => (
        <div
          key={id}
          className={cxTile(id, tileDrag, dropTarget, resizingId)}
          style={{
            transform: `translate(${rect.x}px, ${rect.y}px)`,
            width: rect.w,
            height: rect.h
          }}
        >
          <div className="spm-handle" onPointerDown={onHandleDown(id)} />
          {EDGE_ZONES.map(({ zone, edges }) => (
            <div
              key={zone}
              className={`spm-edge spm-edge-${zone}`}
              onPointerDown={onEdgeDown(id, edges)}
            />
          ))}
          <div className="spm-tile-body">{renderTile(id, rect)}</div>
        </div>
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

function cxTile(
  id: string,
  drag: TileDrag | null,
  target: DropTarget,
  resizingId: string | null
): string {
  const dragging = drag?.id === id
  const targeted = target?.kind === 'tile' && target.id === id
  const resizing = resizingId === id
  return `spm-tile${dragging ? ' is-dragging' : ''}${resizing ? ' is-resizing' : ''}${
    targeted ? ` is-target edge-${target.edge}` : ''
  }`
}

function hitTest(
  geometry: ReturnType<typeof computeGeometry>,
  layout: SurfaceLayout,
  dragId: string,
  px: number,
  py: number,
  bandDropPx: number
): DropTarget {
  if (py > geometry.totalHeight - bandDropPx / 2) return { kind: 'band', index: layout.bands.length }

  for (const [id, r] of geometry.tiles) {
    if (id === dragId) continue
    if (px < r.x || px > r.x + r.w || py < r.y || py > r.y + r.h) continue
    const relX = (px - r.x) / r.w
    const relY = (py - r.y) / r.h
    const dists: Array<[Edge, number]> = [
      ['w', relX],
      ['e', 1 - relX],
      ['n', relY],
      ['s', 1 - relY]
    ]
    dists.sort((a, b) => a[1] - b[1])
    return { kind: 'tile', id, edge: dists[0]?.[0] ?? 'e' }
  }
  return null
}

function applyTarget(origin: SurfaceLayout, id: string, target: DropTarget): SurfaceLayout {
  if (!target) return origin
  if (target.kind === 'band') return moveTileToBand(origin, id, target.index, 160)
  return moveTile(origin, id, target.id, target.edge)
}
