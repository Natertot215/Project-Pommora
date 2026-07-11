// The shared active-view hook: reads the container's active view id from the store slice (reactive to
// every switch) and resolves it through pickView. One source for the ViewDropdown button, the ViewPane
// list, ViewSettings' flat door, HiddenPane, and the table — no per-surface fetch effect to drift.
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { SavedView } from '@shared/views'
import { useSession } from '../../store'
import { useViewEmbedScope } from '@renderer/Embeds/ViewEmbedScope'
import { pickView } from './Table/TableView'

export function useActiveView(
  source: CollectionNode | SetNode,
  schema: PropertyDefinition[]
): { activeViewId: string | undefined; view: SavedView } {
  // Inside a view embed the tile payload IS the view (C-1: per-instance, never the
  // global slot) — the slot read stays unconditional to keep hook order stable.
  const scope = useViewEmbedScope()
  const activeViewId = useSession((s) => s.activeViews[source.id])
  if (scope) return { activeViewId: scope.view.id, view: scope.view }
  return { activeViewId, view: pickView(source, activeViewId, schema) }
}
