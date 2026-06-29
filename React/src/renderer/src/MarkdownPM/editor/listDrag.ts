// Drag-to-reorder list items by their `.md-li-glyph`: a press past the ACTIVATION threshold becomes a drag, a
// release-in-place is a click (checkbox → toggle, else caret). The drop moves the source lines (block + nested
// descendants) in one transaction, renumbering any ordered run it touched.
import { type Extension } from '@codemirror/state'
import { EditorView } from '@codemirror/view'
import { ACTIVATION } from '../../design-system/interactions/shared'
import { parseListMarkerPrefixed as parseListMarker } from '../detect'
import { Overlay, forEachLine, setShade, shadeField } from './dragChrome'
import { lineElementAt } from './lineDom'
import { subBlockAt, dropChanges, checkboxToggleChange, type SubBlock, type Slot } from './listDragModel'

interface Gesture {
  pid: number
  startX: number
  startY: number
  active: boolean
  overlay: Overlay
  cands: Cand[]
  slot: ResolvedSlot | null
}

interface ResolvedSlot extends Slot {
  lineLeft: number // viewport x of the insertion line's left edge
  lineTop: number // viewport y
  lineWidth: number
  indent: string // depth the dropped block adopts — the target line's leading whitespace
}

// A drop candidate — a visible list line outside the dragged block, measured ONCE at drag start in viewport
// coords. The doc is static during a drag, so re-measuring per pointermove would be pure layout thrash.
interface Cand {
  from: number
  to: number
  top: number // viewport y of the line top
  bottom: number // viewport y of the line bottom
  left: number // viewport x of the marker — the line's left follows the item's indent
  right: number // viewport x of the right gutter (wrap boundary) — the line spans the writing column
  indent: string // the line's leading whitespace — the dropped block adopts this depth
}

// The right edge a drop line reaches on a given line: the page wrap boundary, except inside a box (callout /
// quote), where it's that line's own content-box right — read from the rendered element so the callout's CSS
// padding owns the width (no recomputing the inset here).
function lineRightEdge(view: EditorView, from: number, fallback: number): number {
  const n = lineElementAt(view, from)
  if (!n || (!n.classList.contains('md-callout') && !n.classList.contains('md-bq'))) return fallback
  const cs = getComputedStyle(n)
  return n.getBoundingClientRect().right - parseFloat(cs.paddingRight || '0') - parseFloat(cs.borderRightWidth || '0')
}

function collectCands(view: EditorView, block: SubBlock): Cand[] {
  const doc = view.state.doc
  const contentRect = view.contentDOM.getBoundingClientRect()
  const padRight = parseFloat(getComputedStyle(view.contentDOM).paddingRight) || 0
  const gutterRight = contentRect.right - padRight // the wrap boundary — the line spans out to here
  const out: Cand[] = []
  for (const { from, to } of view.visibleRanges) {
    forEachLine(doc, from, to, (line) => {
      const lm = parseListMarker(line.text)
      const inBlock = line.from >= block.from && line.from <= block.to
      if (lm === null || inBlock) return
      const cTop = view.coordsAtPos(line.from)
      const cEnd = view.coordsAtPos(line.to)
      const cMarker = view.coordsAtPos(line.from + lm.markerStart)
      if (cTop && cEnd) {
        out.push({ from: line.from, to: line.to, top: cTop.top, bottom: cEnd.bottom, left: (cMarker ?? cTop).left, right: lineRightEdge(view, line.from, gutterRight), indent: line.text.slice(0, lm.markerStart) })
      }
    })
  }
  out.sort((a, b) => a.top - b.top)
  return out
}

