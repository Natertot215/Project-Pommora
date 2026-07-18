// The view-mint machinery (G-1): entry-mint is the SOLE place a container's default view is born.
// On landing a view-bearing container whose views[] is empty, `ensureContainerView` mints once (an
// in-flight map keyed by container id guards a re-select from double-firing). Every other view writer
// routes through `saveViewAdopting` — a sentinel-holding write awaits the in-flight mint and saves
// against the real id, never minting its own. Store-free: the mint/adopt paths' refetch (load)
// re-hydrates the activeViews slice from disk, so no writer here needs the store; ordinary saves
// are confirmed by the live watcher's push alone.
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { DEFAULT_VIEW_ID, mintDefaultView, type SavedView } from '@shared/views'

const inFlight = new Map<string, Promise<string>>()

/** The promise a sentinel-holding writer awaits — the minted real id, or undefined if not minting. */
export const pendingViewMint = (containerId: string): Promise<string> | undefined =>
  inFlight.get(containerId)

/** Mint the default view once for an empty view-bearing container, then refetch. No-op when the
 *  container already has views or a mint is already in flight (the re-select guard). */
export function ensureContainerView(
  source: CollectionNode | SetNode,
  schema: PropertyDefinition[],
  refetch: () => Promise<void>,
): void {
  if ((source.views?.length ?? 0) > 0 || inFlight.has(source.id)) return
  const mint = (async () => {
    const res = await window.nexus.views.save(source.path, source.kind, mintDefaultView(schema))
    if (!res.ok) throw new Error(res.error)
    // A refetch failure must NOT un-guard: the view IS on disk, so re-minting would double it. The
    // stale tree self-heals on the next successful load; the guard stays so no second default is born.
    await refetch().catch(() => {})
    return res.id
  })()
  inFlight.set(source.id, mint)
  // Clear the guard ONLY when the save itself failed (allow a retry); a successful mint keeps it.
  void mint.catch(() => inFlight.delete(source.id))
}

/** The ONE view writer every surface calls. A sentinel-holding write adopts the in-flight mint's real
 *  id (never mints its own); a real id saves directly. On a sentinel save it also adopts the id as the
 *  active view so the writer's edits stay on the view the user sees (that refetch re-hydrates the
 *  activeViews slice — the one state the watcher push doesn't carry). An ordinary save skips the
 *  immediate refetch entirely: the sidecar write trips the live watcher, whose stabilized
 *  `nexus:changed` push is the single canonical confirm — an explicit load() here was a second
 *  full walk on every view write (and a visible double repaint on the glass chrome). */
export async function saveViewAdopting(
  source: CollectionNode | SetNode,
  view: SavedView,
  refetch: () => Promise<void>,
): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  let toSave = view
  if (view.id === DEFAULT_VIEW_ID) {
    const minted = await pendingViewMint(source.id)?.catch(() => undefined)
    if (minted) toSave = { ...view, id: minted }
  }
  const res = await window.nexus.views.save(source.path, source.kind, toSave)
  if (res.ok && toSave.id === DEFAULT_VIEW_ID) {
    await window.nexus.activeViews.set(source.id, res.id)
    await refetch()
  }
  return res
}
