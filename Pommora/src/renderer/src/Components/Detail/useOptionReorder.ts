import { useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { ACTIVATION, suppressNextClick } from '@renderer/design-system/interactions/shared'

// Single-region drag-to-reorder for the option chip list — the flat cousin of the two-region paneDnd.
// The whole chip row is the handle (buttons/inputs inside never arm one); the dragged row dims in
// place and a drop-line marks the target gap. Escape aborts. The drop calls onReorder(value, toIndex)
// where toIndex is in the without-the-dragged coordinate space (matching optionModel.reorderOption).

type Handlers = { move: (e: PointerEvent) => void; up: () => void; cancel: () => void; key: (e: KeyboardEvent) => void }
type Gesture = { value: string; sx: number; sy: number; active: boolean; index: number; handlers: Handlers }

export function useOptionReorder(
  order: string[],
  onReorder: (value: string, toIndex: number) => void
): {
  containerRef: (el: HTMLDivElement | null) => void
  registerRow: (value: string, el: HTMLElement | null) => void
  onRowPointerDown: (value: string, e: ReactPointerEvent) => void
  dragging: string | null
  lineTop: number | null
} {
  const container = useRef<HTMLElement | null>(null)
  const rows = useRef(new Map<string, HTMLElement>())
  const orderRef = useRef(order)
  orderRef.current = order
  const onReorderRef = useRef(onReorder)
  onReorderRef.current = onReorder
  const g = useRef<Gesture | null>(null)
  const [dragging, setDragging] = useState<string | null>(null)
  const [lineTop, setLineTop] = useState<number | null>(null)

  const containerRef = (el: HTMLDivElement | null): void => {
    container.current = el
  }
  const registerRow = (value: string, el: HTMLElement | null): void => {
    if (el) rows.current.set(value, el)
    else rows.current.delete(value)
  }

  // Row geometry frozen at drag-start: reading a rect per row on every pointermove is layout-thrash
  // on a high-frequency trigger (the paneDnd snapshot pattern). A mid-drag scroll dirties it and the
  // next move re-measures.
  type Snapshot = { rects: Array<{ top: number; bottom: number }>; containerTop: number }
  const snapshot = useRef<Snapshot | null>(null)
  const snapshotDirty = useRef(false)
  const markDirty = (): void => {
    snapshotDirty.current = true
  }
  const takeSnapshot = (): Snapshot | null => {
    const cEl = container.current
    if (!cEl) return null
    const rects: Snapshot['rects'] = []
    for (const value of orderRef.current) {
      const el = rows.current.get(value)
      if (el) {
        const r = el.getBoundingClientRect()
        rects.push({ top: r.top, bottom: r.bottom })
      }
    }
    return { rects, containerTop: cEl.getBoundingClientRect().top }
  }

  // The drop index (0…n) the pointer is over, and the drop-line's Y within the container — read off
  // the frozen snapshot, never the live DOM.
  const locate = (clientY: number): { index: number; top: number } => {
    const snap = snapshot.current
    if (!snap) return { index: 0, top: 0 }
    const { rects, containerTop } = snap
    let index = rects.length
    for (let i = 0; i < rects.length; i++) {
      if (clientY < (rects[i].top + rects[i].bottom) / 2) {
        index = i
        break
      }
    }
    const top =
      index >= rects.length
        ? (rects[rects.length - 1]?.bottom ?? containerTop) - containerTop
        : (index === 0 ? rects[0].top : (rects[index - 1].bottom + rects[index].top) / 2) - containerTop
    return { index, top }
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
    setLineTop(null)
  }

  const onMove = (e: PointerEvent): void => {
    const s = g.current
    if (!s) return
    if (!s.active) {
      if (Math.hypot(e.clientX - s.sx, e.clientY - s.sy) < ACTIVATION) return
      s.active = true
      setDragging(s.value)
      window.addEventListener('scroll', markDirty, { capture: true, passive: true })
    }
    // First move after activation takes the snapshot here (it's null out of clear()); scroll dirties it.
    if (snapshotDirty.current || !snapshot.current) {
      snapshot.current = takeSnapshot()
      snapshotDirty.current = false
    }
    const { index, top } = locate(e.clientY)
    s.index = index
    setLineTop(top)
  }
  const onUp = (): void => {
    const s = g.current
    detach()
    if (s?.active) {
      const from = orderRef.current.indexOf(s.value)
      const to = s.index > from ? s.index - 1 : s.index
      if (from >= 0 && to !== from) onReorderRef.current(s.value, to)
      suppressNextClick() // the release must not open the chip's menu / recolor
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
    const handlers: Handlers = { move: onMove, up: onUp, cancel: onCancel, key: onKey }
    g.current = { value, sx: e.clientX, sy: e.clientY, active: false, index: 0, handlers }
    window.addEventListener('pointermove', handlers.move)
    window.addEventListener('pointerup', handlers.up)
    window.addEventListener('pointercancel', handlers.cancel)
    window.addEventListener('keydown', handlers.key, { capture: true })
  }

  return { containerRef, registerRow, onRowPointerDown, dragging, lineTop }
}
