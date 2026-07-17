import { EditorState } from '@codemirror/state'
import { tableRegions } from './regions'
import { parseDelimiter } from './codec'

// A GFM table is its own block only while a blank line fences it; with the separator gone, two tables fuse
// into one — the second table's header + delimiter become body rows, so the region carries a SECOND
// delimiter row. Count the tables that carry more than one (the fused ones). This reads the RESULT doc
// only, so it's immune to the offset shift a deletion causes (the bug a cross-before/after comparison hits).
export function fusedTableCount(doc: string): number {
  let n = 0
  for (const r of tableRegions(doc)) {
    const delims = doc
      .slice(r.from, r.to)
      .split('\n')
      .filter((l) => parseDelimiter(l) !== null).length
    if (delims > 1) n++
  }
  return n
}

// Refuse deletions — and paste-shaped inserts — that would fuse two tables. Single-char typing passes
// through untouched (a typed row of dashes is content the user is building); a MULTI-LINE insert landing
// against a table is a paste, and letting it fuse mangles the pasted header + delimiter into body rows.
export const tableMergeGuard = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged) return tr
  let guarded = false
  tr.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
    if (toA > fromA || inserted.toString().includes('\n')) guarded = true
  })
  // Count the start doc FIRST so tableRegions' single-entry memo ends primed with newDoc — the decoration
  // build that follows a passing edit reparses newDoc and reuses it.
  if (
    guarded &&
    fusedTableCount(tr.startState.doc.toString()) < fusedTableCount(tr.newDoc.toString())
  ) {
    return [] // cancel — this edit would merge two tables into one
  }
  return tr
})
