// The one pointer-gesture lifecycle: a pending→active state machine gated on ACTIVATION travel,
// the window listener trio + Esc, deferred pointer capture, and mirrored teardown. Every drag
// surface needs this skeleton — hand-rolling it per surface means the same edge-case bug (leaked
// listener, stranded capture, un-suppressed click) has to be fixed again in every copy. This
// module owns exactly that skeleton and nothing else: geometry models, snapshots, autoscroll, and
// drop chrome stay with the caller, wired through the hooks below.

import { type PointerEvent as ReactPointerEvent, useCallback, useEffect, useRef } from 'react'
import { ACTIVATION } from './shared'

export type PointerGestureSpec = {
  /** The element that anchors the gesture (capture target; the caller's drag subject). */
  el: HTMLElement
  /** The React pointerdown that starts the press. */
  event: ReactPointerEvent
  /** Travel (px) before the press becomes a drag. Default ACTIVATION. */
  activation?: number
  /** Defer-capture the pointer on activation (default true). Off for window-listener-only surfaces. */
  capture?: boolean
  /**
   * The press crossed the activation threshold: snapshot geometry, bind per-drag listeners,
   * start autoscroll. Return false to abort (e.g. the subject vanished) — teardown runs, no drop.
   */
  onActivate: (e: PointerEvent) => boolean | undefined
  /** A post-activation pointermove. */
  onDragMove: (e: PointerEvent) => void
  /** Release after activation — commit here (and suppress the click yourself if one landed). */
  onDrop: () => void
  /** The gesture ended without a drop: pointercancel, Escape, or an activation abort. */
  onAbort?: () => void
  /** Runs on EVERY end — drop, abort, or sub-threshold tap — before onDrop/onAbort. The place to
   *  stop autoscroll, remove per-drag listeners, and end drag-disclose. */
  teardown?: () => void
  /** Bind Escape in the capture phase and swallow it while ACTIVE — for surfaces living inside a
   *  dismissable host (a dropdown) whose own Escape must not fire mid-drag. A sub-threshold press
   *  still leaves Escape to the host. */
  swallowActiveEscape?: boolean
}

type LiveGesture = {
  spec: PointerGestureSpec
  active: boolean
  handlers: {
    move: (e: PointerEvent) => void
    up: () => void
    cancel: () => void
    key: (e: KeyboardEvent) => void
  }
}

// One pointer, one gesture — a module singleton, so a begin during a live gesture is refused.
let live: LiveGesture | null = null

function detach(g: LiveGesture): void {
  window.removeEventListener('pointermove', g.handlers.move)
  window.removeEventListener('pointerup', g.handlers.up)
  window.removeEventListener('pointercancel', g.handlers.cancel)
  window.removeEventListener('keydown', g.handlers.key, {
    capture: g.spec.swallowActiveEscape ?? false,
  })
  try {
    g.spec.el.releasePointerCapture(g.spec.event.pointerId)
  } catch {
    // never captured / already released
  }
  g.spec.teardown?.()
  live = null
}

/** A live gesture's owner handle — `abort()` tears it down ONLY if it is still the live one
 *  (a component unmounting mid-drag must never kill a sibling's gesture). */
export type GestureHandle = { abort: () => void }

/**
 * Start the shared pending→active pointer gesture. Returns null if refused (busy, non-primary,
 * or a non-left button). Window listeners drive the whole gesture — capture (if enabled) is
 * deferred to activation so a sub-threshold tap keeps its click.
 */
export function beginPointerGesture(spec: PointerGestureSpec): GestureHandle | null {
  const e = spec.event
  if (live || e.button !== 0 || !e.isPrimary) return null
  const startX = e.clientX
  const startY = e.clientY
  const threshold = spec.activation ?? ACTIVATION

  const g: LiveGesture = {
    spec,
    active: false,
    handlers: {
      move: (ev: PointerEvent) => {
        if (!g.active) {
          if (Math.hypot(ev.clientX - startX, ev.clientY - startY) < threshold) return
          if (spec.capture !== false) {
            try {
              spec.el.setPointerCapture(e.pointerId)
            } catch {
              // capture unavailable — window listeners still drive the drag
            }
          }
          g.active = true
          if (spec.onActivate(ev) === false) {
            detach(g)
            spec.onAbort?.()
            return
          }
        }
        spec.onDragMove(ev)
      },
      up: () => {
        const wasActive = g.active
        detach(g)
        if (wasActive) spec.onDrop()
      },
      cancel: () => {
        const wasActive = g.active
        detach(g)
        if (wasActive) spec.onAbort?.()
      },
      key: (ev: KeyboardEvent) => {
        if (ev.key !== 'Escape') return
        if (spec.swallowActiveEscape && g.active) {
          ev.stopImmediatePropagation()
          ev.preventDefault()
        }
        g.handlers.cancel()
      },
    },
  }
  live = g
  window.addEventListener('pointermove', g.handlers.move)
  window.addEventListener('pointerup', g.handlers.up)
  window.addEventListener('pointercancel', g.handlers.cancel)
  window.addEventListener('keydown', g.handlers.key, {
    capture: spec.swallowActiveEscape ?? false,
  })
  return {
    abort: () => {
      if (live === g) g.handlers.cancel()
    },
  }
}

/**
 * A surface's side of the ritual: hold the live handle, abort it on unmount, and honor the
 * refusal rule — a refused begin (a gesture already live) must never overwrite the live
 * gesture's handle, or the unmount abort would no-op and leak that gesture's listeners.
 * Returns whether the gesture actually started.
 */
export function usePointerGesture(): (spec: PointerGestureSpec) => boolean {
  const handle = useRef<GestureHandle | null>(null)
  useEffect(() => () => handle.current?.abort(), [])
  return useCallback((spec) => {
    const h = beginPointerGesture(spec)
    if (h) handle.current = h
    return h !== null
  }, [])
}
