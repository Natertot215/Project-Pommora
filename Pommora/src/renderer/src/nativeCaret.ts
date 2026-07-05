// A drawn caret for native text fields — <input>, <textarea>, and plain contenteditable. CodeMirror
// surfaces have their own (the customCaret layer); everything else relies on the browser's native caret,
// which CSS can only recolour, never reshape. This paints the SAME `.mdpm-caret` visual (Carets.css knobs)
// over whichever field is focused, so the whole app shows one caret. It attaches globally — one focus
// listener at the document root — so it covers every input, including ones it doesn't own, without editing
// their components. The native caret is hidden in Carets.css; here we only position the drawn bar.

// Computed-style props copied onto the measuring mirror so its text lays out exactly like the field's.
const MIRROR_PROPS = [
  'boxSizing', 'width', 'height',
  'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
  'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
  'borderTopStyle', 'borderRightStyle', 'borderBottomStyle', 'borderLeftStyle',
  'fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'fontVariant', 'fontStretch',
  'letterSpacing', 'wordSpacing', 'lineHeight', 'textAlign', 'textIndent', 'textTransform', 'tabSize'
] as const

type Field = HTMLInputElement | HTMLTextAreaElement

// Input types that expose a text caret + selectionStart (email/number return null selectionStart, so skip).
// `password` is out on purpose: it renders masked dots, so the mirror's real-character widths would mis-place
// the caret.
const TEXT_TYPES = new Set(['', 'text', 'search', 'url', 'tel'])

const isField = (el: EventTarget | null): el is Field =>
  (el instanceof HTMLTextAreaElement && !el.readOnly && !el.disabled) ||
  (el instanceof HTMLInputElement && TEXT_TYPES.has(el.type) && !el.readOnly && !el.disabled)

// Editable text that ISN'T a CodeMirror surface (those carry customCaret already).
const isEditable = (el: EventTarget | null): el is HTMLElement =>
  el instanceof HTMLElement && el.isContentEditable && !el.closest('.cm-editor')

interface CaretRect {
  x: number
  y: number
  h: number
}

let bar: HTMLDivElement | null = null
let mirror: HTMLDivElement | null = null
let active: HTMLElement | null = null
let raf = 0
let started = false
// A field that resizes AFTER focus (`field-sizing` growth, or a picker pane re-centering as it does) strands
// the bar at its focus-time spot — re-measure on resize. Size-only: a pure position shift with no resize rides
// the next caret event (input/click) instead, so an idle field that only moves can lag a frame until then.
let fieldRO: ResizeObserver | null = null
// The mirror's copied style only changes when the field (or layout) does, not per keystroke — cache which
// field it's styled for + that field's line height, so the per-frame path only updates text + position.
let styledEl: Field | null = null
let styledH = 0

function ensureNodes(): void {
  if (!bar) {
    bar = document.createElement('div')
    bar.className = 'mdpm-caret-overlay'
    bar.style.display = 'none'
    document.body.appendChild(bar)
  }
  if (!mirror) {
    mirror = document.createElement('div')
    mirror.setAttribute('aria-hidden', 'true')
    Object.assign(mirror.style, {
      position: 'fixed',
      visibility: 'hidden',
      pointerEvents: 'none',
      overflow: 'hidden',
      zIndex: '-1',
      top: '0',
      left: '0'
    })
    document.body.appendChild(mirror)
  }
}

// Copy the field's box + font onto the mirror so its text lays out identically. Only needed when the active
// field changes (or layout shifts on resize) — never per keystroke.
function syncMirror(el: Field): void {
  const cs = getComputedStyle(el)
  const m = mirror as HTMLDivElement
  const ms = m.style as unknown as Record<string, string>
  const src = cs as unknown as Record<string, string>
  for (const p of MIRROR_PROPS) ms[p] = src[p]
  m.style.whiteSpace = el instanceof HTMLInputElement ? 'pre' : 'pre-wrap'
  m.style.wordWrap = el instanceof HTMLInputElement ? 'normal' : 'break-word'
  styledH = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.4
  styledEl = el
}

