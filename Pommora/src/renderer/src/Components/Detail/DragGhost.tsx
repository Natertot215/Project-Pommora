import { createPortal } from 'react-dom'
import type { ReactNode } from 'react'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens/typography.css'

/**
 * The floating drag chip every list-drag shares (the table bands' recipe: fixed, z-1000, frosted,
 * label-primary) — portaled to body so it paints ABOVE any pane frost. Without it, a drag's only
 * visual is the source row dimmed in place, which melts into the glass and reads as "dragging behind
 * the pane."
 */
export function DragGhost({
  x,
  y,
  label,
}: {
  x: number | null
  y: number | null
  label: ReactNode
}): ReactNode {
  if (x === null || y === null || label == null || label === '') return null
  return createPortal(
    <div
      aria-hidden
      className={cx('band-drag-ghost', text.body.standard)}
      style={{ top: y, left: x }}
    >
      {label}
    </div>,
    document.body,
  )
}
