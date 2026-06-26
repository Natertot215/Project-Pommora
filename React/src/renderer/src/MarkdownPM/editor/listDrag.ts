// Drag-to-reorder list items by their glyph (bullet / number / checkbox). One CM6 extension owns
// pointerdown on `.md-li-glyph` (the shared marker class added in intent.ts): a press that crosses the
// ACTIVATION threshold becomes a drag; a press that releases in place is a click (checkbox → toggle,
// else place caret). The drop moves the actual Markdown source lines (block + nested descendants) in one
// transaction, renumbering any ordered run it touched. Visuals mirror the sidebar's PommoraDND.
import { StateEffect, StateField, type Extension, type Line, type Range, type Text } from '@codemirror/state'
import { Decoration, type DecorationSet, EditorView } from '@codemirror/view'
import { ACTIVATION } from '../../design-system/interactions/shared'
import { parseListMarker } from '../detect'
import { subBlockAt, dropChanges, checkboxToggleChange, type SubBlock, type Slot } from './listDragModel'

// Walk the doc lines whose span intersects [from, to] inclusive. Shared by the shade decoration and the
// candidate collection — both step through lines the same way (lineAt → next line at line.to + 1).
function forEachLine(doc: Text, from: number, to: number, fn: (line: Line) => void): void {
  let line = doc.lineAt(from)
  while (line.from <= to) {
    fn(line)
    if (line.to + 1 > doc.length) break
    line = doc.lineAt(line.to + 1)
  }
}

// ── Ghost-shade decoration: shades the dragged block's lines in place via a StateField (CM rebuilds
//    line DOM on every change, so a raw class would be wiped — line decorations survive). ──────────────
const setShade = StateEffect.define<{ from: number; to: number } | null>()
const shadeLine = Decoration.line({ class: 'md-li-drag-source' })

const shadeField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes)
    for (const e of tr.effects) {
      if (!e.is(setShade)) continue
      if (e.value === null) {
        deco = Decoration.none
      } else {
        const ranges: Range<Decoration>[] = []
        forEachLine(tr.state.doc, e.value.from, e.value.to, (line) => ranges.push(shadeLine.range(line.from)))
        deco = Decoration.set(ranges)
      }
    }
    return deco
  },
  provide: (f) => EditorView.decorations.from(f)
})

// ── Imperative overlay: just the accent insertion line over the editor (no floating ghost — the in-place
//    shade shows what's moving). Created/torn-down by the gesture; no React tree. ─────────────────────
class Overlay {
  private line: HTMLElement | null = null

  // The insertion line spans the writing column: left edge at the target's content-start x (follows the
  // item's indent), width out to the right gutter. position:fixed → viewport coords, immune to the
  // scroll-container ambiguity an absolute child of scrollDOM has.
  showLine(left: number, top: number, width: number): void {
    if (!this.line) {
      const l = document.createElement('div')
      l.setAttribute('aria-hidden', 'true')
      l.style.cssText = 'position:fixed;height:2px;border-radius:2px;background:var(--accent);pointer-events:none;z-index:1000'
      const dot = document.createElement('span')
      dot.style.cssText = 'position:absolute;left:-3px;top:-2.5px;width:7px;height:7px;border-radius:50%;background:var(--accent)'
      l.appendChild(dot)
      document.body.appendChild(l)
      this.line = l
    }
    this.line.style.left = `${left}px`
    this.line.style.width = `${width}px`
    this.line.style.top = `${top}px`
  }

  hideLine(): void {
    this.line?.remove()
    this.line = null
  }

  destroy(): void {
    this.hideLine()
  }
}

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

// A drop candidate — a visible list line outside the dragged block, measured ONCE at drag start in
// viewport coords. The doc is static during a drag, so re-measuring every line on every pointermove (the
// old resolveSlot) was pure layout thrash — that was the jank, and the line stuttered/stuck under it.
interface Cand {
  from: number
  to: number
  top: number // viewport y of the line top
  bottom: number // viewport y of the line bottom
  left: number // viewport x of the marker — the line's left follows the item's indent
  right: number // viewport x of the right gutter (wrap boundary) — the line spans the writing column
  indent: string // the line's leading whitespace — the dropped block adopts this depth
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
        out.push({ from: line.from, to: line.to, top: cTop.top, bottom: cEnd.bottom, left: (cMarker ?? cTop).left, right: gutterRight, indent: line.text.slice(0, lm.markerStart) })
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
        if (slot) gesture.overlay.showLine(slot.lineLeft, slot.lineTop, slot.lineWidth)
        else gesture.overlay.hideLine()
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
        gesture.overlay.destroy()
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
