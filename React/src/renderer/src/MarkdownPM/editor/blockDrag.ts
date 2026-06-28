// Block drag: press a block's rail grip → drag the whole block → drop it at the nearest block boundary,
// relocating its source lines via `blockMoveChanges`. Same gesture lifecycle as listDrag (pointerdown →
// ACTIVATION threshold → in-place shade → fixed insertion-line → drop), but the source is a block handle
// (a `::before` hit-tested by x, like the chevron), the scope is `blockAt`, and the drop targets are
// `blockStarts`. TODO(polish): extract the shared Overlay + shade so listDrag and blockDrag share one copy.
import { StateEffect, StateField, type Extension, type Line, type Range, type Text } from '@codemirror/state'
import { Decoration, type DecorationSet, EditorView } from '@codemirror/view'
import { ACTIVATION } from '../../design-system/interactions/shared'
import { blockAt, blockStarts } from './blockModel'
import { blockMoveChanges } from './listDragModel'

const setShade = StateEffect.define<{ from: number; to: number } | null>()
const shadeLine = Decoration.line({ class: 'md-li-drag-source' }) // reuse the list-drag source shade

function forEachLine(doc: Text, from: number, to: number, fn: (l: Line) => void): void {
  let line = doc.lineAt(from)
  while (line.from <= to) {
    fn(line)
    if (line.to + 1 > doc.length) break
    line = doc.lineAt(line.to + 1)
  }
}

const shadeField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes)
    for (const e of tr.effects) {
      if (!e.is(setShade)) continue
      if (e.value === null) deco = Decoration.none
      else {
        const r: Range<Decoration>[] = []
        forEachLine(tr.state.doc, e.value.from, e.value.to, (l) => r.push(shadeLine.range(l.from)))
        deco = Decoration.set(r)
      }
    }
    return deco
  },
  provide: (f) => EditorView.decorations.from(f)
})

