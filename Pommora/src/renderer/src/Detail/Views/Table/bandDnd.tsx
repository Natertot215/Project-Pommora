import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from 'react'
import { createPortal } from 'react-dom'
import { text } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import {
  ACTIVATION,
  DROP_LINE_INSET,
  suppressNextClick,
} from '@renderer/design-system/interactions/shared'
import { findScroller, startAutoScroll } from '@renderer/design-system/interactions/autoscroll'
import type { MeasuredRow } from '@renderer/Sidebar/sidebarDndModel'
import { type Band, type BandIndex, type BandSlot, bandSlot, buildBandIndex } from './bandDndModel'

// Band drag (Phase 2) — group headers reorder/reparent via the sidebar's insertion-line gesture.
// The GLYPH is the drag surface (C-6); this file owns only the gesture + the frozen snapshot +
// the line/ghost/nest chrome. The drop hands TableView a CLASSIFIED commit (reorder vs reparent,
// routed by the slot's implied parent vs the dragged band's current parent) — the caller never
// re-derives it.

export type BandDrop =
  | { kind: 'reorder'; beforeId: string | null }
  | { kind: 'reparent'; targetParentId: string | null; beforeId: string | null }

type DragState = {
  id: string | null
  ghostX: number
  ghostY: number
  slot: BandSlot | null
  lineTop: number
}
const IDLE: DragState = { id: null, ghostX: 0, ghostY: 0, slot: null, lineTop: 0 }

type Handlers = {
  move: (e: PointerEvent) => void
  up: () => void
  cancel: () => void
  key: (e: KeyboardEvent) => void
}
type Gesture =
  | { kind: 'idle' }
  | {
      kind: 'pending' | 'active'
      id: string
      el: HTMLElement
      pid: number
      startX: number
      startY: number
      handlers: Handlers
    }

type Value = {
  draggingId: string | null
  nestTargetId: string | null
  registerBand: (id: string, el: HTMLElement | null) => void
  begin: (id: string, e: ReactPointerEvent) => void
}
const Ctx = createContext<Value | null>(null)

