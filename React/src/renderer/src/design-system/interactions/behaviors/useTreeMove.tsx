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
import { ACTIVATION } from '../shared'
import { announce } from '../a11y'

// Tree move (cross-level) — the named drag behavior for hierarchical file trees (the sidebar).
// Pick up an item (a page); the innermost drop container under the cursor highlights; drop ->
// onMove(fromPath, toPath). A portal overlay ghosts the row across the tree. File moves have no
// index, so there's no reorder/gap-shift here (that's a separate behavior) — this is the
// Finder/Obsidian model. Built on the shared drag primitives, separate from the sort engines.

type ItemReg = { el: HTMLElement; path: string; label: string }
type ContReg = { el: HTMLElement; path: string }

type TreeMoveValue = {
  activeId: string | null
  overId: string | null
  registerItem: (id: string, reg: ItemReg | null) => void
  registerContainer: (id: string, reg: ContReg | null) => void
  begin: (id: string, e: ReactPointerEvent) => void
}
const Ctx = createContext<TreeMoveValue | null>(null)

const base = (p: string): string => p.slice(p.lastIndexOf('/') + 1)
const parentDir = (p: string): string => p.slice(0, Math.max(0, p.lastIndexOf('/')))

export function TreeMove({ onMove, children }: { onMove: (fromPath: string, toPath: string) => void; children: ReactNode }): React.JSX.Element {
  const items = useRef(new Map<string, ItemReg>())
  const conts = useRef(new Map<string, ContReg>())
  const onMoveRef = useRef(onMove)
  onMoveRef.current = onMove

  const [activeId, setActiveId] = useState<string | null>(null)
  const [overId, setOverId] = useState<string | null>(null)
  const [pos, setPos] = useState({ x: 0, y: 0 }) // overlay top-left (fixed)
  const [size, setSize] = useState({ w: 0, h: 0 })
  const [label, setLabel] = useState('')

  const drag = useRef({
    id: '',
    el: null as HTMLElement | null,
    pid: -1,
    startX: 0,
    startY: 0,
    grabX: 0,
    grabY: 0,
    active: false,
    over: null as string | null,
    handlers: null as null | { move: (e: PointerEvent) => void; up: () => void; cancel: () => void }
  })

  const registerItem = (id: string, reg: ItemReg | null): void => {
    if (reg) items.current.set(id, reg)
    else items.current.delete(id)
  }
  const registerContainer = (id: string, reg: ContReg | null): void => {
    if (reg) conts.current.set(id, reg)
    else conts.current.delete(id)
  }

  // The innermost container under the pointer: the smallest-area registered container whose rect
  // contains the point. Containers don't transform, so live getBoundingClientRect is accurate.
  const containerAt = (x: number, y: number): string | null => {
    let best: string | null = null
    let bestArea = Infinity
    for (const [id, c] of conts.current) {
      const r = c.el.getBoundingClientRect()
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {
        const area = r.width * r.height
        if (area < bestArea) {
          bestArea = area
          best = id
        }
      }
    }
    return best
  }

  const onMovePtr = (e: PointerEvent): void => {
    const d = drag.current
    if (!d.active) {
      if (Math.hypot(e.clientX - d.startX, e.clientY - d.startY) < ACTIVATION) return
      const it = items.current.get(d.id)
      if (!it) {
        detach()
        return
      }
      d.active = true
      setActiveId(d.id)
      setLabel(it.label)
      announce(`Picked up ${it.label}.`)
    }
    setPos({ x: e.clientX - d.grabX, y: e.clientY - d.grabY })
    const over = containerAt(e.clientX, e.clientY)
    if (over !== d.over) {
      d.over = over
      setOverId(over)
    }
  }

  const detach = (): void => {
    const d = drag.current
    if (d.el && d.handlers) {
      d.el.removeEventListener('pointermove', d.handlers.move)
      d.el.removeEventListener('pointerup', d.handlers.up)
      d.el.removeEventListener('pointercancel', d.handlers.cancel)
      try {
        d.el.releasePointerCapture(d.pid)
      } catch {
        // already released
      }
    }
    d.handlers = null
  }

  const reset = (): void => {
    drag.current.active = false
    drag.current.over = null
    setActiveId(null)
    setOverId(null)
  }

  // Swallow the click that fires after a real drag, so dropping a row doesn't also select it.
  const suppressNextClick = (): void => {
    const swallow = (e: MouseEvent): void => {
      e.stopPropagation()
      e.preventDefault()
    }
    document.addEventListener('click', swallow, { capture: true, once: true })
    window.setTimeout(() => document.removeEventListener('click', swallow, { capture: true }), 0)
  }

  const onUp = (): void => {
    detach()
    const d = drag.current
    if (!d.active) {
      reset()
      return // never passed activation — a click, not a drag
    }
    const it = items.current.get(d.id)
    const overC = d.over ? conts.current.get(d.over) : null
    if (it && overC && overC.path !== parentDir(it.path)) {
      onMoveRef.current(it.path, overC.path)
      announce(`Moved ${it.label} into ${base(overC.path)}.`)
    } else if (it) {
      announce(`${it.label} stayed where it was.`)
    }
    suppressNextClick()
    reset()
  }

  const onCancel = (): void => {
    detach()
    reset()
  }

  const begin = (id: string, e: ReactPointerEvent): void => {
    if (e.button !== 0 || !e.isPrimary || drag.current.active) return
    // Don't hijack a click into the inline-rename field (capturing the pointer would break editing).
    if ((e.target as HTMLElement).closest?.('input, textarea, [contenteditable="true"]')) return
    const it = items.current.get(id)
    if (!it) return
    const r = it.el.getBoundingClientRect()
    setSize({ w: r.width, h: r.height })
    setPos({ x: r.left, y: r.top })
    const handlers = { move: onMovePtr, up: onUp, cancel: onCancel }
    drag.current = {
      id,
      el: it.el,
      pid: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      grabX: e.clientX - r.left,
      grabY: e.clientY - r.top,
      active: false,
      over: null,
      handlers
    }
    try {
      it.el.setPointerCapture(e.pointerId)
    } catch {
      // capture unavailable
    }
    it.el.addEventListener('pointermove', handlers.move)
    it.el.addEventListener('pointerup', handlers.up)
    it.el.addEventListener('pointercancel', handlers.cancel)
  }

  useEffect(() => () => detach(), [])

  const value = useMemo<TreeMoveValue>(
    () => ({ activeId, overId, registerItem, registerContainer, begin }),
    // register/begin read refs only; identity churn each render is fine.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [activeId, overId]
  )

  return (
    <Ctx.Provider value={value}>
      {children}
      {activeId &&
        createPortal(
          <div
            className="tree-drag-overlay"
            style={{ position: 'fixed', left: pos.x, top: pos.y, width: size.w, height: size.h, pointerEvents: 'none', zIndex: 1000 }}
          >
            {label}
          </div>,
          document.body
        )}
    </Ctx.Provider>
  )
}

/** Make a row draggable (a page). Spread `handle` on the row, put `setNodeRef` on it. */
export function useTreeDrag(id: string, path: string, label: string): { setNodeRef: (el: HTMLElement | null) => void; handle: { onPointerDown: (e: ReactPointerEvent) => void }; isDragging: boolean } {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useTreeDrag must be used inside <TreeMove>')
  return {
    setNodeRef: (el) => ctx.registerItem(id, el ? { el, path, label } : null),
    handle: { onPointerDown: (e) => ctx.begin(id, e) },
    isDragging: ctx.activeId === id
  }
}

/** Make a row a drop container (a Set / Collection / Vault). Put `setNodeRef` on its wrapper. */
export function useTreeDrop(id: string, path: string): { setNodeRef: (el: HTMLElement | null) => void; isOver: boolean } {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useTreeDrop must be used inside <TreeMove>')
  return {
    setNodeRef: (el) => ctx.registerContainer(id, el ? { el, path } : null),
    isOver: ctx.overId === id
  }
}
