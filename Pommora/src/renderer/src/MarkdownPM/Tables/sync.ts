import { Annotation } from '@codemirror/state'
import { tableRegions, modelFromRegion } from './regions'
import { cellToSource, serialize } from './codec'
import type { TableModel } from './model'

// Marks a transaction as the table widget editing its own source. The widget StateField remaps its
// decorations (keeping the widget + its focused cell editor mounted) instead of rebuilding from the doc;
// external edits carry no annotation, so they rebuild. This is what keeps cell focus across an edit.
export const tableSelfEdit = Annotation.define<boolean>()

export function cellCommitChange(
  docText: string,
  tableIndex: number,
  row: number,
  col: number,
  newText: string,
): { from: number; to: number; insert: string } | null {
  const seg = tableRegions(docText)[tableIndex]?.rows[row]?.segments[col]
  if (!seg) return null
  const insert = ` ${cellToSource(newText)} `
  return { from: seg[0], to: seg[1], insert }
}

export function structuralEditChange(
  docText: string,
  tableIndex: number,
  transform: (m: TableModel) => TableModel,
): { from: number; to: number; insert: string } | null {
  const region = tableRegions(docText)[tableIndex]
  if (!region) return null
  const insert = serialize(transform(modelFromRegion(region)))
  // A transform that serializes to the same text (reordering identical/empty columns, aligning to the
  // current alignment) is a no-op. Skip it: dispatching it would rebuild an eq-equal widget, CM would skip
  // the re-render, and a live drag — which relies on that re-render to clear — would freeze.
  if (insert === docText.slice(region.from, region.to)) return null
  return { from: region.from, to: region.to, insert }
}
