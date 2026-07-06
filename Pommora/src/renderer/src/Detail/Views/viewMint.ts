// The view-mint machinery (G-1): entry-mint is the SOLE place a container's default view is born.
// On landing a view-bearing container whose views[] is empty, `ensureContainerView` mints once (an
// in-flight map keyed by container id guards a re-select from double-firing). Every other view writer
// routes through `saveViewAdopting` — a sentinel-holding write awaits the in-flight mint and saves
// against the real id, never minting its own. Store-free: the refetch (load) re-hydrates the
// activeViews slice from disk, so no writer here needs the store.
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { DEFAULT_VIEW_ID, mintDefaultView, type SavedView } from '@shared/views'

const inFlight = new Map<string, Promise<string>>()

/** The promise a sentinel-holding writer awaits — the minted real id, or undefined if not minting. */
export const pendingViewMint = (containerId: string): Promise<string> | undefined => inFlight.get(containerId)

/** Mint the default view once for an empty view-bearing container, then refetch. No-op when the
 *  container already has views or a mint is already in flight (the re-select guard). */
export function ensureContainerView(
  source: CollectionNode | SetNode,
  schema: PropertyDefinition[],
  refetch: () => Promise<void>
): void {
  if ((source.views?.length ?? 0) > 0 || inFlight.has(source.id)) return
  const mint = (async () => {
    const res = await window.nexus.views.save(source.path, source.kind, mintDefaultView(schema))
    if (!res.ok) throw new Error(res.error)
    await refetch()
    return res.id
  })()
  inFlight.set(source.id, mint)
  void mint.catch(() => {}).finally(() => inFlight.delete(source.id))
}

/** The ONE view writer every surface calls. A sentinel-holding write adopts the in-flight mint's real
 *  id (never mints its own); a real id saves directly. On a sentinel save it also adopts the id as the
 *  active view so the writer's edits stay on the view the user sees (the refetch re-hydrates the slice). */
export async function saveViewAdopting(
  source: CollectionNode | SetNode,
  view: SavedView,
  refetch: () => Promise<void>
): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  let toSave = view
  if (view.id === DEFAULT_VIEW_ID) {
    const minted = await pendingViewMint(source.id)?.catch(() => undefined)
    if (minted) toSave = { ...view, id: minted }
  }
  const res = await window.nexus.views.save(source.path, source.kind, toSave)
  if (res.ok && toSave.id === DEFAULT_VIEW_ID) await window.nexus.activeViews.set(source.id, res.id)
  await refetch()
  return res
}
