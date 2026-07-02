import type { CSSProperties } from 'react'

// Shared vocabulary for the drag engine — the types, tuning constants, and pure helpers used by
// BOTH the single-zone engine (`engine.tsx`) and the cross-list engine (`group.tsx`). The two
// engines model genuinely different interactions (in-place transform vs portal overlay), so their
// drag-state and commit machinery stay separate; only these shared primitives are hoisted here.

export type Box = { left: number; top: number; width: number; height: number; cx: number; cy: number }
export type DropState = 'idle' | 'dragging' | 'dropping' | 'pending'
export type Modifier = (t: { x: number; y: number }, ctx: { activeRect: Box; bounds: Box | null }) => { x: number; y: number }

export type DragNotify = {
  onDragStart?: (e: { activeId: string }) => void
  onDragOver?: (e: { activeId: string; overId: string | null }) => void
  onDragEnd?: (e: { activeId: string; overId: string | null }) => void
  onDragCancel?: (e: { activeId: string }) => void
}

export type DragItem = {
  setNodeRef: (el: HTMLElement | null) => void
  style: CSSProperties
  handle: Record<string, unknown>
  isDragging: boolean
}

export const ACTIVATION = 5 // px the pointer must travel before a drag starts (vs. a click)
export const DROP_LINE_INSET = 2 // px an insertion line is pulled in from its surface's edges
export const HYSTERESIS = 6 // px a new candidate must beat the current `over` by, to switch — kills flicker
export const SETTLE_FALLBACK = 80 // ms slack past the transition for the commit fallback (paint-start delay)

/** Measure an element into a Box (with centre), in viewport coordinates. */
export function toBox(el: HTMLElement): Box {
  const r = el.getBoundingClientRect()
  return { left: r.left, top: r.top, width: r.width, height: r.height, cx: r.left + r.width / 2, cy: r.top + r.height / 2 }
}

/** Integer-ish px for transforms — `.toFixed(1)` keeps sub-pixel sharpness on Retina without blur. */
export const px = (n: number): string => `${n.toFixed(1)}px`
