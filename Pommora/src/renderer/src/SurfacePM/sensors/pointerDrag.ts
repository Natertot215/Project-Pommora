// The SurfacePM pointer sensor — the engine's capture pattern (Pointer Events +
// setPointerCapture, rAF-coalesced moves, Esc abort) reduced to a one-shot drag
// primitive the surface's dividers and tile handles share.

export interface PointerDragHandlers {
  /** Fires rAF-coalesced with the cumulative delta from the drag origin. */
  onMove: (dx: number, dy: number, e: PointerEvent) => void
  /** Fires once: true = commit, false = aborted (Esc / pointercancel). */
  onEnd: (commit: boolean) => void
  /** Pixels of travel before the drag arms (a plain click never arms). */
  threshold?: number
}

export function startPointerDrag(e: React.PointerEvent, handlers: PointerDragHandlers): void {
  const el = e.currentTarget as HTMLElement
  const originX = e.clientX
  const originY = e.clientY
  const threshold = handlers.threshold ?? 3
  let armed = threshold === 0
  let raf = 0
  let lastX = originX
  let lastY = originY
  let done = false

  const flush = (): void => {
    raf = 0
    handlers.onMove(lastX - originX, lastY - originY, lastEvent as PointerEvent)
  }
  let lastEvent: PointerEvent | null = null

  const finish = (commit: boolean): void => {
    if (done) return
    done = true
    if (raf) cancelAnimationFrame(raf)
    el.removeEventListener('pointermove', onMove)
    el.removeEventListener('pointerup', onUp)
    el.removeEventListener('pointercancel', onCancel)
    window.removeEventListener('keydown', onKey, true)
    if (el.hasPointerCapture(e.pointerId)) el.releasePointerCapture(e.pointerId)
    handlers.onEnd(commit)
  }

  const onMove = (ev: PointerEvent): void => {
    if (!armed) {
      if (Math.hypot(ev.clientX - originX, ev.clientY - originY) < threshold) return
      armed = true
    }
    lastX = ev.clientX
    lastY = ev.clientY
    lastEvent = ev
    if (!raf) raf = requestAnimationFrame(flush)
  }
  const onUp = (): void => finish(armed)
  const onCancel = (): void => finish(false)
  const onKey = (ev: KeyboardEvent): void => {
    if (ev.key === 'Escape') {
      ev.stopPropagation()
      finish(false)
    }
  }

  el.setPointerCapture(e.pointerId)
  el.addEventListener('pointermove', onMove)
  el.addEventListener('pointerup', onUp)
  el.addEventListener('pointercancel', onCancel)
  window.addEventListener('keydown', onKey, true)
}
