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
import { findScroller, startAutoScroll } from './autoscroll'
import { beginDragDisclose, endDragDisclose } from './dragDisclose'
import {
  ACTIVATION,
  HYSTERESIS,
  SETTLE_FALLBACK,
  px,
  suppressNextClick,
  toBox,
  type Box,
  type DragItem,
  type DropState,
} from './shared'

// A press that begins on an interactive control needs more travel before it becomes a drag, so a
// small tap-wobble opens the control (picker/checkbox) instead of lifting the card and eating the click.
const INTERACTIVE_ACTIVATION = 12

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

// Group frozen rects into visual ROWS by vertical-span overlap (cards top-align with unequal heights,
// so a per-card centre or bottom splits one row and makes the insertion index flip-flop). Each row
// carries a SHARED band [top, bottom] (min top, max bottom) so the whole row reads as one row.
function rowsOf(
  rects: Box[],
  skip: number,
): Array<{ top: number; bottom: number; items: Array<{ i: number; cx: number }> }> {
  const items = rects
    .map((b, i) => ({ i, top: b.top, bottom: b.top + b.height, cx: b.cx }))
    .filter((it) => it.i !== skip)
    .sort((a, b) => a.top - b.top || a.cx - b.cx)
  const rows: Array<{ top: number; bottom: number; items: Array<{ i: number; cx: number }> }> = []
  for (const it of items) {
    const row = rows.find((r) => it.top < r.bottom && it.bottom > r.top)
    if (row) {
      row.items.push({ i: it.i, cx: it.cx })
      row.top = Math.min(row.top, it.top)
      row.bottom = Math.max(row.bottom, it.bottom)
    } else rows.push({ top: it.top, bottom: it.bottom, items: [{ i: it.i, cx: it.cx }] })
  }
  for (const r of rows) r.items.sort((a, b) => a.cx - b.cx)
  return rows
}

// The viewport position of grid SLOT `slot`: the measured rect for an existing card, else WALKED
// forward by grid columns from the last card — next column in the same row, wrapping to the next row
// only once the row is full. A linear "below the last card" extrapolation would instead drop a slot
// with open space to its RIGHT onto a new row (a partial row's right-hand drop reading as "below").
function cellAt(
  rects: Box[],
  slot: number,
  pitch: number,
  containerWidth: number,
): { x: number; y: number } {
  if (slot < rects.length) return { x: rects[slot].left, y: rects[slot].top }
  if (rects.length === 0) return { x: 0, y: 0 }
  const lefts = [...new Set(rects.map((r) => Math.round(r.left)))].sort((a, b) => a - b)
  // Column stride from the two closest occupied columns, else the card's own width. The grid keeps
  // empty tracks (auto-fill), so infer the FULL column count from the container width — not from how
  // many cards are present, or a sparse band wraps an append onto a phantom new row below the cards.
  const stride = lefts.length >= 2 ? lefts[1] - lefts[0] : (rects[0]?.width ?? 1) + 1
  const cols = Math.max(
    lefts.length,
    containerWidth > 0 ? Math.round(containerWidth / stride) : 1,
    1,
  )
  const last = rects[rects.length - 1]
  let col = Math.max(0, Math.round((last.left - lefts[0]) / stride))
  let top = last.top
  for (let sInc = rects.length; sInc <= slot; sInc++) {
    col++
    if (col >= cols) {
      col = 0
      top += pitch
    }
  }
  return { x: lefts[0] + col * stride, y: top }
}
const ZoneIdCtx = createContext<string | null>(null)

export type DragGroupProps = {
  /** Commit the move: relocate `activeId` into `toZone` at `toIndex` (index among that zone's items, active removed). */
  onCommit: (activeId: string, toZone: string, toIndex: number) => void
  /** Render the lifted card's content for the portal overlay. */
  renderOverlay?: (activeId: string) => ReactNode
  /** Allow a drag to cross into other zones (default true). False pins it to its source zone — a
   *  within-zone reorder only (a card can't fly to a band that can't receive it). */
  crossZone?: boolean
  children: ReactNode
}

