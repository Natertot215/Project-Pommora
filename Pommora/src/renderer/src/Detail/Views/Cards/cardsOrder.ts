// Pure card-order helpers — extracted so the drag/order seams are unit-testable off the React tree
// (the pipeline sorter reads viewOrders as its lowest-priority tiebreaker).

/** The per-view manual card order fed to the sorter (the table's gate, verbatim): an active drag
 *  override always wins; otherwise the persisted per-machine order applies only when the view is
 *  sorted or grouped — on a plain view viewOrders is not a primary order, matching the table. */
export function resolveManualOrder(
  sortedOrGrouped: boolean,
  manualOverride: string[] | null,
  viewOrder: string[] | undefined,
): string[] | undefined {
  if (!sortedOrGrouped && !manualOverride) return undefined
  return manualOverride ?? viewOrder
}

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
