import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type ReactNode
} from 'react'
import { createPortal } from 'react-dom'
import { text } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import { ACTIVATION, DROP_LINE_INSET, suppressNextClick } from '@renderer/design-system/interactions/shared'
import { findScroller, startAutoScroll } from '@renderer/design-system/interactions/autoscroll'
import type { MeasuredRow } from '@renderer/Sidebar/sidebarDndModel'
import { type PaneDrop, type PaneRow, type PaneSlot, type Region, paneSlot } from './paneDndModel'
import * as s from './settingsPane.css'

// The Properties pane's two-region drag (the bandDnd gesture skeleton, the paneSlot model).
// WHOLE rows are the drag surface; the two [data-group] wrappers are the region rects the
// classification runs on (E-4). Esc aborts with a capture-phase swallow so the Toolbar's
// useDismiss never closes the dropdown mid-drag; the capped slot auto-scrolls at the edges,
// and any scroll dirties the frozen snapshot.

type DragState = { id: string | null; ghostX: number; ghostY: number; slot: PaneSlot | null; lineTop: number }
const IDLE: DragState = { id: null, ghostX: 0, ghostY: 0, slot: null, lineTop: 0 }

type Handlers = { move: (e: PointerEvent) => void; up: () => void; cancel: () => void; key: (e: KeyboardEvent) => void }
type Gesture =
  | { kind: 'idle' }
  | { kind: 'pending' | 'active'; id: string; el: HTMLElement; pid: number; startX: number; startY: number; handlers: Handlers }

type Value = {
  draggingId: string | null
  allHighlighted: boolean
  registerRow: (id: string, el: HTMLElement | null) => void
  registerRegion: (group: PaneRow['group'], el: HTMLElement | null) => void
  begin: (id: string, e: ReactPointerEvent) => void
}
const Ctx = createContext<Value | null>(null)

