// The block-drag rail handles: a grip on each draggable block's first line, content-anchored like the fold
// chevron (a `::before` on the line, so it can't drift below callouts/folds). Headings use the chevron,
// callouts keep their own grip, and the table widget supplies its own — so this covers paragraph, code,
// blockquote, and a list (grabbed at item 1, which is the list block's first line).
import { EditorView, Decoration } from '@codemirror/view'
import type { Range } from '@codemirror/state'
import { blockStarts } from './blockModel'
import { lineElementAt } from './lineDom'

// Blockquote is intentionally NOT here: its quote bar is a `::before` on the line, so a grip `::before`
// collides and replaces the bar on the first row. Blockquotes get a handle off their own border later.
const GRIP_KINDS = new Set(['paragraph', 'code', 'list'])

export const blockHandles = EditorView.decorations.compute(['doc'], (state) => {
  const ranges: Range<Decoration>[] = []
  for (const b of blockStarts(state.doc.toString())) {
    if (GRIP_KINDS.has(b.kind)) ranges.push(Decoration.line({ class: 'md-block-handle' }).range(b.from))
  }
  return Decoration.set(ranges, true)
})

// A grip `::before` can't self-hover (a pseudo-element has no independent `:hover`) and the line's own `:hover`
// fires over its text too — so the grip is revealed by `md-grip-hot`, toggled here only while the pointer sits
// in a grip line's gutter strip (left of its content), tracked by a delegated mousemove.
let hotLine: HTMLElement | null = null
function setHot(next: HTMLElement | null): void {
  if (next === hotLine) return
  hotLine?.classList.remove('md-grip-hot')
  next?.classList.add('md-grip-hot')
  hotLine = next
}

export const blockGripHover = EditorView.domEventHandlers({
  mousemove(e, view) {
    const pos = view.posAtCoords({ x: e.clientX, y: e.clientY }, false)
    const line = pos == null ? null : lineElementAt(view, view.state.doc.lineAt(pos).from)
    const inGutter =
      !!line &&
      (line.classList.contains('md-block-handle') || line.classList.contains('md-callout-first')) &&
      e.clientX < line.getBoundingClientRect().left
    setHot(inGutter ? line : null)
  },
  mouseleave() {
    setHot(null)
  }
})
