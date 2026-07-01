import { createContext, useContext, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from 'react'
import { ACTIVATION } from '@renderer/design-system/interactions/shared'

// Table row drag — the sidebar drop-line gesture (B): an accent insertion LINE marks the exact slot,
// the picked-up row mutes in place (--drag-muted), and NO row displaces. Where you drop disambiguates
// (D-8): a slot inside the dragged row's own group reorders it (viewOrders); a slot in another group
// reassigns the grouped property (setProperty). The commits live in TableView and are passed in — this
// file owns only the gesture + hit-testing + the line. The cursor ghost is omitted (B-2).

const LINE_INSET = 2 // px the insertion line is pulled in from the row's left/right edges

type Slot = { lineY: number; left: number; width: number; commit: () => void; noop: boolean }
type DragState = { id: string | null; slot: Slot | null }
const IDLE: DragState = { id: null, slot: null }

type Handlers = { move: (e: PointerEvent) => void; up: () => void; cancel: () => void }
type Gesture =
  | { kind: 'idle' }
  | { kind: 'pending' | 'active'; id: string; el: HTMLElement; pid: number; startX: number; startY: number; handlers: Handlers }

type Value = { draggingId: string | null; registerRow: (id: string, el: HTMLElement | null) => void; begin: (id: string, e: ReactPointerEvent) => void }
const Ctx = createContext<Value | null>(null)

export function TableRowDnd({
  rows,
  disabled,
  canReorderWithin,
  canReassign,
  reorderTo,
  reassign,
  children
}: {
  /** The flat visible data-row order + each row's group key. */
  rows: { id: string; groupKey: string }[]
  disabled: boolean
  canReorderWithin: boolean
  canReassign: boolean
  /** Commit a within-group reorder (the new flat order of row ids). */
  reorderTo: (orderIds: string[]) => void
  /** Commit a cross-group reassign (write the dragged row's grouped property to the target group). */
  reassign: (activeId: string, targetGroupKey: string) => void
  children: ReactNode
}): React.JSX.Element {
  const rowsRef = useRef(rows)
  rowsRef.current = rows
  const els = useRef(new Map<string, HTMLElement>())
  const content = useRef<HTMLDivElement | null>(null)
  const live = useRef<Slot | null>(null)
  const [drag, setDrag] = useState<DragState>(IDLE)
  const gesture = useRef<Gesture>({ kind: 'idle' })

  const registerRow = (id: string, el: HTMLElement | null): void => {
    if (el) els.current.set(id, el)
    else els.current.delete(id)
  }

  // Hit-test live row rects (nothing moves mid-drag) → the landing slot. The nearest row + which half
  // the cursor is in fixes the slot; that row's group is the target group (drop above row R or below it,
  // the slot sits in R's group either way).
  const computeSlot = (clientY: number): Slot | null => {
    const box = content.current
    const g = gesture.current
    if (!box || g.kind === 'idle') return null
    const activeGroup = rowsRef.current.find((r) => r.id === g.id)?.groupKey
    if (activeGroup === undefined) return null

    const measured: { id: string; top: number; bottom: number; mid: number; group: string }[] = []
    for (const r of rowsRef.current) {
      if (r.id === g.id) continue
      const el = els.current.get(r.id)
      if (!el) continue
      const rect = el.getBoundingClientRect()
      measured.push({ id: r.id, top: rect.top, bottom: rect.bottom, mid: rect.top + rect.height / 2, group: r.groupKey })
    }
    if (measured.length === 0) return null
    measured.sort((a, b) => a.top - b.top)

    // nearest row: the last whose top is at/above the cursor, else the first.
    let near = measured[0]
    for (const m of measured) {
      if (clientY >= m.top) near = m
      else break
    }
    const above = clientY < near.mid // drop before `near` vs after it
    const targetGroup = near.group
    const boxTop = box.getBoundingClientRect().top
    const nearEl = els.current.get(near.id)
    if (!nearEl) return null
    const r = nearEl.getBoundingClientRect()
    const boxLeft = box.getBoundingClientRect().left
    // End the line at the content edge (where the columns stop), not the full row — the row spans the
    // trailing 1fr filler too, so r.width would run the line out into the empty gutter past the last column.
    const filler = nearEl.querySelector('.cell-filler')
    const contentRight = filler ? filler.getBoundingClientRect().left : r.right
    const lineY = (above ? near.top : near.bottom) - boxTop
    const left = r.left - boxLeft + LINE_INSET
    const width = contentRight - r.left - LINE_INSET * 2

    if (targetGroup === activeGroup) {
      if (!canReorderWithin) return null
      // before `near` (above) or before the row after `near` in the flat order (below).
      const order = rowsRef.current.map((x) => x.id)
      const beforeId = above ? near.id : (order[order.indexOf(near.id) + 1] ?? null)
      const without = order.filter((id) => id !== g.id)
      const idx = beforeId ? without.indexOf(beforeId) : without.length
      const next = [...without.slice(0, idx), g.id, ...without.slice(idx)]
      const noop = next.length === order.length && next.every((id, i) => id === order[i])
      return { lineY, left, width, noop, commit: () => reorderTo(next) }
    }
    if (!canReassign) return null
    return { lineY, left, width, noop: false, commit: () => reassign(g.id, targetGroup) }
  }

  const detach = (): void => {
    const g = gesture.current
    if (g.kind === 'idle') return
    g.el.removeEventListener('pointermove', g.handlers.move)
    g.el.removeEventListener('pointerup', g.handlers.up)
    g.el.removeEventListener('pointercancel', g.handlers.cancel)
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
  // Swallow the click that fires right after a real drag so the drop doesn't also select the row.
  const suppressNextClick = (): void => {
    const swallow = (e: MouseEvent): void => {
      e.stopPropagation()
      e.preventDefault()
    }
    document.addEventListener('click', swallow, { capture: true, once: true })
    window.setTimeout(() => document.removeEventListener('click', swallow, { capture: true }), 0)
  }

  const begin = (id: string, e: ReactPointerEvent): void => {
    if (disabled || e.button !== 0 || !e.isPrimary || gesture.current.kind !== 'idle') return
    const el = els.current.get(id)
    if (!el) return
    const handlers: Handlers = { move: onMove, up: onUp, cancel: onCancel }
    gesture.current = { kind: 'pending', id, el, pid: e.pointerId, startX: e.clientX, startY: e.clientY, handlers }
    // Capture is deferred to activation: capturing on pointerdown would eat the click, so a tap could
    // never select the row.
    el.addEventListener('pointermove', handlers.move)
    el.addEventListener('pointerup', handlers.up)
    el.addEventListener('pointercancel', handlers.cancel)
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
    }
    const slot = computeSlot(e.clientY)
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

  const value = useMemo<Value>(() => ({ draggingId: drag.id, registerRow, begin }), [drag.id]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Ctx.Provider value={value}>
      <div ref={content} className="table-dnd">
        {children}
        {drag.slot && (
          <div className="table-drop-line" aria-hidden style={{ top: drag.slot.lineY, left: drag.slot.left, width: drag.slot.width }}>
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
    isDragging: ctx.draggingId === id
  }
}
