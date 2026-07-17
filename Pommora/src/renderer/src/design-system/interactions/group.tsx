import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from 'react'
import { createPortal } from 'react-dom'
import { useFeel } from './feel'
import {
  ACTIVATION,
  SETTLE_FALLBACK,
  px,
  toBox,
  type Box,
  type DragItem,
  type DropState,
} from './shared'

// Cross-list drag (the board). A DragGroup owns the one active drag across its zones. No
// array churn: the lifted card is hidden in its source column and rendered as a portal overlay
// under the cursor; every column just shifts its items by one slot-pitch to show where the card
// would land. The move commits once, on drop (decide-then-animate). Each zone's rects are frozen
// the first time the drag enters it (measured before any shift), mirroring the single-zone engine.

type ZoneReg = { ids: string[]; els: Map<string, HTMLElement>; container: HTMLElement | null }
type ActiveDrag = { id: string; zone: string; srcIdx: number; pitch: number; rect: Box }

type GroupValue = {
  active: ActiveDrag | null
  overZone: string | null
  overIndex: number
  dropState: DropState
  setZoneIds: (zoneId: string, ids: string[]) => void
  registerContainer: (zoneId: string, el: HTMLElement | null) => void
  registerItem: (zoneId: string, id: string, el: HTMLElement | null) => void
  begin: (zoneId: string, id: string, e: ReactPointerEvent) => void
  itemState: (
    zoneId: string,
    id: string,
  ) => { transform: string; hidden: boolean; animate: boolean }
}
const GroupCtx = createContext<GroupValue | null>(null)
const ZoneIdCtx = createContext<string | null>(null)

export type DragGroupProps = {
  /** Commit the move: relocate `activeId` into `toZone` at `toIndex` (index among that zone's items, active removed). */
  onCommit: (activeId: string, toZone: string, toIndex: number) => void
  /** Render the lifted card's content for the portal overlay. */
  renderOverlay?: (activeId: string) => ReactNode
  children: ReactNode
}

