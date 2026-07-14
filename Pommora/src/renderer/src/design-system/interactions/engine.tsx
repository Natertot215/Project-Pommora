import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
  type PointerEvent as ReactPointerEvent,
  type ReactNode
} from 'react'
import { useFeel, type Feel } from './feel'
import { findScroller, startAutoScroll } from './autoscroll'
import { announce, ensureInstructions, INSTRUCTIONS_ID } from './a11y'
import { ARROW_DIRS, keyboardNext } from './keyboard'
import { ACTIVATION, HYSTERESIS, SETTLE_FALLBACK, px, toBox, type Box, type DragItem, type DragNotify, type DropState, type Modifier } from './shared'

// The single-zone drag engine. Replaces dnd-kit behind the seam for every standalone
// surface (list, grid, table, each tree level). Principles, grounded in the dnd-kit dissection:
//
//   • One pointer sensor — Pointer Events + setPointerCapture (Chromium), no document listeners.
//     A keyboard path mirrors it: Space/Enter lifts, arrows move, Space/Enter drops, Esc cancels.
//   • Measure rects once at drag start; no continuous re-measuring, no array churn mid-drag.
//   • Closest-center collision with hysteresis (no slot-boundary flicker); DOM order breaks ties.
//   • One strategy-agnostic displacement: the rects-reflow shift covers list, row, and 2-D grid.
//     `swap` mode instead exchanges the active + over items only.
//   • Decide, THEN animate (shared by pointer + keyboard): run the accept/reject decision first,
//     then animate the item to its TRUE resting slot. `canReorder` may be async (`pending` hold).
//   • Constraints are inline options: `axis` lock, `bounds` clamp, plus a `modifiers` escape hatch.
//   • Auto-scroll: the shared loop (interactions/autoscroll.ts) scrolls the container at the edges;
//     each scrolled frame re-runs `track`, so the scroll delta stays compensated into the drag.
//   • Accessible: focusable handle + assertive live-region announcements + restored focus on drop.

type ZoneValue = {
  ids: string[]
  feel: Feel
  activeId: string | null
  overIndex: number
  delta: { x: number; y: number }
  scrollComp: { x: number; y: number }
  rects: Box[]
  dropState: DropState
  keyboard: boolean
  disabled: boolean
  swap: boolean
  itemRole: string | null
  register: (id: string, el: HTMLElement | null) => void
  begin: (id: string, e: ReactPointerEvent) => void
  liftKeyboard: (id: string) => void
}
const ZoneCtx = createContext<ZoneValue | null>(null)

export type ZoneProps = DragNotify & {
  ids: string[]
  onReorder?: (activeId: string, overId: string) => void
  /** Decide-then-animate hook. Return false (or a Promise<false>) to reject; the item animates back
   *  to origin. A Promise holds the item lifted (`pending`) until it resolves. */
  canReorder?: (activeId: string, overId: string) => boolean | Promise<boolean>
  disabled?: boolean
  /** Lock the drag to one axis. */
  axis?: 'x' | 'y'
  /** Clamp the lifted item within the viewport (`window`) or the list's own extent (`parent`). */
  bounds?: 'parent' | 'window'
  /** Escape hatch: fold the drag translation through custom transforms (applied after axis+bounds). */
  modifiers?: Modifier[]
  /** Exchange the active + over items instead of shifting the gap. Commit with `arraySwap`. */
  swap?: boolean
  /** ARIA role for each item's handle (default 'button'); set null to omit it (e.g. table rows). */
  itemRole?: string | null
  /** Human label for screen-reader announcements (defaults to the id). */
  getItemLabel?: (id: string) => string
  children: ReactNode
}

