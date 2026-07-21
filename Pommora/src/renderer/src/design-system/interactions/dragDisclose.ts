// Spring-loaded group headers. While ANY drag is active, dwelling the pointer over a COLLAPSED band
// header for ~half a second discloses (expands) it, so a card/row can be dropped into a folded group.
// Engine-agnostic by construction: a drag engine calls beginDragDisclose/endDragDisclose around its
// gesture, and GroupBand registers each collapsed header — no engine needs to know about bands, and
// no band needs to know which engine is dragging. The hit-test rides a window pointermove +
// elementFromPoint, so it works under pointer capture too (where pointerenter never fires).

const DWELL_MS = 500 // ~half a second — the deliberate hold before a folded group springs open

const targets = new Map<HTMLElement, () => void>() // collapsed header → its expand
let drags = 0 // active-drag refcount (only one at a time, but refcount survives unbalanced calls)
let hovered: HTMLElement | null = null
let timer: number | null = null
let lastCheck = 0
let remeasure: (() => void) | null = null // the active engine re-snapshots its drop geometry
let remeasureTimer: number | null = null

function clearHover(): void {
  hovered = null
  if (timer != null) {
    clearTimeout(timer)
    timer = null
  }
}

// After a band springs open its rows/cards mount and the layout shifts — so the engine's ONE-TIME drag
// geometry snapshot is now stale and the just-revealed group isn't a drop target. Re-snapshot it: once
// on the next frame (an instant/reduced-motion open) and once after the disclosure animation settles.
function scheduleRemeasure(): void {
  if (!remeasure) return
  requestAnimationFrame(() => {
    if (drags > 0) remeasure?.()
  })
  if (remeasureTimer != null) clearTimeout(remeasureTimer)
  remeasureTimer = window.setTimeout(() => {
    if (drags > 0) remeasure?.()
  }, 250)
}

function onMove(e: PointerEvent): void {
  // Throttle the hit-test well under the dwell — a folded header only needs to be noticed once inside
  // the half-second window, not every frame (elementFromPoint is a layout read).
  const now = performance.now()
  if (now - lastCheck < 100) return
  lastCheck = now
  const under = document.elementFromPoint(e.clientX, e.clientY)
  const found = under?.closest('[data-disclose]') as HTMLElement | null
  const target = found && targets.has(found) ? found : null
  if (target === hovered) return
  clearHover()
  hovered = target
  if (target)
    timer = window.setTimeout(() => {
      const expand = targets.get(target)
      clearHover()
      expand?.()
      scheduleRemeasure()
    }, DWELL_MS)
}

/** A collapsed band registers its header element + expand; returns an unregister for the effect. */
export function registerDiscloseTarget(el: HTMLElement, expand: () => void): () => void {
  targets.set(el, expand)
  return () => {
    targets.delete(el)
    if (hovered === el) clearHover()
  }
}

/** `onDisclose` re-snapshots the calling engine's drop geometry after a group springs open. */
export function beginDragDisclose(onDisclose?: () => void): void {
  remeasure = onDisclose ?? null
  if (drags++ === 0) window.addEventListener('pointermove', onMove)
}

export function endDragDisclose(): void {
  drags = Math.max(0, drags - 1)
  if (drags === 0) {
    window.removeEventListener('pointermove', onMove)
    clearHover()
    remeasure = null
    if (remeasureTimer != null) {
      clearTimeout(remeasureTimer)
      remeasureTimer = null
    }
  }
}
