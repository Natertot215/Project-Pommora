// The block-drag rail handles: a grip on each draggable block's first line, content-anchored like the fold
// chevron (a `::before` on the line, so it can't drift below callouts/folds). Headings use the chevron,
// callouts keep their own grip, and the table widget supplies its own — so the rail grip covers paragraph,
// code, hr, and a list (grabbed at item 1, the list block's first line).
import { Decoration, EditorView, WidgetType } from '@codemirror/view'
import type { Extension, Range } from '@codemirror/state'
import { blockAt, blockStarts } from './blockModel'
import { lineElementAt } from './lineDom'

const GRIP_KINDS = new Set(['paragraph', 'code', 'list', 'hr'])

// Blocks whose grip reveals on a gutter hover of ANY of their lines (the grip itself sits on the first line):
// GRIP_KINDS plus the box blocks that have a grip but aren't rail-pseudo grips. Tables are out — their rows
// carry their own handles.
const GRIP_BLOCKS = new Set([...GRIP_KINDS, 'callout', 'blockquote'])

// Blockquote can't use the rail `::before` grip — its quote bar is a `::before` and its fill an `::after`, both
// taken — so its grip is a real element (this widget), dropped into the same gutter by CSS. `side: -1` puts it
// before the line content; `ignoreEvent` false lets the press reach the md-bq-first drag gesture.
class GripWidget extends WidgetType {
  eq(): boolean {
    return true
  }
  toDOM(): HTMLElement {
    const el = document.createElement('span')
    el.className = 'md-bq-grip'
    el.setAttribute('aria-hidden', 'true')
    return el
  }
  ignoreEvent(): boolean {
    return false
  }
}
const gripWidget = new GripWidget()

export const blockHandles = EditorView.decorations.compute(['doc'], (state) => {
  const ranges: Range<Decoration>[] = []
  for (const b of blockStarts(state.doc.toString())) {
    if (GRIP_KINDS.has(b.kind)) ranges.push(Decoration.line({ class: 'md-block-handle' }).range(b.from))
    else if (b.kind === 'blockquote') ranges.push(Decoration.widget({ widget: gripWidget, side: -1 }).range(b.from))
  }
  return Decoration.set(ranges, true)
})

// Grips can't self-hover (a pseudo has no independent `:hover`, and a line's own `:hover` fires over its text
// too), so `md-grip-hot` is toggled here whenever the pointer sits in the gutter strip of ANY line within a
// grippable block — revealing the grip on that block's first line (paragraphs already behave this way, being a
// single doc line). `onHotChange` reports the HOVERED line, not the revealed one, so the host's callout-grip
// flag (the seam the right-click delete menu rides on) stays on the grip's own line, not anywhere in the box.
export function blockGripHover(onHotChange?: (line: HTMLElement | null) => void): Extension {
  let hotLine: HTMLElement | null = null
  const setHot = (next: HTMLElement | null): void => {
    if (next === hotLine) return
    hotLine?.classList.remove('md-grip-hot')
    next?.classList.add('md-grip-hot')
    hotLine = next
  }
  let reported: HTMLElement | null = null
  const report = (line: HTMLElement | null): void => {
    if (line === reported) return
    reported = line
    onHotChange?.(line)
  }
  // blockAt parses the doc, so resolve the block only when the hovered doc-line changes, not every pixel.
  let cachedFrom = -1
  let cachedFirstFrom = -1
  return EditorView.domEventHandlers({
    mousemove(e, view) {
      const pos = view.posAtCoords({ x: e.clientX, y: e.clientY }, false)
      const hovered = pos == null ? null : lineElementAt(view, view.state.doc.lineAt(pos).from)
      if (pos == null || !hovered || e.clientX >= hovered.getBoundingClientRect().left) {
        setHot(null)
        report(null)
        return
      }
      const lineFrom = view.state.doc.lineAt(pos).from
      if (lineFrom !== cachedFrom) {
        cachedFrom = lineFrom
        const block = blockAt(view.state.doc.toString(), pos)
        cachedFirstFrom = block && GRIP_BLOCKS.has(block.kind) ? view.state.doc.lineAt(block.from).from : -1
      }
      setHot(cachedFirstFrom < 0 ? null : lineElementAt(view, cachedFirstFrom))
      report(hovered)
    },
    mouseleave() {
      setHot(null)
      report(null)
    }
  })
}
