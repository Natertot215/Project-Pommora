import {
  createContext,
  useContext,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from 'react'
import {
  beginDragDisclose,
  endDragDisclose,
} from '@renderer/design-system/interactions/dragDisclose'
import { usePointerGesture } from '@renderer/design-system/interactions/gesture'
import { DROP_LINE_INSET, suppressNextClick } from '@renderer/design-system/interactions/shared'
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
  canRelocate = false,
  reorderTo,
  reassign,
  relocate = () => {},
  children,
}: {
  /** The flat visible data-row order + each row's group key. */
  rows: { id: string; groupKey: string }[]
  disabled: boolean
  canReorderWithin: boolean
  canReassign: boolean
  /** True under plain location grouping: the bands ARE folders, so a cross-band drop MOVES the page. */
  canRelocate?: boolean
  /** Commit a within-group reorder: the new flat order of row ids + the reordered group's key (so the
   *  caller can map a structural group to its on-disk container for the page_order write) + the dragged
   *  row's id (for callers whose commit is (active, over)-shaped). */
  reorderTo: (orderIds: string[], groupKey: string, activeId: string) => void
  /** Commit a cross-group reassign (write the dragged row's grouped property to the target group). */
  reassign: (activeId: string, targetGroupKey: string) => void
  /** Commit a cross-folder move: relocate the dragged page into the target location band's Set. */
  relocate?: (activeId: string, targetGroupKey: string) => void
  children: ReactNode
}): React.JSX.Element {
  const rowsRef = useRef(rows)
  rowsRef.current = rows
  // The context value memoizes on drag.id, freezing `begin` (and the gesture's whole closure chain)
  // at an old render — so the mutable config rides a per-render ref, the rowsRef/commitBandRef
  // discipline: a drop always commits through the CURRENT props, never a mount-time snapshot.
  const cfg = useRef({
    disabled,
    canReorderWithin,
    canReassign,
    canRelocate,
    reorderTo,
    reassign,
    relocate,
  })
  cfg.current = {
    disabled,
    canReorderWithin,
    canReassign,
    canRelocate,
    reorderTo,
    reassign,
    relocate,
  }
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
  // Set at ACTIVATION (a tap never sets it) — the id the hit-test + commits run against.
  const dragId = useRef<string | null>(null)
  const beginGesture = usePointerGesture()

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
    const id = dragId.current
    const snap = snapshot.current
    if (!id || !snap) return null
    const activeGroup = rowsRef.current.find((r) => r.id === id)?.groupKey
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
      const without = order.filter((x) => x !== id)
      const idx = beforeId ? without.indexOf(beforeId) : without.length
      const next = [...without.slice(0, idx), id, ...without.slice(idx)]
      const noop = next.length === order.length && next.every((x, i) => x === order[i])
      return {
        lineY,
        left,
        width,
        noop,
        commit: () => cfg.current.reorderTo(next, activeGroup, id),
      }
    }
    // A drop in a DIFFERENT band: under location grouping the bands are folders (move the page);
    // under a reassignable property grouping it rewrites the grouped value; otherwise it's inert.
    if (cfg.current.canRelocate)
      return {
        lineY,
        left,
        width,
        noop: false,
        commit: () => cfg.current.relocate(id, targetGroup),
      }
    if (!cfg.current.canReassign) return null
    return {
      lineY,
      left,
      width,
      noop: false,
      commit: () => cfg.current.reassign(id, targetGroup),
    }
  }

  const reset = (): void => {
    dragId.current = null
    live.current = null
    setDrag(IDLE)
  }

  // Hit-test at a Y → the slot + line. Shared by pointer move and the scroll re-resolve (wheel +
  // auto-scroll). Re-measures lazily, only when a scroll dirtied the snapshot — a pointer move reads
  // the cache (rows don't displace mid-drag), a scroll re-measures once.
  const resolveSlot = (clientY: number): void => {
    const id = dragId.current
    if (!id) return
    if (snapshotDirty.current) {
      measure(id)
      snapshotDirty.current = false
    }
    const slot = computeSlot(clientY)
    live.current = slot
    setDrag({ id, slot })
  }

  const begin = (id: string, e: ReactPointerEvent): void => {
    if (cfg.current.disabled) return
    const el = els.current.get(id)
    if (!el) return
    // The shared gesture listens on window, not the row: the grip sits out in the gutter, so a
    // first move drifting off the row must still activate. Capture defers to activation (a tap
    // keeps its row-select click).
    const started = beginGesture({
      el,
      event: e,
      onActivate: () => {
        dragId.current = id
        // Snapshot geometry now that the drag is real, then re-snapshot only when a scroll shifts
        // the rects (rows never displace mid-drag — hit-testing reads the cache, no per-move reflow).
        measure(id)
        // A scroll that moves the rows (wheel OR the auto-scroll loop below — its scrollBy fires
        // this same native event) dirties the snapshot and re-resolves from the last point, so a
        // held-still drag near an edge keeps tracking. Target-guarded so an unrelated inner scroll
        // never costs the O(rows) re-measure.
        const onScroll = (ev: Event): void => {
          if (
            ev.target instanceof Element &&
            content.current &&
            !ev.target.contains(content.current)
          )
            return
          snapshotDirty.current = true
          resolveSlot(lastPoint.current.y)
        }
        onDragScroll.current = onScroll
        window.addEventListener('scroll', onScroll, { capture: true, passive: true })
        // Auto-scroll the vertical scroller. findScroller('y') is load-bearing: it SKIPS the x-only
        // '.table-view' to reach '.detail-scroll'. No onScrolled — the native onScroll above already
        // re-resolves off the module's scrollBy.
        const sc = findScroller(el, 'y')
        if (sc) {
          stopScroll.current = startAutoScroll({
            getPoint: () => lastPoint.current,
            scroller: sc,
            dragEl: el,
            axis: 'y',
          })
        }
        return true
      },
      onDragMove: (ev) => {
        lastPoint.current = { x: ev.clientX, y: ev.clientY }
        resolveSlot(ev.clientY)
      },
      onDrop: () => {
        const slot = live.current
        if (slot && !slot.noop) {
          slot.commit()
          suppressNextClick()
        }
        reset()
      },
      onAbort: reset,
      teardown: () => {
        endDragDisclose()
        stopScroll.current?.()
        stopScroll.current = null
        if (onDragScroll.current) {
          window.removeEventListener('scroll', onDragScroll.current, { capture: true })
          onDragScroll.current = null
        }
        snapshot.current = null
      },
    })
    if (started) {
      beginDragDisclose(() => {
        if (dragId.current) measure(dragId.current)
      })
    }
  }

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
