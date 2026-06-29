// Rejects any in-line delete that would erode a callout BODY line's hidden `> ` prefix (which would drop the
// line out of the box). A JOIN (delete reaching past the line start) and a whole-head strip stay allowed — both
// keep the box valid. The companion `calloutAtomic` covers the typing side by keeping the caret out of the prefix.
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
