// Shared jsdom stubs for driving pointer-gesture tests. jsdom has no PointerEvent constructor,
// measures every rect as zero, and lacks pointer capture — these helpers stub exactly those
// three seams so dnd-surface tests can assert STATE (mount/mute/clear/commit callbacks).
// Geometry truth stays with the CDP passes, never jsdom.

type PointerOpts = { x?: number; y?: number; button?: number; pointerId?: number }

/** Dispatch a pointer-typed event built on MouseEvent (jsdom can't construct PointerEvent),
 *  patched with the pointer fields the gesture code reads. */
export function firePointer(
  target: EventTarget,
  type: 'pointerdown' | 'pointermove' | 'pointerup' | 'pointercancel',
  opts: PointerOpts = {}
): void {
  const e = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: opts.x ?? 0,
    clientY: opts.y ?? 0,
    button: opts.button ?? 0
  })
  Object.defineProperty(e, 'pointerId', { value: opts.pointerId ?? 1 })
  Object.defineProperty(e, 'isPrimary', { value: true })
  target.dispatchEvent(e)
}

/** Give an element a fixed, non-zero bounding rect. */
export function stubRect(
  el: Element,
  r: { top: number; bottom: number; left?: number; right?: number }
): void {
  const left = r.left ?? 0
  const right = r.right ?? 200
  const rect = {
    top: r.top,
    bottom: r.bottom,
    left,
    right,
    width: right - left,
    height: r.bottom - r.top,
    x: left,
    y: r.top,
    toJSON: () => ({})
  } as DOMRect
  el.getBoundingClientRect = () => rect
}

/** Install no-op pointer capture on every element (jsdom throws "not implemented"). */
export function stubPointerCapture(): void {
  Object.assign(HTMLElement.prototype, {
    setPointerCapture: () => {},
    releasePointerCapture: () => {}
  })
}

export function pressEscape(): void {
  window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))
}