export function DragGroup({
  onCommit,
  renderOverlay,
  crossZone = true,
  children,
}: DragGroupProps): React.JSX.Element {
  const feel = useFeel()
  const feelRef = useRef(feel)
  feelRef.current = feel
  const onCommitRef = useRef(onCommit)
  onCommitRef.current = onCommit
  const crossZoneRef = useRef(crossZone)
  crossZoneRef.current = crossZone

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
    lastX: 0,
    lastY: 0,
    interactive: false,
    idxAnchorX: 0,
    idxAnchorY: 0,
    handlers: null as null | {
      move: (e: PointerEvent) => void
      up: () => void
      cancel: () => void
      scroll: () => void
      blur: () => void
    },
  })

  const commitRef = useRef<(() => void) | null>(null) // armed on drop; fired by overlay transitionend or fallback
  const timerRef = useRef<number | null>(null) // fallback-commit timer, kept so it can be cancelled
  const stopScroll = useRef<(() => void) | null>(null) // this group's auto-scroll loop stopper

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

  // Cached zone container bounds — snapshotted once at activation, refreshed by onScroll, never per
  // pointermove. No band moves mid-drag otherwise, so the cache stays valid and the per-move
  // getBoundingClientRect (a layout read every frame) is gone.
  const bounds = useRef(
    new Map<string, { left: number; right: number; top: number; bottom: number }>(),
  )
  const measureBounds = (): void => {
    bounds.current.clear()
    for (const [zid, z] of zones.current) {
      if (!z.container) continue
      const r = z.container.getBoundingClientRect()
      bounds.current.set(zid, { left: r.left, right: r.right, top: r.top, bottom: r.bottom })
    }
  }
  // Reserve (or release) one row of height on a FOREIGN over-zone so the incoming card's wrapped
  // trailing card grows into real space instead of spilling past the band into the group below. Only
  // ONE zone is padded at a time, toggled SYNCHRONOUSLY on band-entry (never a per-move effect), so a
  // zone is always measured at its natural geometry — the frozen rects can't go stale under it.
  const padded = useRef<string | null>(null)
  const setPad = (zid: string | null): void => {
    if (padded.current === zid) return
    const prev = padded.current && zones.current.get(padded.current)?.container
    if (prev) prev.style.paddingBottom = ''
    const next = zid && zones.current.get(zid)?.container
    if (next) next.style.paddingBottom = `${drag.current.pitch}px`
    padded.current = zid
  }
  const zoneWidth = (zid: string): number => {
    const b = bounds.current.get(zid)
    return b ? b.right - b.left : 0
  }
  // A scroll during the drag moves every band; re-measure bounds AND shift each zone's FROZEN item
  // rects by its container's delta (frozen can't be re-measured live — transforms contaminate it), so
  // zoneAt, indexAt and the placement all stay aligned to what's on screen.
  const onScroll = (): void => {
    for (const [zid, z] of zones.current) {
      if (!z.container) continue
      const r = z.container.getBoundingClientRect()
      const prev = bounds.current.get(zid)
      const f = frozen.current.get(zid)
      if (prev && f && (r.top !== prev.top || r.left !== prev.left)) {
        const shx = r.left - prev.left
        const shy = r.top - prev.top
        frozen.current.set(
          zid,
          f.map((b) => ({
            ...b,
            left: b.left + shx,
            top: b.top + shy,
            cx: b.cx + shx,
            cy: b.cy + shy,
          })),
        )
      }
      bounds.current.set(zid, { left: r.left, right: r.right, top: r.top, bottom: r.bottom })
    }
  }
  const zoneAt = (x: number, y: number): string | null => {
    for (const [zid, r] of bounds.current)
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return zid
    return null
  }

  // Insertion index in a zone by pointer Y: count non-active items whose centre is above the
  // pointer. Uses the FROZEN rects (measured before shift-transforms) — never live rects, which
  // are transform-contaminated mid-drag — matching the single-zone engine's collision model.
  const indexAt = (zoneId: string, x: number, y: number): number => {
    const rects = frozen.current.get(zoneId)
    if (!rects) return 0
    const skip = zoneId === drag.current.zone ? drag.current.srcIdx : -1
    // Insertion index in NON-active space, over SHARED row bands: rows entirely above the pointer
    // count whole; in the pointer's own row, count the cards left of it (x past centre); below all
    // rows, everything counts. One row band per visual row means a vertical wobble never re-buckets a
    // card, so the index holds steady across a row (the coarse per-move flip-flop is gone).
    const rows = rowsOf(rects, skip)
    let idx = 0
    for (const row of rows) {
      if (y >= row.bottom) {
        idx += row.items.length
        continue
      }
      if (y < row.top) break
      // A single-card row has no horizontal neighbour, so a lone card / single column orders by the
      // row's vertical midpoint; a real multi-card row orders by x.
      if (row.items.length === 1) idx += y > (row.top + row.bottom) / 2 ? 1 : 0
      else for (const it of row.items) if (x > it.cx) idx++
      return idx
    }
    return idx
  }

  // Zone/index tracking for a viewport point — shared by pointermove and the auto-scroll loop
  // (content moves under a held-still pointer, so scrolled frames must re-track too).
  const trackAt = (cx: number, cy: number): void => {
    const d = drag.current
    const dx = cx - d.startX
    const dy = cy - d.startY
    // crossZone off → the drag is pinned to its source zone (within-zone reorder only).
    const zid = crossZoneRef.current ? (zoneAt(cx, cy) ?? d.overZone) : d.zone
    if (zid !== d.overZone) {
      // Band-entry: reserve the wrap row on a foreign destination (release it from the old one) and
      // refresh bounds — synchronously, so no zone is measured while another is padded.
      setPad(zid && zid !== d.zone ? zid : null)
      measureBounds()
    }
    if (zid && !frozen.current.has(zid)) frozen.current.set(zid, measure(zid))
    let idx = zid ? indexAt(zid, cx, cy) : d.overIndex
    // Hysteresis: hold the current index until the pointer travels HYSTERESIS from where the index
    // last changed. A boundary wobble (near a card's centre) can't flip it back and forth per frame.
    if (zid === d.overZone && idx !== d.overIndex) {
      if (Math.hypot(cx - d.idxAnchorX, cy - d.idxAnchorY) < HYSTERESIS) idx = d.overIndex
      else {
        d.idxAnchorX = cx
        d.idxAnchorY = cy
      }
    } else if (zid !== d.overZone) {
      d.idxAnchorX = cx
      d.idxAnchorY = cy
    }
    if (zid === d.overZone && idx === d.overIndex) {
      setDelta({ x: dx, y: dy })
      return
    }
    d.overZone = zid
    d.overIndex = idx
    setDelta({ x: dx, y: dy })
    setOverZone(zid)
    setOverIndex(idx)
  }

  const onMove = (e: PointerEvent): void => {
    const d = drag.current
    // No pointer capture, so a release OUTSIDE the Electron window delivers no pointerup; the first
    // move back in reports no button pressed — cancel the stranded drag rather than leave the ghost
    // glued to the pointer (whose next click would otherwise commit the card wherever it lands).
    if (d.active && e.buttons === 0) return onCancel()
    if (!d.active) {
      const dx = e.clientX - d.startX
      const dy = e.clientY - d.startY
      if (Math.hypot(dx, dy) < (d.interactive ? INTERACTIVE_ACTIVATION : ACTIVATION)) return
      measureBounds() // snapshot zone bounds once, now that nothing has shifted
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
      // Row pitch = the smallest positive vertical step to another item (row-to-row in a grid; item-
      // to-item in a list). rects[1]-rects[0] is ~0 in a grid — its first two items share a row.
      const vgaps = rects.map((b) => b.top - rect.top).filter((d) => d > 1)
      d.pitch = vgaps.length ? Math.min(...vgaps) : rect.height + 8
      d.overZone = d.zone
      d.overIndex = srcIdx
      setActive({ id: d.id, zone: d.zone, srcIdx, pitch: d.pitch, rect })
      setDropState('dragging')
      // Seed the over-state so the landing preview shows at the origin slot immediately — otherwise
      // holding still right after pickup closes the gap with no target box until the pointer moves.
      setOverZone(d.zone)
      setOverIndex(srcIdx)
      // Edge auto-scroll, exactly as the single-zone engine wires it. Each scrolled frame first
      // re-shifts the frozen rects + bounds (onScroll — the capture-phase event may lag the
      // programmatic scroll), then re-tracks the held-still pointer over the moved content.
      const scroller = findScroller(d.el, 'xy')
      if (scroller) {
        stopScroll.current = startAutoScroll({
          getPoint: () => ({ x: drag.current.lastX, y: drag.current.lastY }),
          scroller,
          dragEl: d.el,
          axis: 'xy',
          onScrolled: onScrollTracked,
        })
      }
    }
    d.lastX = e.clientX
    d.lastY = e.clientY
    trackAt(e.clientX, e.clientY)
  }

  const detach = (): void => {
    stopScroll.current?.()
    stopScroll.current = null
    const d = drag.current
    if (d.handlers) {
      window.removeEventListener('pointermove', d.handlers.move)
      window.removeEventListener('pointerup', d.handlers.up)
      window.removeEventListener('pointercancel', d.handlers.cancel)
      window.removeEventListener('scroll', d.handlers.scroll, { capture: true })
      window.removeEventListener('blur', d.handlers.blur)
      endDragDisclose()
    }
    d.handlers = null
  }

  const reset = (): void => {
    setPad(null)
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
    const slot = Math.max(0, Math.min(idx, rects.length))
    return cellAt(rects, slot, drag.current.pitch, zoneWidth(zoneId))
  }

  const onUp = (): void => {
    detach()
    const d = drag.current
    if (!d.active || !d.rect) return
    // The GESTURE is over — only the settle animation remains. Cleared here (not in reset) so a
    // press during the fly can pass begin's live-drag guard and fast-forward the armed commit.
    d.active = false
    // Swallow the click synthesized by this pointerup so the drop doesn't also fire a card's
    // open/navigate (the drop can land the pointer over a DIFFERENT card than the one lifted).
    suppressNextClick()
    const rect = d.rect
    // The TRUE zone under the drop point — not d.overZone, which sticks to the last zone crossed. A
    // drop over no zone (an inter-band gap, an empty/collapsed band's header) cancels and flies home;
    // committing to the stale zone would silently reassign to the WRONG band.
    const dropZone = crossZoneRef.current ? zoneAt(d.lastX, d.lastY) : d.zone
    if (!dropZone) {
      setDropState('dropping')
      setDropTarget({ x: 0, y: 0 })
      arm(reset)
      return
    }
    if (!frozen.current.has(dropZone)) frozen.current.set(dropZone, measure(dropZone))
    // Honor the hysteresis-smoothed index when the drop lands in the tracked over-zone — the card
    // commits to the slot the preview showed. A raw recompute would ignore the dead-band and land one
    // slot off the box; only a drop into a DIFFERENT zone than tracked recomputes.
    const toIndex = dropZone === d.overZone ? d.overIndex : indexAt(dropZone, d.lastX, d.lastY)
    const tgt = targetXY(dropZone, toIndex)
    setDropState('dropping')
    setDropTarget({ x: tgt.x - rect.left, y: tgt.y - rect.top }) // fly the overlay to the landing slot
    arm(() => {
      onCommitRef.current(d.id, dropZone, toIndex)
      reset()
    })
  }

  const onCancel = (): void => {
    detach()
    if (!drag.current.active) return
    drag.current.active = false // gesture over; only the fly-home settle remains
    setDropState('dropping')
    setDropTarget({ x: 0, y: 0 }) // fly the overlay back to the source slot
    arm(reset)
  }

  // The window losing focus mid-drag (or mid-press) is the case the buttons guard can't catch — the
  // pointer may never come back. Cancel a live drag; just detach a pending (pre-activation) one.
  const onWindowBlur = (): void => {
    if (drag.current.active) onCancel()
    else if (drag.current.handlers) detach()
  }

  // Any scroll during the drag — wheel/trackpad or the auto-scroll loop — first shifts the frozen
  // geometry, then re-tracks the held-still pointer so the drop preview follows the moved content.
  const onScrollTracked = (): void => {
    onScroll()
    if (drag.current.active) trackAt(drag.current.lastX, drag.current.lastY)
  }

  const begin = (zoneId: string, id: string, e: ReactPointerEvent): void => {
    if (e.button !== 0 || !e.isPrimary) return
    if (drag.current.active) return // a live drag owns the pointer
    // A press during a drop's settle animation fast-forwards that commit instead of being refused —
    // grabbing the next card immediately then feels responsive, not dead for ~300ms.
    if (commitRef.current) commitRef.current()
    const z = zones.current.get(zoneId)
    const el = z?.els.get(id) ?? null
    if (!el) return
    // A press starting on an interactive control raises the drag-activation slop (see onMove) so a
    // tap-wobble opens the control rather than lifting the card. Cards mark those with data-drag-slop.
    const interactive = !!(e.target as Element)?.closest?.(
      '[data-drag-slop], button, input, textarea, select, a[href], [contenteditable]',
    )
    const handlers = {
      move: onMove,
      up: onUp,
      cancel: onCancel,
      scroll: onScrollTracked,
      blur: onWindowBlur,
    }
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
      lastX: e.clientX,
      lastY: e.clientY,
      interactive,
      idxAnchorX: e.clientX,
      idxAnchorY: e.clientY,
      handlers,
    }
    // Window listeners, NOT pointer capture: capture would retarget a no-move tap's click onto the
    // handle, stealing an inner clickable's click. Without it the whole surface is a drag handle AND
    // every inner click survives — a move past activation drags, a tap clicks. suppressNextClick eats
    // the post-drag click.
    window.addEventListener('pointermove', handlers.move)
    window.addEventListener('pointerup', handlers.up)
    window.addEventListener('pointercancel', handlers.cancel)
    window.addEventListener('scroll', handlers.scroll, { capture: true, passive: true })
    window.addEventListener('blur', handlers.blur)
    beginDragDisclose(measureBounds)
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
    if (oi === -1 || !rects[oi])
      return { transform: 'translate3d(0,0,0)', hidden: false, animate: dropState !== 'idle' }
    // The resting arrangement: this zone's items minus the lifted one, with it re-inserted at the hover
    // index when this IS the over-zone (source zone closes the gap; over zone — within OR across bands —
    // opens one so the adjacent cards part to show the landing). Each item targets a MEASURED slot rect,
    // so a 2-D grid reflows by real positions; a foreign over-zone reserves one wrap row (setPad) so the
    // trailing card that wraps grows into real space instead of spilling into the group below.
    const order = z.ids.filter((x) => x !== active.id)
    if (zoneId === overZone)
      order.splice(Math.max(0, Math.min(overIndex, order.length)), 0, active.id)
    const slot = order.indexOf(id)
    const base = rects[oi]
    const tgt = cellAt(rects, slot, active.pitch, zoneWidth(zoneId))
    return {
      transform: `translate3d(${px(tgt.x - base.left)}, ${px(tgt.y - base.top)}, 0)`,
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

  // The drop-location preview (SurfacePM's spm-placement idiom) — the accent-washed slot the lifted
  // card will land in, within OR across bands. It rides the live over-zone/index, so it IS the future
  // slot the reflow's gap opens for. Shown only while dragging (the overlay flies here on drop).
  const placeSlot =
    active && dropState === 'dragging' && overZone ? targetXY(overZone, overIndex) : null

  return (
    <GroupCtx.Provider value={value}>
      {children}
      {placeSlot &&
        active &&
        createPortal(
          <div
            style={{
              position: 'fixed',
              left: placeSlot.x,
              top: placeSlot.y,
              width: active.rect.width,
              height: active.rect.height,
              borderRadius: 12,
              background: 'color-mix(in srgb, var(--accent) var(--tint-secondary), transparent)',
              pointerEvents: 'none',
              zIndex: 999,
            }}
          />,
          document.body,
        )}
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