export function DragGroup({
  onCommit,
  renderOverlay,
  children,
}: DragGroupProps): React.JSX.Element {
  const feel = useFeel()
  const feelRef = useRef(feel)
  feelRef.current = feel
  const onCommitRef = useRef(onCommit)
  onCommitRef.current = onCommit

  const zones = useRef(new Map<string, ZoneReg>())
  const frozen = useRef(new Map<string, Box[]>()) // per-zone rects, measured once on first entry

  const [active, setActive] = useState<ActiveDrag | null>(null)
  const [overZone, setOverZone] = useState<string | null>(null)
  const [overIndex, setOverIndex] = useState(-1)
  const [delta, setDelta] = useState({ x: 0, y: 0 })
  const [dropState, setDropState] = useState<DropState>('idle')
  const [dropTarget, setDropTarget] = useState<{ x: number; y: number } | null>(null)

  const drag = useRef({
    id: '',
    zone: '',
    pid: -1,
    el: null as HTMLElement | null,
    rect: null as Box | null,
    startX: 0,
    startY: 0,
    active: false,
    srcIdx: -1,
    pitch: 0,
    overZone: '',
    overIndex: -1,
    handlers: null as null | {
      move: (e: PointerEvent) => void
      up: () => void
      cancel: () => void
    },
  })

  const commitRef = useRef<(() => void) | null>(null) // armed on drop; fired by overlay transitionend or fallback
  const timerRef = useRef<number | null>(null) // fallback-commit timer, kept so it can be cancelled

  const ensure = (zoneId: string): ZoneReg => {
    let z = zones.current.get(zoneId)
    if (!z) {
      z = { ids: [], els: new Map(), container: null }
      zones.current.set(zoneId, z)
    }
    return z
  }
  const setZoneIds = (zoneId: string, ids: string[]): void => {
    ensure(zoneId).ids = ids
  }
  const registerContainer = (zoneId: string, el: HTMLElement | null): void => {
    ensure(zoneId).container = el
  }
  const registerItem = (zoneId: string, id: string, el: HTMLElement | null): void => {
    const z = ensure(zoneId)
    if (el) z.els.set(id, el)
    else z.els.delete(id)
  }

  // Measure a zone's items once, before any shift transforms are applied (so rects are clean).
  const measure = (zoneId: string): Box[] => {
    const z = zones.current.get(zoneId)
    if (!z) return []
    const out: Box[] = []
    for (const id of z.ids) {
      const el = z.els.get(id)
      if (!el) continue
      out.push(toBox(el))
    }
    return out
  }

  const zoneAt = (x: number, y: number): string | null => {
    for (const [zid, z] of zones.current) {
      const el = z.container
      if (!el) continue
      const r = el.getBoundingClientRect()
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return zid
    }
    return null
  }

  // Insertion index in a zone by pointer Y: count non-active items whose centre is above the
  // pointer. Uses the FROZEN rects (measured before shift-transforms) — never live rects, which
  // are transform-contaminated mid-drag — matching the single-zone engine's collision model.
  const indexAt = (zoneId: string, y: number): number => {
    const rects = frozen.current.get(zoneId)
    if (!rects) return 0
    const skip = zoneId === drag.current.zone ? drag.current.srcIdx : -1
    let idx = 0
    rects.forEach((b, i) => {
      if (i === skip) return
      if (y > b.cy) idx++
    })
    return idx
  }

  const onMove = (e: PointerEvent): void => {
    const d = drag.current
    const dx = e.clientX - d.startX
    const dy = e.clientY - d.startY
    if (!d.active) {
      if (Math.hypot(dx, dy) < ACTIVATION) return
      const rects = measure(d.zone)
      const z = zones.current.get(d.zone)
      const srcIdx = z ? z.ids.indexOf(d.id) : -1
      const rect = srcIdx >= 0 ? rects[srcIdx] : undefined
      if (!rect) {
        detach()
        return
      }
      frozen.current.set(d.zone, rects)
      d.active = true
      d.rect = rect
      d.srcIdx = srcIdx
      d.pitch = rects.length > 1 ? Math.abs(rects[1].top - rects[0].top) : rect.height + 8
      d.overZone = d.zone
      d.overIndex = srcIdx
      setActive({ id: d.id, zone: d.zone, srcIdx, pitch: d.pitch, rect })
      setDropState('dragging')
    }
    const zid = zoneAt(e.clientX, e.clientY) ?? d.overZone
    if (zid && !frozen.current.has(zid)) frozen.current.set(zid, measure(zid))
    const idx = zid ? indexAt(zid, e.clientY) : d.overIndex
    d.overZone = zid
    d.overIndex = idx
    setDelta({ x: dx, y: dy })
    setOverZone(zid)
    setOverIndex(idx)
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
    frozen.current.clear()
    setActive(null)
    setOverZone(null)
    setOverIndex(-1)
    setDelta({ x: 0, y: 0 })
    setDropState('idle')
    setDropTarget(null)
  }

  // Arm the commit: run `fn` once, fired by the overlay's fly-to-slot transitionend (preferred) or
  // a fallback timer (covers the no-transition case). Mirrors the single-zone settle.
  const arm = (fn: () => void): void => {
    let done = false
    const once = (): void => {
      if (done) return
      done = true
      commitRef.current = null
      if (timerRef.current != null) {
        clearTimeout(timerRef.current)
        timerRef.current = null
      }
      fn()
    }
    commitRef.current = once
    timerRef.current = window.setTimeout(once, feelRef.current.duration + SETTLE_FALLBACK)
  }

  // Where the lifted card lands in the over-zone. After the move the items (incl. the inserted
  // card) sit contiguously from the zone's first slot, one pitch apart — so the card at non-active
  // index `idx` lands at firstSlotTop + idx*pitch. (Indexing the filtered frozen array directly is
  // off-by-one for within-zone trailing drops, because the source close-shift isn't accounted for.)
  const targetXY = (zoneId: string, idx: number): { x: number; y: number } => {
    const rects = frozen.current.get(zoneId) ?? []
    if (rects.length === 0) {
      const c = zones.current.get(zoneId)?.container?.getBoundingClientRect()
      return { x: c ? c.left + 10 : 0, y: c ? c.top + 10 : 0 }
    }
    return { x: rects[0].left, y: rects[0].top + idx * drag.current.pitch }
  }

  const onUp = (): void => {
    detach()
    const d = drag.current
    if (!d.active || !d.rect) return
    const toZone = d.overZone
    const toIndex = d.overIndex
    const rect = d.rect
    const tgt = toZone ? targetXY(toZone, toIndex) : { x: rect.left, y: rect.top }
    setDropState('dropping')
    setDropTarget({ x: tgt.x - rect.left, y: tgt.y - rect.top }) // fly the overlay to the landing slot
    arm(() => {
      if (toZone) onCommitRef.current(d.id, toZone, toIndex)
      reset()
    })
  }

  const onCancel = (): void => {
    detach()
    if (!drag.current.active) return
    setDropState('dropping')
    setDropTarget({ x: 0, y: 0 }) // fly the overlay back to the source slot
    arm(reset)
  }

  const begin = (zoneId: string, id: string, e: ReactPointerEvent): void => {
    if (e.button !== 0 || !e.isPrimary) return
    if (drag.current.active || commitRef.current) return // a drag is in progress or a drop is still committing
    const z = zones.current.get(zoneId)
    const el = z?.els.get(id) ?? null
    if (!el) return
    const handlers = { move: onMove, up: onUp, cancel: onCancel }
    drag.current = {
      id,
      zone: zoneId,
      pid: e.pointerId,
      el,
      rect: null,
      startX: e.clientX,
      startY: e.clientY,
      active: false,
      srcIdx: -1,
      pitch: 0,
      overZone: '',
      overIndex: -1,
      handlers,
    }
    try {
      el.setPointerCapture(e.pointerId)
    } catch {
      // capture unavailable
    }
    el.addEventListener('pointermove', handlers.move)
    el.addEventListener('pointerup', handlers.up)
    el.addEventListener('pointercancel', handlers.cancel)
  }

  const itemState = (
    zoneId: string,
    id: string,
  ): { transform: string; hidden: boolean; animate: boolean } => {
    if (!active) return { transform: 'translate3d(0,0,0)', hidden: false, animate: false }
    if (id === active.id) return { transform: 'translate3d(0,0,0)', hidden: true, animate: false }
    const z = zones.current.get(zoneId)
    const rects = frozen.current.get(zoneId)
    if (!z || !rects)
      return { transform: 'translate3d(0,0,0)', hidden: false, animate: dropState !== 'idle' }
    const oi = z.ids.indexOf(id)
    if (oi === -1)
      return { transform: 'translate3d(0,0,0)', hidden: false, animate: dropState !== 'idle' }
    let dy = 0
    let na = oi
    if (zoneId === active.zone && oi > active.srcIdx) {
      dy -= active.pitch
      na = oi - 1
    }
    if (zoneId === overZone && na >= overIndex) dy += active.pitch
    return {
      transform: `translate3d(0, ${px(dy)}, 0)`,
      hidden: false,
      animate: dropState !== 'idle',
    }
  }

  // Unmount mid-drag (navigate away while dragging): pull the captured-pointer listeners and
  // cancel any pending commit timer so neither dangles on a torn-down tree.
  useEffect(
    () => () => {
      detach()
      if (timerRef.current != null) clearTimeout(timerRef.current)
    },
    [],
  )

  const value = useMemo<GroupValue>(
    () => ({
      active,
      overZone,
      overIndex,
      dropState,
      setZoneIds,
      registerContainer,
      registerItem,
      begin,
      itemState,
    }),
    // registration/begin/itemState read refs + current state via closure; identity churn is fine.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [active, overZone, overIndex, dropState],
  )

  const overlayStyle: CSSProperties | null =
    active && dropState !== 'idle'
      ? {
          position: 'fixed',
          left: active.rect.left,
          top: active.rect.top,
          width: active.rect.width,
          height: active.rect.height,
          transform:
            dropState === 'dropping' && dropTarget
              ? `translate3d(${px(dropTarget.x)}, ${px(dropTarget.y)}, 0)`
              : `translate3d(${px(delta.x)}, ${px(delta.y)}, 0)`,
          transition:
            dropState === 'dropping' ? `transform ${feel.duration}ms ${feel.easing}` : 'none',
          pointerEvents: 'none',
          zIndex: 1000,
        }
      : null

  return (
    <GroupCtx.Provider value={value}>
      {children}
      {overlayStyle &&
        active &&
        createPortal(
          <div
            style={overlayStyle}
            onTransitionEnd={(e) => {
              if (e.propertyName === 'transform' && dropState === 'dropping') commitRef.current?.()
            }}
          >
            {renderOverlay?.(active.id)}
          </div>,
          document.body,
        )}
    </GroupCtx.Provider>
  )
}

