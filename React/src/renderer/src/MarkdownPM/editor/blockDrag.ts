// Block drag: press a block's gutter handle → drag the whole block → drop it at the nearest block boundary,
// relocating its source lines via `blockMoveChanges`. `createBlockDragGesture` parameterizes the lifecycle
// (pointerdown → ACTIVATION threshold → in-place shade → fixed insertion-line → drop) by the hit-test class,
// so the rail grips and the heading chevron share ONE gesture. TODO(polish): listDrag still keeps its own
// Overlay + shade copy — fold those into a shared module too.
import { type Extension } from '@codemirror/state'
import { EditorView } from '@codemirror/view'
import { ACTIVATION } from '../../design-system/interactions/shared'
import { blockAt, blockStarts } from './blockModel'
import { Overlay, setShade, shadeField } from './dragChrome'
import { lineElementAt } from './lineDom'
import { blockMoveChanges } from './listDragModel'

// The OUTER bottom of the content block above a gap (skipping blank lines), so the insertion line reads "the
// dragged block goes BELOW this" and sits OUTSIDE a box (below a callout's border, not inside it).
function bottomAbove(view: EditorView, at: number): number | null {
  if (at === 0) return null
  let line = view.state.doc.lineAt(at - 1)
  while (line.from > 0 && line.length === 0) line = view.state.doc.lineAt(line.from - 1)
  return lineElementAt(view, line.from)?.getBoundingClientRect().bottom ?? null
}