export function Zone({
  ids,
  onReorder,
  canReorder,
  disabled = false,
  axis,
  bounds,
  modifiers,
  swap = false,
  itemRole = 'button',
  getItemLabel,
  children,
  ...notify
}: ZoneProps): React.JSX.Element {
  const feel = useFeel()

  const els = useRef(new Map<string, HTMLElement>())
  const idsRef = useRef(ids)
  idsRef.current = ids
  const feelRef = useRef(feel)
  feelRef.current = feel
  const notifyRef = useRef(notify)
  notifyRef.current = notify
  const cbRef = useRef({ onReorder, canReorder })
  cbRef.current = { onReorder, canReorder }
  const optsRef = useRef({ axis, bounds, modifiers })
  optsRef.current = { axis, bounds, modifiers }
  const labelRef = useRef(getItemLabel)
  labelRef.current = getItemLabel

  const [activeId, setActiveId] = useState<string | null>(null)
  const [overIndex, setOverIndex] = useState(-1)
  const [delta, setDelta] = useState({ x: 0, y: 0 })
  const [scrollComp, setScrollComp] = useState({ x: 0, y: 0 })
  const [rects, setRects] = useState<Box[]>([])
  const [dropState, setDropState] = useState<DropState>('idle')
  const [keyboard, setKeyboard] = useState(false)

  // Mutable drag scratch — read inside pointer/rAF/keydown callbacks without stale closures.
  const drag = useRef({
    id: '',
    pid: -1,
    el: null as HTMLElement | null,
    startX: 0,
    startY: 0,
    lastX: 0,
    lastY: 0,
    active: false,
    activeIdx: -1,
    rects: [] as Box[],
    over: -1,
    bounds: null as Box | null,
    scroller: null as HTMLElement | null,
    scroll0X: 0,
    scroll0Y: 0,
    handlers: null as null | { move: (e: PointerEvent) => void; up: () => void; cancel: () => void },
    kdown: null as null | ((e: KeyboardEvent) => void)
  })

  // The auto-scroll loop this Zone started (instance-scoped stopper). detach() calls it rather than the
  // global stop, so a sibling Zone's unmount can't halt THIS Zone's live drag (the loop is a module singleton).
  const stopScroll = useRef<(() => void) | null>(null)

  const labelOf = (id: string): string => labelRef.current?.(id) ?? id
  const register = (id: string, el: HTMLElement | null): void => {
    if (el) els.current.set(id, el)
    else els.current.delete(id)
  }

  // Measure every item's rect once. Returns null if any item is unregistered (e.g. a virtualized
  // row not yet mounted) — the caller aborts the drag cleanly rather than crashing.
  const measure = (): Box[] | null => {
    const out: Box[] = []
    for (const id of idsRef.current) {
      const el = els.current.get(id)
      if (!el) return null
      out.push(toBox(el))
    }
    return out
  }

  // Apply axis lock → bounds clamp → modifiers to the raw pointer delta.
  const constrain = (dx: number, dy: number): { x: number; y: number } => {
    const o = optsRef.current
    const ar = drag.current.rects[drag.current.activeIdx]
    let x = o.axis === 'y' ? 0 : dx
    let y = o.axis === 'x' ? 0 : dy
    const bnd = drag.current.bounds
    if (bnd && ar) {
      x = Math.max(bnd.left - ar.left, Math.min(x, bnd.left + bnd.width - (ar.left + ar.width)))
      y = Math.max(bnd.top - ar.top, Math.min(y, bnd.top + bnd.height - (ar.top + ar.height)))
    }
    if (o.modifiers && ar) for (const m of o.modifiers) ({ x, y } = m({ x, y }, { activeRect: ar, bounds: bnd }))
    return { x, y }
  }

  // Recompute over-slot + delta for a pointer position. Shared by onMove and the auto-scroll loop.
  const track = (cx: number, cy: number): void => {
    const d = drag.current
    if (!d.active) return
    const comp = d.scroller ? { x: d.scroller.scrollLeft - d.scroll0X, y: d.scroller.scrollTop - d.scroll0Y } : { x: 0, y: 0 }
    const { x: dx, y: dy } = constrain(cx - d.startX, cy - d.startY)
    // Closest-center with the container's scroll delta folded in; strict `<` + in-order = DOM-order tie-break.
    const px = d.rects[d.activeIdx].cx + dx + comp.x
    const py = d.rects[d.activeIdx].cy + dy + comp.y
    let best = d.over
    let bestDist = Infinity
    d.rects.forEach((b, i) => {
      const dist = Math.hypot(b.cx - px, b.cy - py)
      if (dist < bestDist) {
        bestDist = dist
        best = i
      }
    })
    const curDist = Math.hypot(d.rects[d.over].cx - px, d.rects[d.over].cy - py)
    const next = best !== d.over && curDist - bestDist > HYSTERESIS ? best : d.over
    setDelta({ x: dx, y: dy })
    setScrollComp(comp)
    if (next !== d.over) {
      d.over = next
      setOverIndex(next)
      notifyRef.current.onDragOver?.({ activeId: d.id, overId: idsRef.current[next] ?? null })
    }
  }

  const onMove = (e: PointerEvent): void => {
    const d = drag.current
    if (!d.active) {
      if (Math.hypot(e.clientX - d.startX, e.clientY - d.startY) < ACTIVATION) return
      const measured = measure()
      const activeIdx = idsRef.current.indexOf(d.id)
      if (!measured || activeIdx === -1) {
        detach()
        return // can't drag without a complete layout snapshot
      }
      d.active = true
      d.activeIdx = activeIdx
      d.rects = measured
      d.over = activeIdx
      d.bounds = resolveBounds(optsRef.current.bounds, measured)
      d.scroller = findScroller(d.el, 'xy')
      d.scroll0X = d.scroller?.scrollLeft ?? 0
      d.scroll0Y = d.scroller?.scrollTop ?? 0
      setActiveId(d.id)
      setRects(measured)
      setOverIndex(activeIdx)
      setDropState('dragging')
      notifyRef.current.onDragStart?.({ activeId: d.id })
      // The module owns the scroll loop; on each scrolled frame it re-runs `track` off the last point,
      // exactly as the old inline `tick` did. The engine folds the scroller's delta into `track`'s
      // collision math (see `comp`), so it passes the SAME scroller explicitly.
      if (d.scroller) {
        stopScroll.current = startAutoScroll({
          getPoint: () => ({ x: drag.current.lastX, y: drag.current.lastY }),
          scroller: d.scroller,
          dragEl: d.el,
          axis: 'xy',
          onScrolled: () => track(drag.current.lastX, drag.current.lastY)
        })
      }
    }
    d.lastX = e.clientX
    d.lastY = e.clientY
    track(e.clientX, e.clientY)
  }

  // Tear down everything a live drag attached: the auto-scroll loop, pointer listeners + capture, the keydown listener.
  const detach = (): void => {
    stopScroll.current?.()
    stopScroll.current = null
    const d = drag.current
    if (d.el && d.handlers) {
      d.el.removeEventListener('pointermove', d.handlers.move)
      d.el.removeEventListener('pointerup', d.handlers.up)
      d.el.removeEventListener('pointercancel', d.handlers.cancel)
      try {
        d.el.releasePointerCapture(d.pid)
      } catch {
        // pointer already released
      }
    }
    d.handlers = null
    if (d.kdown) {
      document.removeEventListener('keydown', d.kdown)
      d.kdown = null
    }
  }

  // Animate the lifted item to its final slot, then settle. We commit on the lifted item's
  // `transitionend` — NOT a blind timer — because the CSS transition starts a frame after a timer
  // would, so a timer fires while gap items are still mid-flight and snaps them short (the jerk).
  // The lifted item's transition starts last, so its end means every item has settled. Fallback
  // timer covers the no-transition case.
  const settle = (targetIndex: number, commit: () => void): void => {
    setDropState('dropping')
    setOverIndex(targetIndex)
    const el = drag.current.el
    let done = false
    const finish = (): void => {
      if (done) return
      done = true
      drag.current.active = false
      el?.removeEventListener('transitionend', onEnd)
      setDropState('idle')
      setActiveId(null)
      setOverIndex(-1)
      setDelta({ x: 0, y: 0 })
      setScrollComp({ x: 0, y: 0 })
      setKeyboard(false)
      commit()
    }
    const onEnd = (e: TransitionEvent): void => {
      if (e.target === el && e.propertyName === 'transform') finish()
    }
    el?.addEventListener('transitionend', onEnd)
    window.setTimeout(finish, feelRef.current.duration + SETTLE_FALLBACK)
  }

  // Decide-then-animate, shared by pointer drop and keyboard drop. `kbd` carries the announce +
  // focus-restore context when the drop came from the keyboard.
  const resolveDrop = (over: number, activeIdx: number, activeId2: string, kbd: { label: string; n: number; el: HTMLElement | null } | null): void => {
    const overId = idsRef.current[over]
    const apply = (ok: boolean): void =>
      settle(ok ? over : activeIdx, () => {
        if (ok) cbRef.current.onReorder?.(activeId2, overId)
        notifyRef.current.onDragEnd?.({ activeId: activeId2, overId: ok ? overId : null })
        if (kbd) {
          announce(ok ? `Dropped ${kbd.label} at position ${over + 1} of ${kbd.n}.` : `${kbd.label} returned to its original position.`)
          requestAnimationFrame(() => kbd.el?.focus())
        }
      })
    if (over === activeIdx) {
      apply(false) // dropped on its own slot — animate home, no reorder
      return
    }
    const verdict = cbRef.current.canReorder?.(activeId2, overId) ?? true
    if (verdict instanceof Promise) {
      setDropState('pending')
      verdict.then(apply).catch(() => apply(false))
    } else {
      apply(verdict)
    }
  }

  const onUp = (): void => {
    detach()
    const d = drag.current
    if (!d.active) return // never passed activation — it was a click, not a drag
    resolveDrop(d.over, d.activeIdx, d.id, null)
  }

  const onCancel = (): void => {
    detach()
    const d = drag.current
    if (!d.active) return
    const activeId2 = d.id
    settle(d.activeIdx, () => notifyRef.current.onDragCancel?.({ activeId: activeId2 }))
  }

  const begin = (id: string, e: ReactPointerEvent): void => {
    if (disabled || e.button !== 0 || !e.isPrimary) return
    if (drag.current.active) return // a drag is in progress or still committing
    const el = els.current.get(id) ?? null
    if (!el) return
    const handlers = { move: onMove, up: onUp, cancel: onCancel }
    drag.current = {
      id,
      pid: e.pointerId,
      el,
      startX: e.clientX,
      startY: e.clientY,
      lastX: e.clientX,
      lastY: e.clientY,
      active: false,
      activeIdx: -1,
      rects: [],
      over: -1,
      bounds: null,
      scroller: null,
      scroll0X: 0,
      scroll0Y: 0,
      handlers,
      kdown: null
    }
    try {
      el.setPointerCapture(e.pointerId)
    } catch {
      // capture unavailable — listeners on the element still work for in-bounds drags
    }
    el.addEventListener('pointermove', handlers.move)
    el.addEventListener('pointerup', handlers.up)
    el.addEventListener('pointercancel', handlers.cancel)
  }

  const onKeyboard = (e: KeyboardEvent): void => {
    const d = drag.current
    if (!d.active) return
    if (e.key in ARROW_DIRS) {
      e.preventDefault()
      const next = keyboardNext(d.rects, d.over, ARROW_DIRS[e.key])
      if (next !== d.over) {
        d.over = next
        setOverIndex(next)
        announce(`Moved to position ${next + 1} of ${d.rects.length}.`)
      }
    } else if (e.key === ' ' || e.key === 'Enter' || e.key === 'Tab') {
      // Space/Enter/Tab all drop (dnd-kit parity) — Tab must commit, not tab focus away mid-drag.
      e.preventDefault()
      detach()
      resolveDrop(d.over, d.activeIdx, d.id, { label: labelOf(d.id), n: d.rects.length, el: d.el })
    } else if (e.key === 'Escape') {
      e.preventDefault()
      detach()
      const activeId2 = d.id
      const el = d.el
      const label = labelOf(activeId2)
      settle(d.activeIdx, () => {
        notifyRef.current.onDragCancel?.({ activeId: activeId2 })
        announce(`Movement cancelled. ${label} returned to its original position.`)
        requestAnimationFrame(() => el?.focus())
      })
    }
  }

  // Keyboard lift: Space/Enter on a focused item. Measures, parks the item on its own slot, and
  // listens on the document for arrows/Space/Esc (the lift keydown won't re-fire — listeners added
  // mid-dispatch are skipped for the current event).
  const liftKeyboard = (id: string): void => {
    if (disabled || drag.current.active) return
    const el = els.current.get(id) ?? null
    const measured = measure()
    const activeIdx = idsRef.current.indexOf(id)
    if (!el || !measured || activeIdx === -1) return
    const kdown = (e: KeyboardEvent): void => onKeyboard(e)
    drag.current = {
      id,
      pid: -1,
      el,
      startX: 0,
      startY: 0,
      lastX: 0,
      lastY: 0,
      active: true,
      activeIdx,
      rects: measured,
      over: activeIdx,
      bounds: null,
      scroller: null,
      scroll0X: 0,
      scroll0Y: 0,
      handlers: null,
      kdown
    }
    setActiveId(id)
    setRects(measured)
    setOverIndex(activeIdx)
    setKeyboard(true)
    setDropState('dragging')
    document.addEventListener('keydown', kdown)
    notifyRef.current.onDragStart?.({ activeId: id })
    announce(`Picked up ${labelOf(id)}. Item ${activeIdx + 1} of ${measured.length}.`)
  }

  // Unmount mid-drag: pull listeners + stop the auto-scroll loop so nothing dangles on a detached node.
  useEffect(() => () => detach(), [])
  useEffect(() => ensureInstructions(), [])

  const value = useMemo<ZoneValue>(
    () => ({ ids, feel, activeId, overIndex, delta, scrollComp, rects, dropState, keyboard, disabled, swap, itemRole, register, begin, liftKeyboard }),
    // register reads only refs; begin/liftKeyboard also close over `disabled` (in deps). Recreating
    // them each render with current values is intentional — not memoized, so identity churn is fine.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [ids, feel, activeId, overIndex, delta, scrollComp, rects, dropState, keyboard, disabled, swap, itemRole]
  )
  return <ZoneCtx.Provider value={value}>{children}</ZoneCtx.Provider>
}

