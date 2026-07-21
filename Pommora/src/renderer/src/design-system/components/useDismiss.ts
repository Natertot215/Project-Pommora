import { useEffect, type RefObject } from 'react'

/**
 * Close on a pointerdown outside `ref` (its element + descendants) or on Escape,
 * while `active`. Scoping to the trigger's container means clicking the trigger
 * again doesn't fire dismiss, so the trigger's own toggle stays clean.
 */
export function useDismiss(
  ref: RefObject<HTMLElement | null>,
  onClose: () => void,
  active: boolean,
): void {
  useEffect(() => {
    if (!active) return
    const onDown = (e: PointerEvent): void => {
      const target = e.target as Element
      // A portal'd picker (its layer + backdrop) renders OUTSIDE this ref in the DOM, so a plain
      // containment check reads any interaction with it as "outside" and dismisses the host it
      // visually sits within. Spare the marked portal — the picker owns its own dismissal.
      if (ref.current && !ref.current.contains(target) && !target.closest?.('[data-picker-portal]'))
        onClose()
    }
    const onKey = (e: KeyboardEvent): void => {
      // A marked picker portal owns its own Escape — while one's open, it closes itself and this host
      // stays put (Escape peels one popover at a time, never the pane out from under the picker in it).
      if (e.key === 'Escape' && !document.querySelector('[data-picker-portal]')) onClose()
    }
    document.addEventListener('pointerdown', onDown, true)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onDown, true)
      document.removeEventListener('keydown', onKey)
    }
  }, [ref, onClose, active])
}
