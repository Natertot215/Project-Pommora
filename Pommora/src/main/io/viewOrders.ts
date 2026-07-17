// The per-machine sorted/grouped manual-order cache: `.nexus/viewOrders.json`, keyed by view id → the
// ordered page-id list used as the lowest-priority tiebreaker under a sort (Part 2 D-5). Kept local
// (NOT the synced sidecar's views[]) so a sorted-view drag never moves the portable `page_order` nor
// churns the container's modified_at. Inside `.nexus/` it's outside the content walk + body-sync —
// per-machine by construction. Mirrors activeViews.ts / folds.ts.
import { mkdir } from 'node:fs/promises'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'
import { serializeOnFile } from './fileLock'

/** view id → manual page-id order (the sort tiebreaker). */
export type ViewOrders = Record<string, string[]>

const viewOrdersPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.viewOrders)

/** Lenient read: absent / corrupt → `{}`; keeps only string-array entries (string members only). */
export async function readViewOrders(root: string): Promise<ViewOrders> {
  const obj = await readJsonObject(viewOrdersPath(root))
  if (obj === null) return {}
  const out: ViewOrders = {}
  for (const [viewId, order] of Object.entries(obj)) {
    if (Array.isArray(order)) out[viewId] = order.filter((x): x is string => typeof x === 'string')
  }
  return out
}

/** Set (or, with an empty array, clear) the manual order for a view; leaves other views intact.
 *  Serialized on the file so two overlapping writes can't lose each other's read-merge-write. */
export async function writeViewOrders(
  root: string,
  viewId: string,
  order: string[],
): Promise<void> {
  await serializeOnFile(viewOrdersPath(root), async () => {
    const current = await readViewOrders(root)
    if (order.length === 0) delete current[viewId]
    else current[viewId] = order
    await mkdir(nexusDir(root), { recursive: true })
    await writeJson(viewOrdersPath(root), current)
  })
}
