import { useRef, useState } from 'react'
import type { ViewBlockEntry } from '@shared/blocks'
import type { CollectionNode, NexusTree, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { DEFAULT_VIEW_ID, mintDefaultView, type SavedView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import { findCollection, findCollectionForSet, findSet } from '@renderer/Detail/Scope'
import { TableView } from '@renderer/Detail/Views/Table/TableView'
import { SettingsPane } from '@renderer/Components/Detail/SettingsPane'
import { ViewEmbedScopeProvider } from '@renderer/Embeds/ViewEmbedScope'
import { useSession } from '@renderer/store'
import * as s from './viewEmbed.css'

/** The copied config is ours by construction; a foreign or malformed one degrades to the
 *  blank default (repair-not-reject). Every degrade path re-stamps `fallbackId` — a repaired
 *  config must never carry the DEFAULT_VIEW_ID sentinel (it keys viewOrders per-machine and
 *  would persist on the next config edit), and never a random id (coerce runs per render). */
function coerceConfig(raw: unknown, schema: PropertyDefinition[], fallbackId: string): SavedView {
  const v = raw as SavedView | null
  const shapeOk =
    typeof v === 'object' &&
    v !== null &&
    typeof v.id === 'string' &&
    typeof v.name === 'string' &&
    typeof v.type === 'string' &&
    (['property_order', 'hidden_properties', 'sort'] as const).every((k) => v[k] === undefined || Array.isArray(v[k]))
  if (!shapeOk) return { ...mintDefaultView(schema), id: fallbackId }
  return v.id === DEFAULT_VIEW_ID ? { ...v, id: fallbackId } : v
}

// The view-embed tile (H-4/H-5): the H-5 header (title + the config affordance; the
// switcher row collapses while the tile holds one view) over the REAL TableView at the
// fixed embed zoom, all inside the ViewEmbedScope — resolution reads the payload
// config, config writes land on it, data writes flow through to the source (D-12).
export function ViewEmbedBlock({
  entry,
  persistViewConfig
}: {
  entry: ViewBlockEntry
  persistViewConfig: (entryId: string, index: number, config: SavedView) => void
}): React.JSX.Element {
  const tree = useSession((st) => st.tree)
  const [cfgOpen, setCfgOpen] = useState(false)
  const btnRef = useRef<HTMLButtonElement>(null)

  const index = Math.min(entry.active ?? 0, entry.views.length - 1)
  const embedded = entry.views[index]
  const source: CollectionNode | SetNode | undefined =
    embedded && tree ? (findCollection(tree, embedded.source_id) ?? findSet(tree, embedded.source_id)) : undefined
  if (!embedded || !source || !tree) return <div className="blk-inert" /> // dead source — inert, space holds (E-2)

  const schemaCollection = source.kind === 'collection' ? source : findCollectionForSet(tree, source.id)
  const view = coerceConfig(embedded.config, schemaCollection?.properties ?? [], `embed:${entry.id}:${index}`)
  const persistConfig = (next: SavedView): void => persistViewConfig(entry.id, index, next)

  return (
    <ViewEmbedScopeProvider value={{ source, view, persistConfig }}>
      <div className={s.tile}>
        <div className={s.head}>
          <Icon name={iconNameOr(view.icon, 'table')} size={13} />
          <span className={s.title}>{entry.display_title ?? source.title}</span>
          <button ref={btnRef} type="button" className={s.configBtn} aria-label="View settings" onClick={() => setCfgOpen(true)}>
            <Icon name="sliders-horizontal" size={14} />
          </button>
        </div>
        <div className={s.body}>
          <TableView key={source.id} source={source} />
        </div>
        {/* PickerMenu owns the anchoring — body portal (H-11), scroll/resize re-measure,
            collision flip; a hand-rolled fixed portal detaches when the surface scrolls. */}
        <PickerMenu open={cfgOpen} onDismiss={() => setCfgOpen(false)} triggerRef={btnRef}>
          <SettingsPane />
        </PickerMenu>
      </div>
    </ViewEmbedScopeProvider>
  )
}
