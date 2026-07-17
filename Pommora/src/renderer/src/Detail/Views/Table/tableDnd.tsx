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
import {
  ACTIVATION,
  DROP_LINE_INSET,
  suppressNextClick,
} from '@renderer/design-system/interactions/shared'
import { findScroller, startAutoScroll } from '@renderer/design-system/interactions/autoscroll'

// Table row drag — the sidebar drop-line gesture (B): an accent insertion LINE marks the exact slot,
// the picked-up row mutes in place (--drag-muted), and NO row displaces. Where you drop disambiguates
// (D-8): a slot inside the dragged row's own group reorders it (viewOrders); a slot in another group
// reassigns the grouped property (setProperty). The commits live in TableView and are passed in — this
// file owns only the gesture + hit-testing + the line. The cursor ghost is omitted (B-2).

type Slot = { lineY: number; left: number; width: number; commit: () => void; noop: boolean }
type MeasuredRow = {
  id: string
  top: number
  bottom: number
  mid: number
  left: number
  contentRight: number
  group: string
}
type DragState = { id: string | null; slot: Slot | null }
const IDLE: DragState = { id: null, slot: null }

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
  registerRow: (id: string, el: HTMLElement | null) => void
  begin: (id: string, e: ReactPointerEvent) => void
}
const Ctx = createContext<Value | null>(null)

