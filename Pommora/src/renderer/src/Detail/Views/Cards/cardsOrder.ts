// Pure card-order helpers — extracted so the drag/order seams are unit-testable off the React tree.
// The manual-order gate the pipeline sorter reads lives in pipeline/sort.ts (resolveManualOrder), shared
// with the table.

/** Move `activeId` into `overId`'s slot, returning a new array. A no-op copy when either id is
 *  absent or they're identical. Shared by the page in-band reorder and the Set-Card reorder. */
export function reorderIds(ids: string[], activeId: string, overId: string): string[] {
  const from = ids.indexOf(activeId)
  const to = ids.indexOf(overId)
  if (from === -1 || to === -1 || from === to) return [...ids]
  const next = [...ids]
  const [moved] = next.splice(from, 1)
  next.splice(to, 0, moved)
  return next
}
