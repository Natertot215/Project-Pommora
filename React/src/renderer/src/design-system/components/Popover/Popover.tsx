import { useEffect, type ReactNode, type RefObject } from 'react'
import { GlassSurface } from '../../materials'
import * as s from './popover.css'

/**
 * A glass panel anchored below its trigger. Presentational only — render it inside
 * a `position: relative` container and toggle it with open state; pair with
 * `useDismiss` on that container for outside-click / Esc handling.
 */
export function Popover({
  align = 'right',
  children
}: {
  align?: 'left' | 'right'
  children: ReactNode
}): React.JSX.Element {
  return (
    <div className={`${s.anchor} ${align === 'right' ? s.alignRight : s.alignLeft}`}>
      <GlassSurface className={s.panel}>{children}</GlassSurface>
    </div>
  )
}

/**
 * Close on a pointerdown outside `ref` (its element + descendants) or on Escape,
 * while `active`. Scoping to the trigger's container means clicking the trigger
 * again doesn't fire dismiss, so the trigger's own toggle stays clean.
 */
export function useDismiss(
  ref: RefObject<HTMLElement | null>,
  onClose: () => void,
  active: boolean
): void {
  useEffect(() => {
    if (!active) return
    const onDown = (e: PointerEvent): void => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose()
    }
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') onClose()
    }
    document.addEventListener('pointerdown', onDown, true)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onDown, true)
      document.removeEventListener('keydown', onKey)
    }
  }, [ref, onClose, active])
}
