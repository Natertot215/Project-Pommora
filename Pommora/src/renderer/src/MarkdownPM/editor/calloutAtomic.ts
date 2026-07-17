// Every callout line's hidden prefix is atomic — the head's `> [!type] ` AND each body line's `> `. The caret
// can't land inside it, so NO delete variant (Backspace, Shift/Cmd/Alt+Backspace, forward-Delete, …) can corrupt
// it char-by-char: it either removes the whole prefix as one unit or leaves it untouched. The head can't be
// demoted to a quote, and a body line can't lose its space (`> `→`>`) and silently fall out of the box. The
// custom Backspace handler still runs first (Prec.high) for its join behaviour — atomic ranges don't block a
// programmatic dispatch, only CM's own default cursor-motion/deletion.
import { EditorView, Decoration } from '@codemirror/view'
import { RangeSetBuilder, type RangeSet } from '@codemirror/state'
import { calloutScan } from './docCache'

function prefixRanges(view: EditorView): RangeSet<Decoration> {
  const { lines, info } = calloutScan(view.state.doc)
  const builder = new RangeSetBuilder<Decoration>()
  let off = 0
  for (let i = 0; i < lines.length; i++) {
    const co = info[i]
    if (co && co.prefixEnd > 0) builder.add(off, off + co.prefixEnd, Decoration.mark({}))
    off += lines[i].length + 1
  }
  return builder.finish()
}

export const calloutAtomic = EditorView.atomicRanges.of(prefixRanges)