export function PaneDnd({
  rows,
  labelFor,
  onDrop,
  slot = paneSlot,
  children
}: {
  /** Every draggable property row (both groups) — snapshot state during a drag. */
  rows: PaneRow[]
  labelFor: (id: string) => string
  onDrop: (drop: PaneDrop) => void
  /** The region/slot semantics — defaults to the Properties pane's; the Visibility pane injects
   *  its own (hidden region inert, drag-in unhides). */
  slot?: typeof paneSlot
  children: ReactNode
}): React.JSX.Element {
  const rowsRef = useRef(rows)
  rowsRef.current = rows
  // The context memo freezes `begin` from an early render — the drop must reach the CALLER'S
  // latest closure (the onCommitRef pattern).
  const onDropRef = useRef(onDrop)
  onDropRef.current = onDrop
  const labelForRef = useRef(labelFor)
  labelForRef.current = labelFor
  const ghostLabel = useRef('')
  const els = useRef(new Map<string, HTMLElement>())
  const regionEls = useRef<{ assigned: HTMLElement | null; all: HTMLElement | null }>({ assigned: null, all: null })
  const box = useRef<HTMLDivElement | null>(null)
  const scroller = useRef<HTMLElement | null>(null)
  const lastPoint = useRef({ x: 0, y: 0 })
  const stopScroll = useRef<(() => void) | null>(null)
  const live = useRef<PaneSlot | null>(null)
  const [drag, setDrag] = useState<DragState>(IDLE)
  const gesture = useRef<Gesture>({ kind: 'idle' })

  // Frozen at activation: row geometry, the row set, and the region rects ride one snapshot;
  // scroll/content changes dirty it and the next move re-measures (E-4).
  type Snapshot = { rows: MeasuredRow[]; byId: Map<string, PaneRow>; regions: { assigned: Region; all: Region }; boxTop: number }
  const snapshot = useRef<Snapshot | null>(null)
  const snapshotDirty = useRef(false)
  useEffect(() => {
    snapshotDirty.current = true
  }, [rows])
  const markSnapshotDirty = (): void => {
    snapshotDirty.current = true
  }

  const takeSnapshot = (): Snapshot | null => {
    const boxEl = box.current
    const assignedEl = regionEls.current.assigned
    const allEl = regionEls.current.all
    if (!boxEl || !assignedEl || !allEl) return null
    const byId = new Map(rowsRef.current.map((r) => [r.id, r]))
    const measured: MeasuredRow[] = []
    for (const row of rowsRef.current) {
      const el = els.current.get(row.id)
      if (!el) continue
      const r = el.getBoundingClientRect()
      measured.push({ id: row.id, top: r.top, bottom: r.bottom, mid: r.top + r.height / 2 })
    }
    measured.sort((a, b) => a.top - b.top)
    const boxRect = boxEl.getBoundingClientRect()
    const assignedRect = assignedEl.getBoundingClientRect()
    const allRect = allEl.getBoundingClientRect()
    // Regions own their FIELD, not just their rendered rows (Nathan's call): assigned runs down
    // to the All Properties heading, and the all region runs to the pane's bottom edge — the
    // empty space around short lists is a legal drop zone, never a dead no-op.
    return {
      rows: measured,
      byId,
      regions: {
        assigned: { top: assignedRect.top, bottom: allRect.top },
        all: { top: allRect.top, bottom: Math.max(allRect.bottom, boxRect.bottom) }
      },
      boxTop: boxRect.top
    }
  }

  const registerRow = (id: string, el: HTMLElement | null): void => {
    if (el) els.current.set(id, el)
    else els.current.delete(id)
  }
  const registerRegion = (group: PaneRow['group'], el: HTMLElement | null): void => {
    regionEls.current[group] = el
  }

  const detach = (): void => {
    stopScroll.current?.()
    stopScroll.current = null
    const g = gesture.current
    if (g.kind === 'idle') return
    window.removeEventListener('pointermove', g.handlers.move)
    window.removeEventListener('pointerup', g.handlers.up)
    window.removeEventListener('pointercancel', g.handlers.cancel)
    window.removeEventListener('keydown', g.handlers.key, { capture: true })
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
    scroller.current = null
    setDrag(IDLE)
  }

  const begin = (id: string, e: ReactPointerEvent): void => {
    if (e.button !== 0 || !e.isPrimary || gesture.current.kind !== 'idle') return
    // `button` beyond the band guard: a row's +, the twisty, and rename inputs never arm a drag.
    if ((e.target as HTMLElement).closest?.('button, input, textarea, [contenteditable="true"]')) return
    const el = els.current.get(id)
    if (!el) return
    const handlers: Handlers = { move: onMove, up: onUp, cancel: onCancel, key: onKey }
    gesture.current = { kind: 'pending', id, el, pid: e.pointerId, startX: e.clientX, startY: e.clientY, handlers }
    window.addEventListener('pointermove', handlers.move)
    window.addEventListener('pointerup', handlers.up)
    window.addEventListener('pointercancel', handlers.cancel)
    // Capture phase so an active drag's Escape is swallowed before the Toolbar's useDismiss
    // closes the whole dropdown (E-4); a sub-threshold press leaves Escape to the dropdown.
    window.addEventListener('keydown', handlers.key, { capture: true })
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
      scroller.current = findScroller(box.current, 'y')
      window.addEventListener('scroll', markSnapshotDirty, { capture: true, passive: true })
      if (scroller.current) {
        stopScroll.current = startAutoScroll({
          getPoint: () => lastPoint.current,
          scroller: scroller.current,
          dragEl: box.current,
          axis: 'y',
          onScrolled: () => resolveSlot(g.id, lastPoint.current.y)
        })
      }
    }
    lastPoint.current = { x: e.clientX, y: e.clientY }
    resolveSlot(g.id, e.clientY)
  }

  // Snapshot (lazily, when a scroll dirtied it) then hit-test the pane at a Y. Shared by pointer move
  // and the auto-scroll re-resolve, so a held-still drag near an edge keeps updating as content scrolls.
  function resolveSlot(id: string, clientY: number): void {
    if (snapshotDirty.current || !snapshot.current) {
      snapshot.current = takeSnapshot()
      snapshotDirty.current = false
    }
    const snap = snapshot.current
    if (!snap) return
    const liveSlot = slot(snap.rows, snap.byId, snap.regions, clientY, id)
    live.current = liveSlot
    setDrag({
      id,
      ghostX: lastPoint.current.x + 12,
      ghostY: clientY + 8,
      slot: liveSlot,
      lineTop: liveSlot?.lineY != null ? liveSlot.lineY - snap.boxTop : 0
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
    if (slot) {
      onDropRef.current(slot.drop)
      suppressNextClick() // the release must not also open the row's editor
    }
    reset()
  }
  function onCancel(): void {
    detach()
    reset()
  }
  function onKey(e: KeyboardEvent): void {
    if (e.key !== 'Escape') return
    if (gesture.current.kind === 'active') {
      e.stopImmediatePropagation()
      e.preventDefault()
    }
    onCancel()
  }

  useEffect(() => () => detach(), [])

  const value = useMemo<Value>(
    () => ({
      draggingId: drag.id,
      allHighlighted: drag.slot?.highlightAll ?? false,
      registerRow,
      registerRegion,
      begin
    }),
    [drag.id, drag.slot?.highlightAll] // eslint-disable-line react-hooks/exhaustive-deps
  )

  return (
    <Ctx.Provider value={value}>
      <div ref={box} className={s.paneDnd}>
        {children}
        {drag.slot && drag.slot.lineY != null && (
          <div className="table-drop-line" aria-hidden style={{ top: drag.lineTop, left: DROP_LINE_INSET, right: DROP_LINE_INSET }}>
            <span className="table-drop-dot" />
          </div>
        )}
      </div>
      {drag.id &&
        createPortal(
          <div aria-hidden className={cx('band-drag-ghost', text.body.standard)} style={{ top: drag.ghostY, left: drag.ghostX }}>
            {ghostLabel.current}
          </div>,
          document.body
        )}
    </Ctx.Provider>
  )
}

/** One draggable property row — the WHOLE row is the drag surface (buttons inside never arm one). */
export function RowShell({ id, children }: { id: string; children: ReactNode }): React.JSX.Element {
  const { ref, handle, isDragging } = usePaneDrag(id)
  return (
    <div ref={ref} {...handle} data-prop={id} className={cx(isDragging && s.rowDragging)}>
      {children}
    </div>
  )
}

/** Make a property row a pane-drag participant: `ref` + `handle` spread on the row wrapper —
 *  the WHOLE row drags (buttons/inputs inside never arm one). */
export function usePaneDrag(id: string): {
  ref: (el: HTMLElement | null) => void
  handle: { onPointerDown: (e: ReactPointerEvent) => void }
  isDragging: boolean
} {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('usePaneDrag must be used inside <PaneDnd>')
  return {
    ref: (el) => ctx.registerRow(id, el),
    handle: { onPointerDown: (e) => ctx.begin(id, e) },
    isDragging: ctx.draggingId === id
  }
}

/** The two region wrappers register their rects here; the all-group wrapper also reads the
 *  unassign area-highlight (C-4). */
export function usePaneRegions(): {
  assignedRef: (el: HTMLElement | null) => void
  allRef: (el: HTMLElement | null) => void
  allHighlighted: boolean
} {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('usePaneRegions must be used inside <PaneDnd>')
  return {
    assignedRef: (el) => ctx.registerRegion('assigned', el),
    allRef: (el) => ctx.registerRegion('all', el),
    allHighlighted: ctx.allHighlighted
  }
}
