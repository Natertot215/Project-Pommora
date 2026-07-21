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
import { usePointerGesture } from '@renderer/design-system/interactions/gesture'
import { DROP_LINE_INSET, suppressNextClick } from '@renderer/design-system/interactions/shared'
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
  // Set at ACTIVATION (a tap never sets it) — the id the hit-test + drop classification run against.
  const dragId = useRef<string | null>(null)
  const beginGesture = usePointerGesture()

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

  const reset = (): void => {
    dragId.current = null
    live.current = null
    snapshot.current = null
    snapshotDirty.current = false
    setDrag(IDLE)
  }

  // Re-snapshot lazily (a scroll dirties it) then hit-test the bands at the last point. Shared by
  // pointer move and the auto-scroll re-resolve, so a held-still drag keeps tracking as bands scroll.
  const resolveSlot = (): void => {
    const id = dragId.current
    if (!id) return
    if (snapshotDirty.current || !snapshot.current) {
      snapshot.current = takeSnapshot()
      snapshotDirty.current = false
    }
    const snap = snapshot.current
    if (!snap) return
    const slot = bandSlot(snap.index, lastPoint.current.y, id, snap.boxBottom)
    live.current = slot
    setDrag({
      id,
      ghostX: lastPoint.current.x + 12,
      ghostY: lastPoint.current.y + 8,
      slot,
      lineTop: slot ? slot.lineY - snap.boxTop : 0,
    })
  }

  const begin = (id: string, e: ReactPointerEvent): void => {
    if ((e.target as HTMLElement).closest?.('input, textarea, [contenteditable="true"]')) return
    const el = els.current.get(id)
    if (!el) return
    // The shared gesture: window listeners drive it (the glyph is small, the first move usually
    // leaves it); capture defers to activation so a sub-threshold press stays inert.
    beginGesture({
      el,
      event: e,
      onActivate: () => {
        dragId.current = id
        ghostLabel.current = labelForRef.current(id)
        window.addEventListener('scroll', markSnapshotDirty, { capture: true, passive: true })
        // Auto-scroll the vertical scroller. findScroller('y') skips the x-only '.table-view' to
        // reach '.detail-scroll'; onScrolled re-resolves a held-still drag as the bands scroll.
        const sc = findScroller(el, 'y')
        if (sc) {
          stopScroll.current = startAutoScroll({
            getPoint: () => lastPoint.current,
            scroller: sc,
            dragEl: el,
            axis: 'y',
            onScrolled: resolveSlot,
          })
        }
        return true
      },
      onDragMove: (ev) => {
        lastPoint.current = { x: ev.clientX, y: ev.clientY }
        resolveSlot()
      },
      onDrop: () => {
        const slot = live.current
        const dragged = snapshot.current?.index.byId.get(id)
        if (slot && dragged) {
          const drop = onDropRef.current
          if (slot.nestInto)
            drop(id, { kind: 'reparent', targetParentId: slot.nestInto, beforeId: null })
          else if (slot.impliedParentId === dragged.parentId)
            drop(id, { kind: 'reorder', beforeId: slot.beforeId })
          else
            drop(id, {
              kind: 'reparent',
              targetParentId: slot.impliedParentId,
              beforeId: slot.beforeId,
            })
          suppressNextClick() // the drop's release must not also fire the glyph's toggle
        }
        reset()
      },
      onAbort: reset,
      teardown: () => {
        stopScroll.current?.()
        stopScroll.current = null
        window.removeEventListener('scroll', markSnapshotDirty, { capture: true })
      },
    })
  }

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