export function GroupZone({
  id,
  items,
  className,
  children,
}: {
  id: string
  items: string[]
  className?: string
  children: ReactNode
}): React.JSX.Element {
  const group = useContext(GroupCtx)
  if (!group) throw new Error('A grouped SortableZone must be inside a <DragGroup>')
  group.setZoneIds(id, items)
  return (
    <ZoneIdCtx.Provider value={id}>
      <ul ref={(el) => group.registerContainer(id, el)} className={className}>
        {children}
      </ul>
    </ZoneIdCtx.Provider>
  )
}

export function useGroupedDragItem(id: string): DragItem {
  const group = useContext(GroupCtx)
  const zoneId = useContext(ZoneIdCtx)
  if (!group || zoneId == null)
    throw new Error('useGroupedDragItem must be used inside a grouped <SortableZone>')
  const { transform, hidden, animate } = group.itemState(zoneId, id)
  const feel = useFeel()
  const isDragging = group.active?.id === id
  return {
    setNodeRef: (el) => group.registerItem(zoneId, id, el),
    style: {
      transform,
      transition: animate ? `transform ${feel.duration}ms ${feel.easing}` : 'none',
      visibility: hidden ? 'hidden' : undefined,
      position: 'relative',
      touchAction: 'none',
    },
    handle: {
      onPointerDown: (e: ReactPointerEvent) => group.begin(zoneId, id, e),
      'aria-roledescription': 'sortable',
      'aria-pressed': isDragging || undefined,
    },
    isDragging,
  }
}
