// The C-1 seam: inside a view-embed tile, view resolution reads the tile payload and
// every view-CONFIG write lands on the payload (D-12: copied, never synced) — the
// source's saved views, per-machine active slot, and container config are untouchable
// from scope. Gating is by EFFECT: surfaces write through useSaveView, which routes on
// the scope's presence; outside a scope everything behaves exactly as before.

import { createContext, useContext } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { SavedView } from '@shared/views'
import { saveViewAdopting } from '@renderer/Detail/Views/viewMint'

export interface ViewEmbedScopeValue {
  source: CollectionNode | SetNode
  view: SavedView
  /** Persist the tile's copied config — writes the block payload via the saveBlocks updater. */
  persistConfig: (next: SavedView) => void
}

const Ctx = createContext<ViewEmbedScopeValue | null>(null)
export const ViewEmbedScopeProvider = Ctx.Provider
export const useViewEmbedScope = (): ViewEmbedScopeValue | null => useContext(Ctx)

/** The one view-config writer surfaces call: in scope the write is a payload update
 *  (the sentinel/mint/active-slot machinery never runs); outside, the adopt-and-save
 *  path unchanged. The scope's `view` may be stale mid-gesture, so callers still pass
 *  the full next view, exactly as they did to saveViewAdopting. */
export function useSaveView(
  source: CollectionNode | SetNode,
  refetch: () => Promise<void>
): (view: SavedView) => Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const scope = useViewEmbedScope()
  if (scope) {
    return (view) => {
      scope.persistConfig(view)
      return Promise.resolve({ ok: true as const, id: view.id })
    }
  }
  return (view) => saveViewAdopting(source, view, refetch)
}