// Cheap per-move hit-test against the cached candidates — all viewport coords (matching the pointer's
// clientY and the position:fixed line). Picks the row under the pointer, before/after by its vertical half.
function slotFrom(cands: Cand[], clientY: number, block: SubBlock, docLen: number): ResolvedSlot | null {
  // Each candidate offers two insertion boundaries — before it (its top edge) and after it (its bottom
  // edge). Snap to whichever boundary is vertically CLOSEST to the pointer, so a paragraph between two
  // bullets splits to the nearer bullet's edge instead of one bullet owning the whole gap.
  let best: { at: number; y: number; c: Cand } | null = null
  let bestDist = Infinity
  for (const c of cands) {
    for (const b of [
      { at: c.from, y: c.top, c },
      { at: c.to < docLen ? c.to + 1 : docLen, y: c.bottom, c }
    ]) {
      const d = Math.abs(clientY - b.y)
      if (d < bestDist) {
        bestDist = d
        best = b
      }
    }
  }
  if (best === null) return null
  if (best.at >= block.from && best.at <= block.to + 1) return null // landing inside the dragged block → no slot
  return { at: best.at, lineLeft: best.c.left, lineTop: best.y, lineWidth: Math.max(best.c.right - best.c.left, 40), indent: best.c.indent }
}

// A glyph CLICK (press released without crossing ACTIVATION): checkbox → toggle; bullet / number → caret.
function clickAction(view: EditorView, pos: number): void {
  const toggle = checkboxToggleChange(view.state.doc.toString(), pos)
  if (toggle) {
    view.dispatch({ changes: toggle, userEvent: 'input' })
    return
  }
  view.dispatch({ selection: { anchor: pos } })
  view.focus()
}

export const listDragExtension: Extension = [
  shadeField,
  EditorView.domEventHandlers({
    // CM starts its text-selection drag on mousedown, and preventDefault on pointerdown doesn't cancel the
    // compatibility mousedown — so without this, pressing a glyph to drag would also select text under it.
    mousedown(e) {
      if (e.button === 0 && (e.target as HTMLElement).closest?.('.md-li-glyph')) {
        e.preventDefault()
        return true
      }
      return false
    },
    pointerdown(e, view) {
      if (e.button !== 0) return false
      const glyph = (e.target as HTMLElement).closest?.('.md-li-glyph')
      if (!glyph) return false
      const pos = view.posAtDOM(glyph)
      const doc = view.state.doc.toString()
      const block = subBlockAt(doc, pos)
      if (!block) return false

      e.preventDefault() // suppress text-selection / caret on the glyph press (numbers are source text)

      const host = view.scrollDOM
      const gesture: Gesture = {
        pid: e.pointerId,
        startX: e.clientX,
        startY: e.clientY,
        active: false,
        overlay: new Overlay(),
        cands: [],
        slot: null
      }

      const onMove = (ev: PointerEvent): void => {
        if (!gesture.active) {
          if (Math.hypot(ev.clientX - gesture.startX, ev.clientY - gesture.startY) < ACTIVATION) return
          gesture.active = true
          document.body.style.cursor = 'grabbing'
          try {
            host.setPointerCapture(gesture.pid)
          } catch {
            // capture unavailable
          }
          view.dispatch({ effects: setShade.of({ from: block.from, to: block.to }) })
          gesture.cands = collectCands(view, block) // measure once — the doc is static for the drag
        }
        const slot = slotFrom(gesture.cands, ev.clientY, block, view.state.doc.length)
        gesture.slot = slot
        if (slot) gesture.overlay.show(slot.lineLeft, slot.lineTop, slot.lineWidth)
        else gesture.overlay.hide()
      }

      const finish = (commit: boolean): void => {
        document.body.style.cursor = ''
        host.removeEventListener('pointermove', onMove)
        host.removeEventListener('pointerup', onUp)
        host.removeEventListener('pointercancel', onCancel)
        try {
          host.releasePointerCapture(gesture.pid)
        } catch {
          // already released
        }
        gesture.overlay.hide()
        if (gesture.active) view.dispatch({ effects: setShade.of(null) })

        if (!gesture.active) {
          if (commit) clickAction(view, pos) // a click, never a drag
          return
        }
        if (commit && gesture.slot) {
          const changes = dropChanges(view.state.doc.toString(), block, gesture.slot)
          if (changes && changes.length) {
            view.dispatch({ changes, userEvent: 'input' })
          }
        }
      }

      const onUp = (): void => finish(true)
      const onCancel = (): void => finish(false)
      host.addEventListener('pointermove', onMove)
      host.addEventListener('pointerup', onUp)
      host.addEventListener('pointercancel', onCancel)
      return true
    }
  })
]