// The fixed accent insertion line (same overlay listDrag draws — no floating ghost; the shade shows what moves).
class Overlay {
  private line: HTMLElement | null = null
  show(left: number, top: number, width: number): void {
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
  destroy(): void {
    this.line?.remove()
    this.line = null
  }
}

// Drop candidates: every block-start (+ EOF) outside the dragged block, measured in viewport coords. A
// boundary's insertion line sits at the BOTTOM of the line above it (the gap top), so it hugs the block
// above instead of floating at the next block's padded line-box top — at doc start there's no line above,
// so use the first line's top.
interface Cand {
  at: number
  y: number
  left: number
  right: number
}
function collectCands(view: EditorView, block: { from: number; to: number }): Cand[] {
  const doc = view.state.doc.toString()
  const rect = view.contentDOM.getBoundingClientRect()
  const right = rect.right - (parseFloat(getComputedStyle(view.contentDOM).paddingRight) || 0)
  const out: Cand[] = []
  for (const { from: at } of blockStarts(doc)) {
    if (at >= block.from && at <= block.to + 1) continue // before/after the dragged block → no-op
    const here = view.coordsAtPos(at)
    if (!here) continue // folded away or off-screen → not a droppable boundary (auto-scroll brings scrollable ones in)
    const above = at === 0 ? null : view.coordsAtPos(at - 1)
    out.push({ at, y: above ? above.bottom : here.top, left: here.left, right })
  }
  if (block.to + 1 < doc.length) {
    const eof = view.coordsAtPos(doc.length)
    if (eof) out.push({ at: doc.length, y: eof.bottom, left: eof.left, right })
  }
  return out.sort((a, b) => a.y - b.y)
}

// Auto-scroll tuning: the band at the scroller's top/bottom edge where a held drag keeps scrolling, and the
// per-frame step (ramped by how deep into the band the pointer is, capped).
const EDGE = 48
const edgeStep = (depth: number): number => Math.min(Math.ceil((depth / EDGE) * 14), 14)
function nearest(cands: Cand[], clientY: number): Cand | null {
  let best: Cand | null = null
  let bd = Infinity
  for (const c of cands) {
    const d = Math.abs(clientY - c.y)
    if (d < bd) {
      bd = d
      best = c
    }
  }
  return best
}

export const blockDragExtension: Extension = [
  shadeField,
  EditorView.domEventHandlers({
    // Suppress CM's text-selection drag when the press starts on a block grip (in the gutter strip).
    mousedown(e) {
      const line = (e.target as HTMLElement).closest?.('.cm-line.md-block-handle') as HTMLElement | null
      if (e.button === 0 && line && e.clientX < line.getBoundingClientRect().left) {
        e.preventDefault()
        return true
      }
      return false
    },
    pointerdown(e, view) {
      if (e.button !== 0) return false
      const line = (e.target as HTMLElement).closest?.('.cm-line.md-block-handle') as HTMLElement | null
      if (!line || e.clientX >= line.getBoundingClientRect().left) return false // not the grip zone
      const block = blockAt(view.state.doc.toString(), view.posAtDOM(line))
      if (!block) return false
      e.preventDefault()

      const host = view.scrollDOM
      const g = { active: false, done: false, overlay: new Overlay(), cands: [] as Cand[], slot: null as Cand | null, lastY: e.clientY, raf: 0 }

      // Re-aim the insertion line at the candidate nearest the last pointer Y — no re-measure.
      const repick = (): void => {
        g.slot = nearest(g.cands, g.lastY)
        if (g.slot) g.overlay.show(g.slot.left, g.slot.y, Math.max(g.slot.right - g.slot.left, 40))
        else g.overlay.destroy()
      }
      // Candidate coords are viewport-relative, so any scroll (wheel or the auto-scroll below) invalidates
      // them — re-measure against the new layout, then re-aim. The doc is static, so this is pure geometry.
      const remeasure = (): void => {
        g.cands = collectCands(view, block)
        repick()
      }
      // Auto-scroll while the pointer sits in the top/bottom EDGE band, so a block can reach a target that was
      // off-screen at grab time (CM only renders ~viewport, so far targets aren't candidates until scrolled in).
      const tick = (): void => {
        g.raf = 0
        if (!g.active) return
        const r = host.getBoundingClientRect()
        let dy = 0
        if (g.lastY < r.top + EDGE) dy = -edgeStep(r.top + EDGE - g.lastY)
        else if (g.lastY > r.bottom - EDGE) dy = edgeStep(g.lastY - (r.bottom - EDGE))
        if (dy === 0) return
        const before = host.scrollTop
        host.scrollTop += dy
        if (host.scrollTop === before) return // at the scroll limit — wait for the pointer to move again
        g.raf = requestAnimationFrame(tick) // the scrollTop write fires `scroll` → onScroll → remeasure (one path)
      }

      const onMove = (ev: PointerEvent): void => {
        if (!g.active) {
          if (Math.hypot(ev.clientX - e.clientX, ev.clientY - e.clientY) < ACTIVATION) return
          g.active = true
          document.body.style.cursor = 'grabbing'
          try {
            host.setPointerCapture(e.pointerId)
          } catch {
            // capture unavailable
          }
          view.dispatch({ effects: setShade.of({ from: block.from, to: block.to }) })
          g.cands = collectCands(view, block)
        }
        g.lastY = ev.clientY
        repick()
        if (!g.raf) g.raf = requestAnimationFrame(tick) // (re)start auto-scroll if we're near an edge
      }

      const onScroll = (): void => {
        if (g.active) remeasure()
      }
      const onKey = (ev: KeyboardEvent): void => {
        if (ev.key === 'Escape') finish(false)
      }

      const finish = (commit: boolean): void => {
        if (g.done) return // a drag ends once — guard the new window blur/Escape paths from re-entering
        g.done = true
        document.body.style.cursor = ''
        if (g.raf) cancelAnimationFrame(g.raf)
        host.removeEventListener('pointermove', onMove)
        host.removeEventListener('pointerup', onUp)
        host.removeEventListener('pointercancel', onCancel)
        host.removeEventListener('scroll', onScroll)
        window.removeEventListener('keydown', onKey)
        window.removeEventListener('blur', onCancel)
        try {
          host.releasePointerCapture(e.pointerId)
        } catch {
          // already released
        }
        g.overlay.destroy()
        if (g.active) view.dispatch({ effects: setShade.of(null) })
        if (g.active && commit && g.slot) {
          const changes = blockMoveChanges(view.state.doc.toString(), block, { at: g.slot.at })
          if (changes && changes.length) view.dispatch({ changes, userEvent: 'input' })
        }
      }

      const onUp = (): void => finish(true)
      const onCancel = (): void => finish(false)
      host.addEventListener('pointermove', onMove)
      host.addEventListener('pointerup', onUp)
      host.addEventListener('pointercancel', onCancel)
      host.addEventListener('scroll', onScroll, { passive: true })
      window.addEventListener('keydown', onKey)
      window.addEventListener('blur', onCancel)
      return true
    }
  })
]