// Caret position for an <input>/<textarea>: lay the text up to the caret into the mirror parked over the field,
// read the trailing span's box (= the caret point), then shift by the field's own scroll offset so a scrolled
// long line still maps to the visible caret.
function fieldCaret(el: Field): CaretRect | null {
  const m = mirror as HTMLDivElement
  if (styledEl !== el) syncMirror(el)
  const rect = el.getBoundingClientRect()
  m.style.left = `${rect.left}px`
  m.style.top = `${rect.top}px`
  const pos = el.selectionStart ?? el.value.length
  m.textContent = el.value.slice(0, pos)
  // The trailing span's LEFT edge marks the caret; a lone `.` stands in when the caret's at the end so the span
  // has a box. Assumes left-aligned text — a text-align:right/center field would mis-place it, but the app has
  // none (revisit here if a right/centered input ever appears).
  const span = document.createElement('span')
  span.textContent = el.value.slice(pos) || '.'
  m.appendChild(span)
  const sr = span.getBoundingClientRect()
  m.textContent = ''
  const x = sr.left - el.scrollLeft
  const y = sr.top - el.scrollTop
  // Draw nothing if the field has no box (detached / display:none) or the caret scrolled out of view on either
  // axis — so a vertically-scrolled textarea or a collapsed field can't strand a bar over other content.
  if (rect.width === 0 && rect.height === 0) return null
  if (x < rect.left - 1 || x > rect.right + 1 || y < rect.top - 1 || y > rect.bottom + 1) return null
  return { x, y, h: styledH }
}

// Caret position for plain contenteditable: the collapsed selection's own client rect.
function editableCaret(el: HTMLElement): CaretRect | null {
  const sel = getSelection()
  if (!sel || !sel.rangeCount) return null
  const r = sel.getRangeAt(0).cloneRange()
  r.collapse(true)
  const rect = r.getClientRects()[0] ?? r.getBoundingClientRect()
  if (!rect || (rect.height === 0 && rect.width === 0 && rect.left === 0)) return null // empty line — skip, don't mutate the DOM
  const cs = getComputedStyle(el)
  return { x: rect.left, y: rect.top, h: parseFloat(cs.lineHeight) || rect.height || parseFloat(cs.fontSize) * 1.4 }
}

function reposition(): void {
  raf = 0
  const b = bar as HTMLDivElement
  if (!active || !active.isConnected) {
    b.style.display = 'none'
    return
  }
  const c = isField(active) ? fieldCaret(active) : isEditable(active) ? editableCaret(active) : null
  if (!c) {
    b.style.display = 'none'
    return
  }
  b.style.display = 'block'
  b.style.left = `${c.x}px`
  b.style.top = `${c.y}px`
  b.style.height = `${c.h}px`
  // Restart the fade on every move so the caret reads solid the instant it relocates — same keyframe-swap
  // trick the editor's caret.ts uses (no reflow); the animation name IS the state, no extra flag.
  b.style.animationName = b.style.animationName === 'mdpm-blink2' ? 'mdpm-blink' : 'mdpm-blink2'
}

function schedule(): void {
  // Nothing focused → nothing to draw; don't burn a frame on every scroll/resize elsewhere in the app.
  if (active && !raf) raf = requestAnimationFrame(reposition)
}

export function initNativeCaret(): void {
  if (started || typeof document === 'undefined') return
  started = true
  ensureNodes()
  document.addEventListener('focusin', (e) => {
    active = isField(e.target) || isEditable(e.target) ? (e.target as HTMLElement) : null
    fieldRO?.disconnect()
    if (active) {
      // styledEl reset forces a mirror re-sync (its cached box is stale once the field resizes). Defer
      // a frame before scheduling so the re-measure lands AFTER the pane's resultant re-center render,
      // not on the intermediate geometry (which strands the bar a few px off).
      fieldRO = new ResizeObserver(() => {
        styledEl = null
        requestAnimationFrame(schedule)
      })
      fieldRO.observe(active)
    }
    schedule()
  })
  document.addEventListener('focusout', (e) => {
    // Hide directly — schedule() now no-ops once `active` is null, so it can't do the hide for us.
    if (e.target === active) {
      active = null
      styledEl = null
      fieldRO?.disconnect()
      if (bar) bar.style.display = 'none'
    }
  })
  // Any event that can move the caret. Capture so a field's own scroll (which doesn't bubble) is seen too.
  for (const ev of ['input', 'keyup', 'click', 'pointerup', 'select', 'scroll']) {
    document.addEventListener(ev, schedule, true)
  }
  document.addEventListener('selectionchange', schedule)
  // Layout may shift the field on resize — force a one-time mirror re-sync next frame.
  window.addEventListener('resize', () => {
    styledEl = null
    schedule()
  })
  window.addEventListener('scroll', schedule, true)
}
