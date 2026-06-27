// A transaction guard that makes a callout BODY line's hidden `> ` prefix uncorruptible by any delete — no key
// combo (Shift/Cmd/Alt+Backspace, forward-Delete, …) can erode it in place and silently drop the line out of the
// box. Two deletes are still allowed because they keep the box valid: a JOIN (the delete reaches back past the
// line start, merging the line into the callout above) and a HEAD strip (removing the whole `> [!type] ` head
// de-callouts the entire box on purpose, and is guarded separately by the atomic range). Only in-line erosion of
// a body prefix is rejected. The companion `calloutAtomic` keeps the caret out of the prefix so it can't be
// corrupted by typing either; this guard covers the delete side.
import { EditorState, type Extension } from '@codemirror/state'
import { calloutLines } from '../detect'

/** True when deleting [from, to) would erode a callout BODY line's `>` prefix in place (start inside the prefix,
 *  not reaching back before the line). Pure + exported for tests. */
export function stripsCalloutPrefix(doc: string, from: number, to: number): boolean {
  if (to <= from) return false // not a deletion
  const lines = doc.split('\n')
  const info = calloutLines(lines)
  let off = 0
  for (let i = 0; i < lines.length; i++) {
    const co = info[i]
    // Body prefixes only — the head's whole-prefix delete (de-callout) is intentional, and the atomic range
    // already blocks partial head corruption.
    if (co && !co.first && co.prefixEnd > 0 && from >= off && from < off + co.prefixEnd) return true
    off += lines[i].length + 1
  }
  return false
}

export const calloutGuard: Extension = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged) return tr
  const doc = tr.startState.doc.toString()
  let bad = false
  tr.changes.iterChanges((fromA, toA) => {
    if (!bad && stripsCalloutPrefix(doc, fromA, toA)) bad = true
  })
  return bad ? [] : tr // cancel a transaction that would erode a body prefix
})
