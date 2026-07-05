import { useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { ACTIVATION, suppressNextClick } from '@renderer/design-system/interactions/shared'

// Group-aware drag-to-reorder for the Status option editor — the multi-region cousin of useOptionReorder.
// The whole chip row is the handle (buttons/inputs inside never arm one). A drag can reorder within a
// group OR cross into another group (including an empty one); on drop it calls
// onMove(value, toGroupId, toIndex) — toIndex in the target group's without-the-dragged space, matching
// optionModel.moveStatusOption. Row geometry is snapshotted at drag-start (no rect-read per move — the
// hard rule); a mid-drag scroll dirties the snapshot. Escape aborts. The drop-line lives in the target
// group and its Y is relative to that group's list container.

type Handlers = { move: (e: PointerEvent) => void; up: () => void; cancel: () => void; key: (e: KeyboardEvent) => void }
type Gesture = { value: string; sx: number; sy: number; active: boolean; toGroupId: string; toIndex: number; handlers: Handlers }
type SnapRow = { value: string; top: number; bottom: number }
type SnapGroup = { id: string; top: number; bottom: number; containerTop: number; rows: SnapRow[] }

/** `order`: the current group structure (each group's id + its ordered option values) — the identity
 *  the snapshot iterates. Passing it keeps the hook's geometry aligned with what's rendered. */
export function useStatusReorder(
  order: { id: string; values: string[] }[],
  onMove: (value: string, toGroupId: string, toIndex: number) => void
): {
  registerGroup: (groupId: string, el: HTMLElement | null) => void
  registerRow: (value: string, el: HTMLElement | null) => void
  onRowPointerDown: (value: string, e: ReactPointerEvent) => void
  dragging: string | null
  drop: { groupId: string; top: number } | null
} {
  const groupEls = useRef(new Map<string, HTMLElement>())
  const rows = useRef(new Map<string, HTMLElement>())
  const orderRef = useRef(order)
  orderRef.current = order
  const onMoveRef = useRef(onMove)
  onMoveRef.current = onMove
  const g = useRef<Gesture | null>(null)
  const [dragging, setDragging] = useState<string | null>(null)
  const [drop, setDrop] = useState<{ groupId: string; top: number } | null>(null)

  const registerGroup = (groupId: string, el: HTMLElement | null): void => {
    if (el) groupEls.current.set(groupId, el)
    else groupEls.current.delete(groupId)
  }
  const registerRow = (value: string, el: HTMLElement | null): void => {
    if (el) rows.current.set(value, el)
    else rows.current.delete(value)
  }

  const snapshot = useRef<SnapGroup[] | null>(null)
  const snapshotDirty = useRef(false)
  const markDirty = (): void => {
    snapshotDirty.current = true
  }
  const takeSnapshot = (): SnapGroup[] => {
    return orderRef.current.map((grp) => {
      const container = groupEls.current.get(grp.id)
      const cRect = container?.getBoundingClientRect()
      const rowRects: SnapRow[] = []
      for (const value of grp.values) {
        const el = rows.current.get(value)
        if (el) {
          const r = el.getBoundingClientRect()
          rowRects.push({ value, top: r.top, bottom: r.bottom })
        }
      }
      return {
        id: grp.id,
        top: cRect?.top ?? 0,
        bottom: cRect?.bottom ?? 0,
        containerTop: cRect?.top ?? 0,
        rows: rowRects
      }
    })
  }

  // The target group + drop index the pointer is over, and the drop-line's Y within that group's
  // container — read off the frozen snapshot. Groups partition the pointer axis by boundary midpoints,
  // so every clientY (gaps + empty groups included) resolves to exactly one group.
  const locate = (clientY: number): { groupId: string; index: number; top: number } | null => {
    const snap = snapshot.current
    if (!snap || snap.length === 0) return null
    let gi = snap.length - 1
    for (let i = 0; i < snap.length - 1; i++) {
      const boundary = (snap[i].bottom + snap[i + 1].top) / 2
      if (clientY < boundary) {
        gi = i
        break
      }
    }
    const grp = snap[gi]
    let index = grp.rows.length
    for (let i = 0; i < grp.rows.length; i++) {
      if (clientY < (grp.rows[i].top + grp.rows[i].bottom) / 2) {
        index = i
        break
      }
    }
    const lineY =
      index >= grp.rows.length
        ? (grp.rows[grp.rows.length - 1]?.bottom ?? grp.containerTop)
        : index === 0
          ? grp.rows[0].top
          : (grp.rows[index - 1].bottom + grp.rows[index].top) / 2
    return { groupId: grp.id, index, top: lineY - grp.containerTop }
  }

  const detach = (): void => {
    const h = g.current?.handlers
    if (!h) return
    window.removeEventListener('pointermove', h.move)
    window.removeEventListener('pointerup', h.up)
    window.removeEventListener('pointercancel', h.cancel)
    window.removeEventListener('keydown', h.key, { capture: true })
    window.removeEventListener('scroll', markDirty, { capture: true })
  }
  const clear = (): void => {
    g.current = null
    snapshot.current = null
    snapshotDirty.current = false
    setDragging(null)
    setDrop(null)
  }

  const onPtrMove = (e: PointerEvent): void => {
    const s = g.current
    if (!s) return
    if (!s.active) {
      if (Math.hypot(e.clientX - s.sx, e.clientY - s.sy) < ACTIVATION) return
      s.active = true
      setDragging(s.value)
      window.addEventListener('scroll', markDirty, { capture: true, passive: true })
    }
    if (snapshotDirty.current || !snapshot.current) {
      snapshot.current = takeSnapshot()
      snapshotDirty.current = false
    }
    const hit = locate(e.clientY)
    if (!hit) return
    s.toGroupId = hit.groupId
    s.toIndex = hit.index
    setDrop({ groupId: hit.groupId, top: hit.top })
  }
  const onUp = (): void => {
    const s = g.current
    detach()
    if (s?.active) {
      const fromGroup = orderRef.current.find((grp) => grp.values.includes(s.value))
      const fromIndex = fromGroup?.values.indexOf(s.value) ?? -1
      const sameGroup = fromGroup?.id === s.toGroupId
      // s.toIndex is in the WITH-dragged snapshot space; moveStatusOption inserts in the WITHOUT space,
      // so a same-group drop past the original slot shifts down by one. Cross-group needs no shift.
      const toIndex = sameGroup && s.toIndex > fromIndex ? s.toIndex - 1 : s.toIndex
      if (!(sameGroup && toIndex === fromIndex)) onMoveRef.current(s.value, s.toGroupId, toIndex)
      suppressNextClick() // the release must not open the chip's recolor
    }
    clear()
  }
  const onCancel = (): void => {
    detach()
    clear()
  }
  const onKey = (e: KeyboardEvent): void => {
    if (e.key === 'Escape' && g.current?.active) {
      e.stopImmediatePropagation()
      e.preventDefault()
      onCancel()
    }
  }

  const onRowPointerDown = (value: string, e: ReactPointerEvent): void => {
    if (e.button !== 0 || !e.isPrimary || g.current) return
    if ((e.target as HTMLElement).closest?.('button, input, [contenteditable="true"]')) return
    const handlers: Handlers = { move: onPtrMove, up: onUp, cancel: onCancel, key: onKey }
    g.current = { value, sx: e.clientX, sy: e.clientY, active: false, toGroupId: '', toIndex: 0, handlers }
    window.addEventListener('pointermove', handlers.move)
    window.addEventListener('pointerup', handlers.up)
    window.addEventListener('pointercancel', handlers.cancel)
    window.addEventListener('keydown', handlers.key, { capture: true })
  }

  return { registerGroup, registerRow, onRowPointerDown, dragging, drop }
}