export function BandDnd({
  bands,
  labelFor,
  onDrop,
  children,
}: {
  /** The visible band list (flattenBands over the live collapsed set) — snapshot state during a drag. */
  bands: Band[]
  labelFor: (id: string) => string
  onDrop: (draggedId: string, drop: BandDrop) => void
  children: ReactNode
}): React.JSX.Element {
  const bandsRef = useRef(bands)
  bandsRef.current = bands
  // The context memo freezes `begin` (and so the whole listener chain) from an early render — the
  // drop must reach the CALLER'S latest closure, not the one captured at bind time (the sidebar's
  // onCommitRef pattern).
  const onDropRef = useRef(onDrop)
  onDropRef.current = onDrop
  const labelForRef = useRef(labelFor)
  labelForRef.current = labelFor
  // Resolved ONCE at activation — labelFor walks the group tree, and the ghost re-renders per move.
  const ghostLabel = useRef('')
  const els = useRef(new Map<string, HTMLElement>())
  const box = useRef<HTMLDivElement | null>(null)
  const live = useRef<BandSlot | null>(null)
  const [drag, setDrag] = useState<DragState>(IDLE)
  const gesture = useRef<Gesture>({ kind: 'idle' })

  // Frozen at activation (C-2): geometry AND the band list ride one snapshot — a mid-drag tree
  // swap re-renders headers, so both go stale together and re-measure together, lazily.
  type Snapshot = { index: BandIndex; boxTop: number; boxBottom: number }
  const snapshot = useRef<Snapshot | null>(null)
  const snapshotDirty = useRef(false)
  const lastPoint = useRef({ x: 0, y: 0 })
  const stopScroll = useRef<(() => void) | null>(null)
  useEffect(() => {
    snapshotDirty.current = true
  }, [bands])
  const markSnapshotDirty = (): void => {
    snapshotDirty.current = true
  }

  const takeSnapshot = (): Snapshot | null => {
    const el = box.current
    if (!el) return null
    const boxRect = el.getBoundingClientRect()
    const current = bandsRef.current
    const rows: MeasuredRow[] = []
    for (const b of current) {
      const headerEl = els.current.get(b.id)
      if (!headerEl) continue
      const r = headerEl.getBoundingClientRect()
      rows.push({ id: b.id, top: r.top, bottom: r.bottom, mid: r.top + r.height / 2 })
    }
    rows.sort((a, b) => a.top - b.top)
    return { index: buildBandIndex(current, rows), boxTop: boxRect.top, boxBottom: boxRect.bottom }
  }

  const registerBand = (id: string, el: HTMLElement | null): void => {
    if (el) els.current.set(id, el)
    else els.current.delete(id)
  }

  const detach = (): void => {
    stopScroll.current?.()
    stopScroll.current = null
    const g = gesture.current
    if (g.kind === 'idle') return
    window.removeEventListener('pointermove', g.handlers.move)
    window.removeEventListener('pointerup', g.handlers.up)
    window.removeEventListener('pointercancel', g.handlers.cancel)
    window.removeEventListener('keydown', g.handlers.key)
    window.removeEventListener('scroll', markSnapshotDirty, { capture: true })
    try {
      g.el.releasePointerCapture(g.pid)
    } catch {
      // already released
    }
  }
  const reset = (): void => {
    gesture.current = { kind: 'idle' }
    live.current = null
    snapshot.current = null
    snapshotDirty.current = false
    setDrag(IDLE)
  }

  const begin = (id: string, e: ReactPointerEvent): void => {
    if (e.button !== 0 || !e.isPrimary || gesture.current.kind !== 'idle') return
    if ((e.target as HTMLElement).closest?.('input, textarea, [contenteditable="true"]')) return
    const el = els.current.get(id)
    if (!el) return
    const handlers: Handlers = { move: onMove, up: onUp, cancel: onCancel, key: onKey }
    gesture.current = {
      kind: 'pending',
      id,
      el,
      pid: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      handlers,
    }
    // Window listeners drive the whole gesture — the glyph is small, so the first move usually
    // leaves it. Capture defers to activation so a sub-threshold press stays inert (a documented
    // no-op: the glyph has no click action to lose).
    window.addEventListener('pointermove', handlers.move)
    window.addEventListener('pointerup', handlers.up)
    window.addEventListener('pointercancel', handlers.cancel)
    window.addEventListener('keydown', handlers.key)
  }

  function onMove(e: PointerEvent): void {
    const g = gesture.current
    if (g.kind === 'idle') return
    if (g.kind === 'pending') {
      if (Math.hypot(e.clientX - g.startX, e.clientY - g.startY) < ACTIVATION) return
      try {
        g.el.setPointerCapture(g.pid)
      } catch {
        // capture unavailable
      }
      gesture.current = { ...g, kind: 'active' }
      ghostLabel.current = labelForRef.current(g.id)
      window.addEventListener('scroll', markSnapshotDirty, { capture: true, passive: true })
      // Auto-scroll the vertical scroller. findScroller('y') skips the x-only '.table-view' to reach
      // '.detail-scroll' (same B-2 case as the rows). Start at activation; onScrolled re-resolves a
      // held-still drag as the bands scroll.
      const sc = findScroller(g.el, 'y')
      if (sc) {
        stopScroll.current = startAutoScroll({
          getPoint: () => lastPoint.current,
          scroller: sc,
          dragEl: g.el,
          axis: 'y',
          onScrolled: resolveSlot,
        })
      }
    }
    lastPoint.current = { x: e.clientX, y: e.clientY }
    resolveSlot()
  }

  // Re-snapshot lazily (a scroll dirties it) then hit-test the bands at the last point. Shared by
  // pointer move and the auto-scroll re-resolve, so a held-still drag keeps tracking as bands scroll.
  function resolveSlot(): void {
    const g = gesture.current
    if (g.kind !== 'active') return
    if (snapshotDirty.current || !snapshot.current) {
      snapshot.current = takeSnapshot()
      snapshotDirty.current = false
    }
    const snap = snapshot.current
    if (!snap) return
    const slot = bandSlot(snap.index, lastPoint.current.y, g.id, snap.boxBottom)
    live.current = slot
    setDrag({
      id: g.id,
      ghostX: lastPoint.current.x + 12,
      ghostY: lastPoint.current.y + 8,
      slot,
      lineTop: slot ? slot.lineY - snap.boxTop : 0,
    })
  }
  function onUp(): void {
    detach()
    const g = gesture.current
    if (g.kind !== 'active') {
      reset()
      return // a press, never a drag
    }
    const slot = live.current
    const dragged = snapshot.current?.index.byId.get(g.id)
    if (slot && dragged) {
      const drop = onDropRef.current
      if (slot.nestInto)
        drop(g.id, { kind: 'reparent', targetParentId: slot.nestInto, beforeId: null })
      else if (slot.impliedParentId === dragged.parentId)
        drop(g.id, { kind: 'reorder', beforeId: slot.beforeId })
      else
        drop(g.id, {
          kind: 'reparent',
          targetParentId: slot.impliedParentId,
          beforeId: slot.beforeId,
        })
      suppressNextClick() // the drop's release must not also fire the glyph's toggle
    }
    reset()
  }
  function onCancel(): void {
    detach()
    reset()
  }
  function onKey(e: KeyboardEvent): void {
    if (e.key === 'Escape') onCancel()
  }

  useEffect(() => () => detach(), [])

  const value = useMemo<Value>(
    () => ({ draggingId: drag.id, nestTargetId: drag.slot?.nestInto ?? null, registerBand, begin }),
    [drag.id, drag.slot?.nestInto], // eslint-disable-line react-hooks/exhaustive-deps
  )

  return (
    <Ctx.Provider value={value}>
      <div ref={box} className="band-dnd">
        {children}
        {drag.slot && !drag.slot.nestInto && (
          <div
            className="table-drop-line"
            aria-hidden
            style={{ top: drag.lineTop, left: DROP_LINE_INSET, right: DROP_LINE_INSET }}
          >
            <span className="table-drop-dot" />
          </div>
        )}
      </div>
      {drag.id &&
        createPortal(
          <div
            aria-hidden
            className={cx('band-drag-ghost', text.body.standard)}
            style={{ top: drag.ghostY, left: drag.ghostX }}
          >
            {ghostLabel.current}
          </div>,
          document.body,
        )}
    </Ctx.Provider>
  )
}

/** Make a group header a band-drag participant: `ref` on the header (the measured row), `handle`
 *  spread on the GLYPH — the only drag surface. `isNestTarget` highlights a hovered nest zone. */
export function useBandDrag(id: string): {
  ref: (el: HTMLElement | null) => void
  handle: { onPointerDown: (e: ReactPointerEvent) => void }
  isDragging: boolean
  isNestTarget: boolean
} {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useBandDrag must be used inside <BandDnd>')
  return {
    ref: (el) => ctx.registerBand(id, el),
    handle: { onPointerDown: (e) => ctx.begin(id, e) },
    isDragging: ctx.draggingId === id,
    isNestTarget: ctx.nestTargetId === id,
  }
}
