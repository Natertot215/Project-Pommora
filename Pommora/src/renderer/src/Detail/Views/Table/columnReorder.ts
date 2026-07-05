import { reorder } from '@renderer/design-system/interactions/drag'

/**
 * Translate a header drag into a new `property_order` (E-2). The visible columns reorder; any hidden
 * property (present in `property_order` but filtered out of the rendered columns) is preserved at the
 * tail so a later hide/show toggle can't drop it — the exact Swift persistence failure H-2 guards.
 *
 * The full visible order is written explicitly, so default-on reserved columns (tiers, title) persist
 * the slot they were dragged to instead of snapping back to their resolver-default placement.
 */
export function reorderColumns(
  visibleIds: string[],
  propertyOrder: string[],
  activeId: string,
  overId: string
): string[] {
  const next = reorder(
    visibleIds.map((id) => ({ id })),
    activeId,
    overId
  ).map((o) => o.id)
  const hidden = propertyOrder.filter((id) => !visibleIds.includes(id))
  return [...next, ...hidden]
}