export function TableRowDnd({
  rows,
  disabled,
  canReorderWithin,
  canReassign,
  reorderTo,
  reassign,
  children,
}: {
  /** The flat visible data-row order + each row's group key. */
  rows: { id: string; groupKey: string }[]
  disabled: boolean
  canReorderWithin: boolean
  canReassign: boolean
  /** Commit a within-group reorder: the new flat order of row ids + the reordered group's key (so the
   *  caller can map a structural group to its on-disk container for the page_order write) + the dragged
   *  row's id (for callers whose commit is (active, over)-shaped). */
  reorderTo: (orderIds: string[], groupKey: string, activeId: string) => void
  /** Commit a cross-group reassign (write the dragged row's grouped property to the target group). */
  reassign: (activeId: string, targetGroupKey: string) => void
  children: ReactNode
}): React.JSX.Element {
  const rowsRef = useRef(rows)
  rowsRef.current = rows
  // The context value memoizes on drag.id, freezing `begin` (and the gesture's whole closure chain)
  // at an old render — so the mutable config rides a per-render ref, the rowsRef/commitBandRef
  // discipline: a drop always commits through the CURRENT props, never a mount-time snapshot.
  const cfg = useRef({ disabled, canReorderWithin, canReassign, reorderTo, reassign })
  cfg.current = { disabled, canReorderWithin, canReassign, reorderTo, reassign }
  const els = useRef(new Map<string, HTMLElement>())
  const content = useRef<HTMLDivElement | null>(null)
  const live = useRef<Slot | null>(null)
  // Cached row geometry for the active drag (measured once at activation, re-measured only on scroll).
  const snapshot = useRef<{ rows: MeasuredRow[]; boxTop: number; boxLeft: number } | null>(null)
  const onDragScroll = useRef<((e: Event) => void) | null>(null)
  const lastPoint = useRef({ x: 0, y: 0 })
  const stopScroll = useRef<(() => void) | null>(null)
  const snapshotDirty = useRef(false)
  const [drag, setDrag] = useState<DragState>(IDLE)
  const gesture = useRef<Gesture>({ kind: 'idle' })

  const registerRow = (id: string, el: HTMLElement | null): void => {
    if (el) els.current.set(id, el)
    else els.current.delete(id)
  }

  // Snapshot every row's geometry ONCE — the drop-line DnD never displaces a row, so a live per-move
  // getBoundingClientRect over every row (a forced reflow × N rows per pointer event) is pure waste. We
  // re-snapshot only when the scroll position shifts the rects (see the scroll listener in begin). The
  // dragged row (excludeId) is left out — it's never a drop target.
  const measure = (excludeId: string): void => {
    const box = content.current
    if (!box) return
    const boxRect = box.getBoundingClientRect()
    const rows: MeasuredRow[] = []
    for (const r of rowsRef.current) {
      if (r.id === excludeId) continue
      const el = els.current.get(r.id)
      if (!el) continue
      const rect = el.getBoundingClientRect()
      // End the line at the content edge (where the columns stop), not the full row — the row spans the
      // trailing 1fr filler too, so rect.right would run the line into the empty gutter past the last column.
      const filler = el.querySelector('.cell-filler')
      const contentRight = filler ? filler.getBoundingClientRect().left : rect.right
      rows.push({
        id: r.id,
        top: rect.top,
        bottom: rect.bottom,
        mid: rect.top + rect.height / 2,
        left: rect.left,
        contentRight,
        group: r.groupKey,
      })
    }
    rows.sort((a, b) => a.top - b.top)
    snapshot.current = { rows, boxTop: boxRect.top, boxLeft: boxRect.left }
  }

  // Hit-test the snapshot → the landing slot. The nearest row + which half the cursor is in fixes the
  // slot; that row's group is the target group (drop above row R or below it, the slot sits in R's group
  // either way).
  const computeSlot = (clientY: number): Slot | null => {
    const g = gesture.current
    const snap = snapshot.current
    if (g.kind === 'idle' || !snap) return null
    const activeGroup = rowsRef.current.find((r) => r.id === g.id)?.groupKey
    if (activeGroup === undefined) return null
    const measured = snap.rows
    if (measured.length === 0) return null

    // nearest row: the last whose top is at/above the cursor, else the first.
    let near = measured[0]
    for (const m of measured) {
      if (clientY >= m.top) near = m
      else break
    }
    const above = clientY < near.mid // drop before `near` vs after it
    const targetGroup = near.group
    const lineY = (above ? near.top : near.bottom) - snap.boxTop
    const left = near.left - snap.boxLeft + DROP_LINE_INSET
    const width = near.contentRight - near.left - DROP_LINE_INSET * 2

    if (targetGroup === activeGroup) {
      if (!cfg.current.canReorderWithin) return null
      // before `near` (above) or before the row after `near` in the flat order (below).
      const order = rowsRef.current.map((x) => x.id)
      const beforeId = above ? near.id : (order[order.indexOf(near.id) + 1] ?? null)
      const without = order.filter((id) => id !== g.id)
      const idx = beforeId ? without.indexOf(beforeId) : without.length
      const next = [...without.slice(0, idx), g.id, ...without.slice(idx)]
      const noop = next.length === order.length && next.every((id, i) => id === order[i])
      return {
        lineY,
        left,
        width,
        noop,
        commit: () => cfg.current.reorderTo(next, activeGroup, g.id),
      }
    }
    if (!cfg.current.canReassign) return null
    return {
      lineY,
      left,
      width,
      noop: false,
      commit: () => cfg.current.reassign(g.id, targetGroup),
    }
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
    if (onDragScroll.current) {
      window.removeEventListener('scroll', onDragScroll.current, { capture: true })
      onDragScroll.current = null
    }
    snapshot.current = null
    try {
      g.el.releasePointerCapture(g.pid)
    } catch {
      // already released
    }
  }
  const reset = (): void => {
    gesture.current = { kind: 'idle' }
    live.current = null
    setDrag(IDLE)
  }

  const begin = (id: string, e: ReactPointerEvent): void => {
    if (cfg.current.disabled || e.button !== 0 || !e.isPrimary || gesture.current.kind !== 'idle')
      return
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
    // Listen on window, not the row: the grip sits out in the gutter (absolutely placed left of the row),
    // so a first move that drifts off the row would never fire a row-bound pointermove — the drag would
    // fail to activate. Capture is still deferred to activation (capturing on pointerdown eats the click,
    // so a tap could never select the row); until then window listeners drive the activation check.
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
      // Snapshot geometry now that the drag is real, then re-snapshot only when a scroll shifts the rects
      // (rows never displace mid-drag, so hit-testing reads the cache — no per-move reflow over every row).
      measure(g.id)
      // A scroll that moves the rows (wheel OR the auto-scroll loop below — its scrollBy fires this same
      // native event) dirties the snapshot and re-resolves the slot from the last point, so a held-still
      // drag near an edge keeps tracking. Dirty-gate + a target guard (skip a scroll that doesn't contain
      // the row content, e.g. an inner cell) so the O(rows) re-measure runs at most once per frame and
      // never on an unrelated scroll — resolveSlot re-measures lazily off the flag.
      const onScroll = (e: Event): void => {
        if (e.target instanceof Element && content.current && !e.target.contains(content.current))
          return
        snapshotDirty.current = true
        resolveSlot(lastPoint.current.y)
      }
      onDragScroll.current = onScroll
      window.addEventListener('scroll', onScroll, { capture: true, passive: true })
      // Auto-scroll the vertical scroller. findScroller('y') is load-bearing: it SKIPS the x-only
      // '.table-view' to reach '.detail-scroll' (the table row's real y-scroller). No onScrolled — the
      // native onScroll above already re-resolves off the module's scrollBy.
      const sc = findScroller(g.el, 'y')
      if (sc) {
        stopScroll.current = startAutoScroll({
          getPoint: () => lastPoint.current,
          scroller: sc,
          dragEl: g.el,
          axis: 'y',
        })
      }
    }
    lastPoint.current = { x: e.clientX, y: e.clientY }
    resolveSlot(e.clientY)
  }

  // Hit-test at a Y → the slot + line. Shared by pointer move and the scroll re-resolve (wheel +
  // auto-scroll). Re-measures lazily, only when a scroll dirtied the snapshot — a pointer move reads
  // the cache (rows don't displace mid-drag), a scroll re-measures once.
  function resolveSlot(clientY: number): void {
    const g = gesture.current
    if (g.kind === 'idle') return
    if (snapshotDirty.current) {
      measure(g.id)
      snapshotDirty.current = false
    }
    const slot = computeSlot(clientY)
    live.current = slot
    setDrag({ id: g.id, slot })
  }
  function onUp(): void {
    detach()
    const g = gesture.current
    if (g.kind !== 'active') {
      reset()
      return // a click, never a drag
    }
    const slot = live.current
    if (slot && !slot.noop) {
      slot.commit()
      suppressNextClick()
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

  // Unmount mid-drag (a watcher re-walk swaps the collection, a view change): pull window listeners +
  // stop the auto-scroll loop so neither dangles for the session. lostpointercapture on the removed node
  // fires no pointerup/blur, so detach is the only guaranteed teardown.
  useEffect(() => () => detach(), []) // eslint-disable-line react-hooks/exhaustive-deps

  const value = useMemo<Value>(() => ({ draggingId: drag.id, registerRow, begin }), [drag.id]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Ctx.Provider value={value}>
      <div ref={content} className="table-dnd">
        {children}
        {drag.slot && (
          <div
            className="table-drop-line"
            aria-hidden
            style={{ top: drag.slot.lineY, left: drag.slot.left, width: drag.slot.width }}
          >
            <span className="table-drop-dot" />
          </div>
        )}
      </div>
    </Ctx.Provider>
  )
}

/** Make a data row draggable + registered for hit-testing: put `ref` on the row, spread `handle` on the
 *  grip. `isDragging` mutes the row in place. */
export function useTableRowDrag(id: string): {
  ref: (el: HTMLElement | null) => void
  handle: { onPointerDown: (e: ReactPointerEvent) => void }
  isDragging: boolean
} {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useTableRowDrag must be used inside <TableRowDnd>')
  return {
    ref: (el) => ctx.registerRow(id, el),
    handle: { onPointerDown: (e) => ctx.begin(id, e) },
    isDragging: ctx.draggingId === id,
  }
}
