// Verbatim TS port of the Swift OrderResolver semantics.
// - no/empty persisted order  -> sort by id ascending (ULIDs are time-sortable)
// - persisted array           -> known-in-array-order (tombstones dropped),
//                                then unreferenced appended by title (localeCompare)

export interface Orderable {
  id: string
  title: string
}

/**
 * @param fallback when there's no persisted order: 'id' (ULID = creation order,
 *   the Swift default) or 'title' (for adopted entities whose ids are hashes).
 */
export function resolveOrder<T extends Orderable>(
  items: T[],
  order: string[] | undefined,
  fallback: 'id' | 'title' = 'id',
): T[] {
  if (!order || order.length === 0) {
    return [...items].sort((a, b) =>
      fallback === 'title' ? a.title.localeCompare(b.title) : a.id.localeCompare(b.id),
    )
  }

  const byId = new Map(items.map((i) => [i.id, i]))
  const known: T[] = []
  for (const id of order) {
    const it = byId.get(id)
    if (it) {
      known.push(it)
      byId.delete(id) // consume so it can't also land in the tail
    }
  }
  const rest = [...byId.values()].sort((a, b) => a.title.localeCompare(b.title))
  return [...known, ...rest]
}
