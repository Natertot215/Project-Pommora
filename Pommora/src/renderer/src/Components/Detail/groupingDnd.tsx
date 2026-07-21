// The Grouping pane's list drag — the table's band gesture rehosted over pane rows. The pure model
// is SHARED (bandDndModel: slots, nest cycle-guard, order math); only the pointer wiring and the
// insertion line live here. paneDnd doesn't fit: its two-region assigned/all vocabulary has no
// parent/nest concept, and the hierarchy list needs reparent drops (F-4).
import { useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from 'react'
import { usePointerGesture } from '@renderer/design-system/interactions/gesture'
import { suppressNextClick } from '@renderer/design-system/interactions/shared'
import type { Band, BandIndex, BandSlot } from '../../Detail/Views/Table/bandDndModel'
import { bandSlot, buildBandIndex, canNest } from '../../Detail/Views/Table/bandDndModel'

export interface GroupingDrop {
  kind: 'reorder' | 'reparent'
  targetParentId: string | null
  beforeId: string | null
}

/** Wrap the pane's draggable list; rows register through the returned context-free API (the list is
 *  small and single-instance, so props beat a context). `bands` is the VISIBLE flat row list. */
export function useGroupingListDrag({
  bands,
  nestable,
  onDrop,
}: {
  bands: Band[]
  nestable: boolean
  onDrop: (draggedId: string, drop: GroupingDrop) => void
}): {
  containerRef: (el: HTMLDivElement | null) => void
  rowRef: (id: string) => (el: HTMLElement | null) => void
  rowHandle: (id: string) => { onPointerDown: (e: ReactPointerEvent) => void }
  draggingId: string | null
  line: { y: number } | null
  nestTarget: string | null
  /** The floating drag-chip coords (DragGhost) — null until the gesture activates. */
  ghost: { x: number; y: number } | null
} {
  const container = useRef<HTMLDivElement | null>(null)
  const els = useRef(new Map<string, HTMLElement>())
  const index = useRef<BandIndex | null>(null)
  const boxTop = useRef(0)
  const endY = useRef(0)
  const beginGesture = usePointerGesture()
  const live = useRef<BandSlot | null>(null)
  const cfg = useRef({ bands, nestable, onDrop })
  cfg.current = { bands, nestable, onDrop }
  const [draggingId, setDraggingId] = useState<string | null>(null)
  const [line, setLine] = useState<{ y: number } | null>(null)
  const [nestTarget, setNestTarget] = useState<string | null>(null)
  const [ghost, setGhost] = useState<{ x: number; y: number } | null>(null)

  const reset = (): void => {
    live.current = null
    index.current = null
    setDraggingId(null)
    setLine(null)
    setNestTarget(null)
    setGhost(null)
  }

  return {
    containerRef: (el) => {
      container.current = el
    },
    rowRef: (id) => (el) => {
      if (el) els.current.set(id, el)
      else els.current.delete(id)
    },
    rowHandle: (id) => ({
      onPointerDown: (e) => {
        const anchor = els.current.get(id) ?? (e.currentTarget as HTMLElement)
        beginGesture({
          el: anchor,
          event: e,
          capture: false,
          onActivate: () => {
            const measured = cfg.current.bands.flatMap((b) => {
              const el = els.current.get(b.id)
              if (!el) return []
              const r = el.getBoundingClientRect()
              return [{ id: b.id, top: r.top, bottom: r.bottom, mid: r.top + r.height / 2 }]
            })
            index.current = buildBandIndex(cfg.current.bands, measured)
            const box = container.current?.getBoundingClientRect()
            boxTop.current = box?.top ?? 0
            endY.current = measured.at(-1)?.bottom ?? box?.bottom ?? 0
            setDraggingId(id)
            return true
          },
          onDragMove: (ev) => {
            setGhost({ x: ev.clientX + 12, y: ev.clientY + 8 })
            const idx = index.current
            if (!idx) return
            let slot = bandSlot(idx, ev.clientY, id, endY.current)
            // A non-nestable list (the flat Custom chips / flat sub-grouped sets) demotes a nest
            // slot to an after-slot at the same line; an illegal nest dies.
            if (slot?.nestInto) {
              if (!cfg.current.nestable || !canNest(id, slot.nestInto, cfg.current.bands))
                slot = null
            }
            live.current = slot
            setLine(slot && !slot.nestInto ? { y: slot.lineY - boxTop.current } : null)
            setNestTarget(slot?.nestInto ?? null)
          },
          onDrop: () => {
            const slot = live.current
            if (slot) {
              suppressNextClick() // the release must not also fire the row's disclosure toggle
              cfg.current.onDrop(id, {
                kind: slot.nestInto
                  ? 'reparent'
                  : slot.impliedParentId === cfg.current.bands.find((b) => b.id === id)?.parentId
                    ? 'reorder'
                    : 'reparent',
                targetParentId: slot.nestInto ?? slot.impliedParentId,
                beforeId: slot.beforeId,
              })
            }
            reset()
          },
          onAbort: reset,
        })
      },
    }),
    draggingId,
    line,
    nestTarget,
    ghost,
  }
}

export function GroupingDropLine({ line }: { line: { y: number } | null }): ReactNode {
  if (!line) return null
  return <div className="grouping-drop-line" aria-hidden style={{ top: line.y }} />
}
