import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { DividerRef, Edge, SurfaceLayout } from './core/model'
import { moveTile, moveTileToBand, resizeBand, resizeDivider } from './core/ops'
import { computeGeometry, type Rect } from './core/rects'
import { startPointerDrag } from './sensors/pointerDrag'
import './surfacepm.css'

// The SurfacePM surface: renders a layout tree as absolutely-positioned tiles,
// dividers as shared-edge splitters, band bottoms as page-flow resizers, and a
// tile drag that previews the real post-move tessellation live. Every gesture
// works snapshot → preview → commit/abort: the drag origin's layout is frozen,
// each move recomputes the preview from it (never from the previous preview),
// Esc restores it. Controlled: `layout` in, `onLayoutChange` out on commit.

export interface SurfaceViewProps {
  layout: SurfaceLayout
  onLayoutChange: (layout: SurfaceLayout) => void
  renderTile: (id: string, rect: Rect) => React.ReactNode
  gap?: number
  minTilePx?: number
  minBandPx?: number
  /** Bottom strip height for "drop here as a new band" targeting. */
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
  const [activeDivider, setActiveDivider] = useState<DividerRef | null>(null)

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
  // Hit-testing during a tile drag runs against the frozen origin's geometry,
  // not the previewed one — otherwise the preview shifting under the pointer
  // retargets itself (the oscillation class the RGL teardown pinned).
  const originGeometry = useMemo(
    () => computeGeometry(layout, Math.max(0, width), gap),
    [layout, width, gap]
  )

  const commit = useCallback(
    (next: SurfaceLayout | null) => {
      setDraft(null)
      setActiveDivider(null)
      if (next && next !== layout) onLayoutChange(next)
    },
    [layout, onLayoutChange]
  )

  const onDividerDown = (ref: DividerRef, extentPx: number) => (e: React.PointerEvent) => {
    if (e.button !== 0) return
    e.preventDefault()
    const origin = layout
    const horizontal = geometry.dividers.find((d) => sameDivider(d.ref, ref))?.dir === 'row'
    setActiveDivider(ref)
    let latest: SurfaceLayout = origin
    startPointerDrag(e, {
      threshold: 0,
      onMove: (dx, dy) => {
        latest = resizeDivider(origin, ref, horizontal ? dx : dy, extentPx, minTilePx)
        setDraft(latest)
      },
      onEnd: (commitDrag) => commit(commitDrag ? latest : null)
    })
  }

  const onBandEdgeDown = (band: number) => (e: React.PointerEvent) => {
    if (e.button !== 0) return
    e.preventDefault()
    const origin = layout
    let latest: SurfaceLayout = origin
    startPointerDrag(e, {
      threshold: 0,
      onMove: (_dx, dy) => {
        latest = resizeBand(origin, band, dy, minBandPx)
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

  return (
    <div
      ref={hostRef}
      className="spm-surface"
      style={{ height: geometry.totalHeight + bandDropPx }}
    >
      {[...geometry.tiles.entries()].map(([id, rect]) => (
        <div
          key={id}
          className={cxTile(id, tileDrag, dropTarget)}
          style={{
            transform: `translate(${rect.x}px, ${rect.y}px)`,
            width: rect.w,
            height: rect.h
          }}
        >
          <div className="spm-handle" onPointerDown={onHandleDown(id)} />
          <div className="spm-tile-body">{renderTile(id, rect)}</div>
        </div>
      ))}

      {geometry.dividers.map((d) => (
        <div
          key={`d-${d.ref.band}-${d.ref.path.join('.')}-${d.ref.index}`}
          className={`spm-divider ${d.dir === 'row' ? 'is-vertical' : 'is-horizontal'} ${
            activeDivider && sameDivider(activeDivider, d.ref) ? 'is-active' : ''
          }`}
          style={hitZone(d, gap)}
          onPointerDown={onDividerDown(d.ref, d.extentPx)}
        />
      ))}

      {geometry.bandEdges.map((edge) => (
        <div
          key={`b-${edge.band}`}
          className="spm-band-edge"
          style={{ transform: `translate(0px, ${edge.y - 4}px)`, width: '100%', height: 9 }}
          onPointerDown={onBandEdgeDown(edge.band)}
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

function sameDivider(a: DividerRef, b: DividerRef): boolean {
  return a.band === b.band && a.index === b.index && a.path.join('.') === b.path.join('.')
}

function cxTile(id: string, drag: TileDrag | null, target: DropTarget): string {
  const dragging = drag?.id === id
  const targeted = target?.kind === 'tile' && target.id === id
  return `spm-tile${dragging ? ' is-dragging' : ''}${targeted ? ` is-target edge-${target.edge}` : ''}`
}

/** Widen a divider's visual gap into a comfortable grab zone. */
function hitZone(d: { x: number; y: number; w: number; h: number; dir: string }, gap: number) {
  const pad = Math.max(0, (10 - gap) / 2)
  return d.dir === 'row'
    ? { transform: `translate(${d.x - pad}px, ${d.y}px)`, width: d.w + pad * 2, height: d.h }
    : { transform: `translate(${d.x}px, ${d.y - pad}px)`, width: d.w, height: d.h + pad * 2 }
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
    // Nearest edge by normalized distance — the classic quadrant carve.
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

function applyTarget(
  origin: SurfaceLayout,
  id: string,
  target: DropTarget
): SurfaceLayout {
  if (!target) return origin
  if (target.kind === 'band') return moveTileToBand(origin, id, target.index, 160)
  return moveTile(origin, id, target.id, target.edge)
}