// Drop candidates, list-drag-style: each block outside the dragged one offers TWO boundaries — above it (its
// top) and below it (its content bottom, see `bottomAbove`) — so the insertion line snaps to the nearer block
// edge and flips at the block's midpoint. Measured in viewport coords; folded/off-screen blocks are skipped.
interface Cand {
  at: number
  y: number
  left: number
  right: number
  noop: boolean // the "stay put" slot (a drop here moves nothing) — hittable so release-in-place cancels, but draws no line
}
function collectCands(view: EditorView, block: { from: number; to: number }): Cand[] {
  const doc = view.state.doc.toString()
  const rect = view.contentDOM.getBoundingClientRect()
  const right = rect.right - (parseFloat(getComputedStyle(view.contentDOM).paddingRight) || 0)
  const starts = blockStarts(doc).map((b) => b.from)
  const afterBlock = starts.find((s) => s > block.to) ?? doc.length // the boundary just past the dragged block
  const isNoop = (at: number): boolean => at === block.from || at === afterBlock // dropping there leaves the block put
  const out: Cand[] = []
  for (let i = 0; i < starts.length; i++) {
    const from = starts[i]
    if (from >= block.from && from <= block.to) continue // inside the dragged block
    const c = view.coordsAtPos(from)
    if (!c) continue // folded away or off-screen → auto-scroll brings scrollable ones in
    const topY = lineElementAt(view, from)?.getBoundingClientRect().top ?? c.top // OUTER top (above a box's border)
    out.push({ at: from, y: topY, left: c.left, right, noop: isNoop(from) }) // ABOVE this block
    const nextFrom = i + 1 < starts.length ? starts[i + 1] : doc.length
    const botY = bottomAbove(view, nextFrom) // this block's OUTER bottom (below a box's border)
    if (botY !== null) out.push({ at: nextFrom, y: botY, left: c.left, right, noop: isNoop(nextFrom) }) // BELOW this block
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

// The gesture core, callable directly so a non-CM-line handle (the table widget's action grip) can start a
// block drag too. From a starting pointer event + the resolved block: ACTIVATION threshold → in-place shade →
// fixed accent line → drop via `blockMoveChanges`, with auto-scroll, scroll re-measure, and Escape/blur abort.
export function startBlockDrag(
  view: EditorView,
  e: PointerEvent,
  block: { from: number; to: number },
  opts: {
    onClick?: (view: EditorView, line: HTMLElement) => void // sub-threshold release action (e.g. a heading's fold)
    onDragStart?: (view: EditorView, block: { from: number; to: number }) => void // at activation (e.g. unfold)
    line?: HTMLElement // the handle line (for onClick) — absent for the programmatic table grip
  } = {}
): void {
  const { onClick, onDragStart, line } = opts
  if (e.button !== 0) return // only the left button drags; a right-press falls through to the context menu (e.g. the table grip's Delete Table)
  e.preventDefault()
  const host = view.scrollDOM
  const g = { active: false, done: false, overlay: new Overlay(), cands: [] as Cand[], slot: null as Cand | null, lastY: e.clientY, raf: 0 }

  // Re-aim the insertion line at the candidate nearest the last pointer Y — no re-measure.
  const repick = (): void => {
    g.slot = nearest(g.cands, g.lastY)
    // The "stay put" slot stays the resolved target (release-in-place cancels) but draws no line — a drop there no-ops.
    if (g.slot && !g.slot.noop) g.overlay.show(g.slot.left, g.slot.y, Math.max(g.slot.right - g.slot.left, 40))
    else g.overlay.destroy()
  }
  // Candidate coords are viewport-relative, so any scroll (wheel or the auto-scroll below) invalidates them —
  // re-measure against the new layout, then re-aim. The doc is static, so this is pure geometry.
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
      onDragStart?.(view, block) // e.g. unfold a heading section before it moves — folds can't survive the move
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
    if (g.done) return // a drag ends once — guard the window blur/Escape paths from re-entering
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
    if (g.active) {
      view.dispatch({ effects: setShade.of(null) })
      if (commit && g.slot) {
        const changes = blockMoveChanges(view.state.doc.toString(), block, { at: g.slot.at })
        if (changes && changes.length) view.dispatch({ changes, userEvent: 'input' })
      }
    } else if (commit && line) {
      onClick?.(view, line) // a click (sub-threshold release) — e.g. toggle the heading fold
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
}

interface DragConfig {
  gate: string // the cm-line class that arms the gesture (hit-tested in the gutter strip left of the content)
  onClick?: (view: EditorView, line: HTMLElement) => void // sub-threshold release action (e.g. a heading's fold)
  onDragStart?: (view: EditorView, block: { from: number; to: number }) => void // at activation (e.g. unfold)
}

// The CM-line gesture: hit-test the gutter handle (`gate` + clientX), resolve the block via `blockAt`, then hand
// off to `startBlockDrag`. Shared by the rail grips, the heading chevron, and the callout head.
export function createBlockDragGesture({ gate, onClick, onDragStart }: DragConfig): Extension {
  const sel = `.cm-line.${gate}`
  return [
    shadeField,
    EditorView.domEventHandlers({
      // Suppress CM's text-selection drag when the press starts on a gutter handle.
      mousedown(e) {
        const line = (e.target as HTMLElement).closest?.(sel) as HTMLElement | null
        if (e.button === 0 && line && e.clientX < line.getBoundingClientRect().left) {
          e.preventDefault()
          return true
        }
        return false
      },
      pointerdown(e, view) {
        if (e.button !== 0) return false
        const line = (e.target as HTMLElement).closest?.(sel) as HTMLElement | null
        if (!line || e.clientX >= line.getBoundingClientRect().left) return false // not the handle zone
        const block = blockAt(view.state.doc.toString(), view.posAtDOM(line))
        if (!block) return false
        startBlockDrag(view, e, block, { onClick, onDragStart, line })
        return true
      }
    })
  ]
}

export const blockDragExtension: Extension = createBlockDragGesture({ gate: 'md-block-handle' })

// The callout's own gutter grip (its `::after`, on the head line) drags the whole box — `blockAt` resolves a
// callout to its full box, so the same gesture moves it. Gated on the callout head line instead of a rail handle.
export const calloutDragExtension: Extension = createBlockDragGesture({ gate: 'md-callout-first' })
