import { useRef, useState } from 'react'
import { Server, Eye, LayoutDashboard, Layers, ListFilter, ArrowUpDown, type LucideIcon } from 'lucide-react'
import { Icon } from '@renderer/design-system/symbols'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { topRowPad, paneSeparator, ICON } from './viewPane.css'
import { useSession } from '../../store'
import { findCollection, findSet, findCollectionForSet } from '../../Detail/Scope'
import { PropertiesPane } from './PropertiesPane'
import { HiddenPane } from './HiddenPane'
import { PaneSlider } from './PaneSlider'
import { MenuItem, MenuSeparator, MenuCaption, MenuTopRow } from '../../design-system/components/menu'
import { IconPicker } from '../IconPicker'
import { InlineEditHeader } from './InlineEditHeader'

type PaneId = 'properties' | 'visibility' | 'layout' | 'filter' | 'group' | 'sort'
interface MenuEntry {
  id: PaneId
  label: string
  Icon: LucideIcon
}

const ENTRIES: MenuEntry[] = [
  { id: 'properties', label: 'Properties', Icon: Server },
  { id: 'visibility', label: 'Visibility', Icon: Eye },
  { id: 'layout', label: 'Layout', Icon: LayoutDashboard },
  { id: 'group', label: 'Group', Icon: Layers },
  { id: 'filter', label: 'Filter', Icon: ListFilter },
  { id: 'sort', label: 'Sort', Icon: ArrowUpDown }
]
const PANE_LABEL = Object.fromEntries(ENTRIES.map((e) => [e.id, e.label])) as Record<PaneId, string>

/**
 * The Collection/Set view-settings menu — the content rendered inside the settings dropdown
 * (SettingsDropdown) when a Collection or Set is selected: an icon+title header (inline rename, icon
 * → IconPicker) over Properties · Visibility · Layout | Filter · Group · Sort as a push/back nav
 * stack. The dropdown shell (anchor + glass MenuSurface) and per-view routing live in SettingsDropdown.
 */
export function ViewPane(): React.JSX.Element | null {
  const selection = useSession((st) => st.selection)
  const tree = useSession((st) => st.tree)
  const submitRename = useSession((st) => st.submitRename)
  const [pane, setPane] = useState<PaneId | 'root'>('root')
  const lastDetail = useRef<PaneId>('properties')
  const [iconOpen, setIconOpen] = useState(false)

  const node =
    selection.kind === 'collection'
      ? findCollection(tree, selection.id)
      : selection.kind === 'set'
        ? findSet(tree, selection.id)
        : undefined
  if (!node) return null

  // Schema lives only on the Collection; a Set inherits its ancestor Collection's schema.
  const schemaCollection =
    selection.kind === 'collection'
      ? findCollection(tree, selection.id)
      : selection.kind === 'set'
        ? findCollectionForSet(tree, selection.id)
        : undefined

  const open = (id: PaneId): void => {
    lastDetail.current = id
    setPane(id)
  }
  const back = (): void => setPane('root')
  // Slot B keeps rendering the last-opened detail while sliding back, so it doesn't blank mid-retract.
  const detailId = pane === 'root' ? lastDetail.current : pane

  const pendingPane = (message: string): React.JSX.Element => (
    <>
      <MenuTopRow label="Settings" onClick={back} className={topRowPad} />
      <MenuSeparator flush className={paneSeparator} />
      <MenuCaption>{message}</MenuCaption>
    </>
  )

  const root = (
    <>
      <InlineEditHeader
        value={node.title}
        onIconClick={() => setIconOpen(true)}
        onCommit={(next) => void submitRename(node.path, node.kind, next)}
      />
      <MenuSeparator flush />
      {ENTRIES.map((e) => (
        <MenuItem
          key={e.id}
          className={flushTrailing}
          leading={<e.Icon size={ICON.rootEntry} />}
          trailing={<Icon name="chevron-right" size={ICON.rowChevron} />}
          onClick={() => open(e.id)}
        >
          {e.label}
        </MenuItem>
      ))}
    </>
  )

  const detail =
    detailId === 'properties' ? (
      schemaCollection ? (
        <PropertiesPane collectionPath={schemaCollection.path} schema={schemaCollection.properties ?? []} onBack={back} />
      ) : (
        pendingPane('Schema unavailable.')
      )
    ) : detailId === 'visibility' ? (
      schemaCollection ? (
        <HiddenPane source={node} schema={schemaCollection.properties ?? []} onBack={back} />
      ) : (
        pendingPane('Schema unavailable.')
      )
    ) : (
      pendingPane(`${PANE_LABEL[detailId]} — pending`)
    )

  return (
    <>
      <PaneSlider active={pane === 'root' ? 'a' : 'b'} slotA={root} slotB={detail} minWidth={225} minHeight={245} maxHeight={375} />
      <IconPicker open={iconOpen} onClose={() => setIconOpen(false)} />
    </>
  )
}
