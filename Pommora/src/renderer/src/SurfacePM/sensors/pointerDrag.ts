// The SurfacePM pointer sensor — PommoraDND's capture discipline (Pointer Events +
// setPointerCapture, rAF-coalesced moves, Esc abort) as a one-shot drag primitive
// for the surface's free-2D gestures, which the engine's list-slot Zones can't
// host. Shares the engine's vocabulary: the app-wide ACTIVATION threshold and the
// post-drop click suppression.

import { ACTIVATION, suppressNextClick } from '@renderer/design-system/interactions/shared'

export interface PointerDragHandlers {
  /** Fires rAF-coalesced with the cumulative delta from the drag origin. */
  onMove: (dx: number, dy: number, e: PointerEvent) => void
  /** Fires once: true = commit, false = aborted (Esc / pointercancel / unarmed release). */
  onEnd: (commit: boolean) => void
  /** Pixels of travel before the drag arms — defaults to the engine's ACTIVATION. */
  threshold?: number
}

export function startPointerDrag(e: React.PointerEvent, handlers: PointerDragHandlers): void {
  const el = e.currentTarget as HTMLElement
  const originX = e.clientX
  const originY = e.clientY
  const threshold = handlers.threshold ?? ACTIVATION
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
    el.removeEventListener('lostpointercapture', onLost)
    window.removeEventListener('keydown', onKey, true)
    if (el.hasPointerCapture(e.pointerId)) el.releasePointerCapture(e.pointerId)
    if (commit && armed) suppressNextClick()
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
  // Capture can be torn away without a pointerup (the element re-inserted or
  // removed mid-gesture) — treat it as an abort, never a zombie. On a normal
  // release this fires after pointerup, where `done` already gates it out.
  const onLost = (): void => finish(false)
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
  el.addEventListener('lostpointercapture', onLost)
  window.addEventListener('keydown', onKey, true)
}
