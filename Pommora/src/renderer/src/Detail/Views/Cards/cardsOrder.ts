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
