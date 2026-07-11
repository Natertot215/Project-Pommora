import { useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import type { ViewBlockEntry } from '@shared/blocks'
import type { CollectionNode, NexusTree, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { mintDefaultView, type SavedView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { MenuSurface } from '@renderer/design-system/components/menu'
import { useDismiss } from '@renderer/design-system/components/Popover'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import { findCollection, findCollectionForSet, findSet } from '@renderer/Detail/Scope'
import { TableView } from '@renderer/Detail/Views/Table/TableView'
import { SettingsPane } from '@renderer/Components/Detail/SettingsPane'
import { ViewEmbedScopeProvider } from '@renderer/Embeds/ViewEmbedScope'
import { useSession } from '@renderer/store'
import * as s from './viewEmbed.css'

/** The copied config is ours by construction; a foreign or malformed one degrades to
 *  the blank default rather than crashing the tile (repair-not-reject). */
function coerceConfig(raw: unknown, schema: PropertyDefinition[]): SavedView {
  const v = raw as SavedView | null
  const ok = typeof v === 'object' && v !== null && typeof v.id === 'string' && typeof v.name === 'string' && typeof v.type === 'string'
  return ok ? v : mintDefaultView(schema)
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
  const presence = useExitPresence(cfgOpen)
  const btnRef = useRef<HTMLButtonElement>(null)
  const popRef = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ top: number; right: number } | null>(null)
  useDismiss(popRef, () => setCfgOpen(false), cfgOpen)

  const index = Math.min(entry.active ?? 0, entry.views.length - 1)
  const embedded = entry.views[index]
  const source: CollectionNode | SetNode | undefined = embedded && tree
    ? (findCollection(tree, embedded.source_id) ?? findSet(tree, embedded.source_id))
    : undefined
  if (!embedded || !source || !tree) return <div className="blk-inert" /> // dead source — inert, space holds (E-2)

  const schemaCollection = source.kind === 'collection' ? source : findCollectionForSet(tree, source.id)
  const view = coerceConfig(embedded.config, schemaCollection?.properties ?? [])
  const persistConfig = (next: SavedView): void => persistViewConfig(entry.id, index, next)

  const openConfig = (): void => {
    const r = btnRef.current?.getBoundingClientRect()
    if (r) setPos({ top: r.bottom + 6, right: Math.max(8, window.innerWidth - r.right - 8) })
    setCfgOpen(true)
  }

  return (
    <ViewEmbedScopeProvider value={{ source, view, persistConfig }}>
      <div className={s.tile}>
        <div className={s.head}>
          <Icon name={iconNameOr(view.icon, 'table')} size={13} />
          <span className={s.title}>{entry.display_title ?? source.title}</span>
          <button ref={btnRef} type="button" className={s.configBtn} aria-label="View settings" onClick={openConfig}>
            <Icon name="sliders-horizontal" size={14} />
          </button>
        </div>
        <div className={s.body}>
          <TableView key={source.id} source={source} />
        </div>
        {presence.mounted && pos !== null
          ? createPortal(
              <div ref={popRef} className={s.pop} style={{ top: pos.top, right: pos.right }}>
                <MenuSurface closing={presence.closing} notchInsetRight={16}>
                  <SettingsPane />
                </MenuSurface>
              </div>,
              document.body
            )
          : null}
      </div>
    </ViewEmbedScopeProvider>
  )
}