function resolveBounds(kind: 'parent' | 'window' | undefined, rects: Box[]): Box | null {
  if (kind === 'window') return { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight, cx: 0, cy: 0 }
  if (kind === 'parent' && rects.length) {
    const left = Math.min(...rects.map((r) => r.left))
    const top = Math.min(...rects.map((r) => r.top))
    const right = Math.max(...rects.map((r) => r.left + r.width))
    const bottom = Math.max(...rects.map((r) => r.top + r.height))
    return { left, top, width: right - left, height: bottom - top, cx: 0, cy: 0 }
  }
  return null
}

/** rects-reflow: where the item at `index` lands once the active item moves to the over-slot. */
export function reflow(rects: Box[], overIndex: number, activeIdx: number, index: number): Box {
  const a = rects.slice()
  const [moved] = a.splice(overIndex, 1)
  a.splice(activeIdx, 0, moved)
  return a[index] ?? rects[index]
}

export function useZoneItem(id: string): DragItem {
  const ctx = useContext(ZoneCtx)
  if (!ctx) throw new Error('useDragItem must be used inside a <SortableZone>')
  const { ids, feel, activeId, overIndex, delta, scrollComp, rects, dropState, keyboard, disabled, swap, itemRole, register, begin, liftKeyboard } = ctx
  const index = ids.indexOf(id)
  const isDragging = activeId === id
  const activeIdx = activeId ? ids.indexOf(activeId) : -1

  let transform = 'translate3d(0,0,0)'
  if (rects.length && activeIdx !== -1 && index !== -1) {
    if (isDragging) {
      // The lifted item sits on the over-slot for keyboard (eases each arrow step) or on drop;
      // otherwise it follows the pointer + scroll compensation. (On the slot, no comp — the slot
      // scrolled with the item, so they cancel.)
      const onSlot = keyboard || dropState === 'dropping'
      const t = onSlot ? rects[overIndex] ?? rects[activeIdx] : null
      const x = t ? t.left - rects[activeIdx].left : delta.x + scrollComp.x
      const y = t ? t.top - rects[activeIdx].top : delta.y + scrollComp.y
      transform = `translate3d(${px(x)}, ${px(y)}, 0)`
    } else if (swap) {
      // Swap mode: only the over item moves, exchanging into the active item's slot.
      if (index === overIndex) transform = `translate3d(${px(rects[activeIdx].left - rects[index].left)}, ${px(rects[activeIdx].top - rects[index].top)}, 0)`
    } else {
      // Shift mode: everyone shifts to open/close the gap, computed by reflow (list/row/grid).
      const t = reflow(rects, overIndex, activeIdx, index)
      transform = `translate3d(${px(t.left - rects[index].left)}, ${px(t.top - rects[index].top)}, 0)`
    }
  }

  // Transition during a live drag: non-active items ease the gap; the active item eases on drop and
  // on every keyboard arrow step (but follows the pointer with no transition during a pointer drag).
  // At rest (idle) it's OFF, so the commit reorder snaps into place pixel-identically — no jerk.
  const animate = isDragging ? dropState === 'dropping' || keyboard : dropState !== 'idle'
  return {
    setNodeRef: (el) => register(id, el),
    style: {
      transform,
      transition: animate ? `transform ${feel.duration}ms ${feel.easing}` : 'none',
      zIndex: isDragging ? 10 : undefined,
      position: 'relative',
      touchAction: 'none'
    },
    handle: {
      onPointerDown: (e: ReactPointerEvent) => begin(id, e),
      onKeyDown: (e: ReactKeyboardEvent) => {
        if ((e.key === ' ' || e.key === 'Enter') && !isDragging && !disabled) {
          e.preventDefault()
          liftKeyboard(id)
        }
      },
      role: itemRole ?? undefined,
      tabIndex: disabled ? -1 : 0,
      'aria-roledescription': 'sortable',
      'aria-describedby': INSTRUCTIONS_ID,
      // aria-pressed only on button-role items (dnd-kit gates it the same way — invalid on a roleless <tr>).
      'aria-pressed': itemRole != null && isDragging ? true : undefined,
      'aria-disabled': disabled || undefined
    },
    isDragging
  }
}
