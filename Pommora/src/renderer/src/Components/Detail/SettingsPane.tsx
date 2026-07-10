import { useRef, useState } from 'react'
import { Server, Eye, LayoutDashboard, Layers, ListFilter, ArrowUpDown, SlidersHorizontal, type LucideIcon } from 'lucide-react'
import type { OpenIn } from '@shared/types'
import { Icon } from '@renderer/design-system/symbols'
import { detail as detailText, flushTrailing, side } from '../../design-system/components/menu/menu.css'
import { ICON } from './settingsPane.css'
import { useSession } from '../../store'
import { findCollection, findSet, findCollectionForSet } from '../../Detail/Scope'
import { pickView } from '../../Detail/Views/Table/TableView'
import { PropertiesPane } from './PropertiesPane'
import { HiddenPane } from './HiddenPane'
import { GroupingPane } from './GroupingPane'
import { SortingPane } from './SortingPane'
import { ViewSettings } from './ViewSettings'
import { PaneSlider } from './PaneSlider'
import { MenuItem, MenuSeparator, MenuCaption, MenuPaneTopRow } from '../../design-system/components/menu'
import { IconPicker } from '../IconPicker'
import { InlineEditHeader } from './InlineEditHeader'

const isMac = navigator.platform.toLowerCase().includes('mac')

type PaneId = 'configuration' | 'properties' | 'visibility' | 'layout' | 'filter' | 'group' | 'sort'
interface MenuEntry {
  id: PaneId
  label: string
  Icon: LucideIcon
}

// Root order (A-3): Configuration · Properties · Visibility · Layout · Group · Filter · Sort.
const ENTRIES: MenuEntry[] = [
  { id: 'configuration', label: 'Configuration', Icon: SlidersHorizontal },
  { id: 'properties', label: 'Properties', Icon: Server },
  { id: 'visibility', label: 'Visibility', Icon: Eye },
  { id: 'layout', label: 'Layout', Icon: LayoutDashboard },
  { id: 'group', label: 'Group', Icon: Layers },
  { id: 'filter', label: 'Filter', Icon: ListFilter },
  { id: 'sort', label: 'Sort', Icon: ArrowUpDown }
]

// A detail pane's right-side breadcrumb — the entry label, but Group/Filter/Sort read the active tense.
const CURRENT_LABEL: Record<PaneId, string> = {
  configuration: 'Configuration',
  properties: 'Properties',
  visibility: 'Visibility',
  layout: 'Layout',
  group: 'Grouping',
  filter: 'Filtering',
  sort: 'Sorting'
}

/**
 * The Collection/Set settings menu — the content rendered inside the settings dropdown when a
 * Collection or Set is selected: an icon+title header over Configuration · Properties · Visibility ·
 * Layout · Group · Filter · Sort as a push/back nav stack. Layout opens the active view's ViewSettings
 * (the flat door); Configuration holds the collection's Open In.
 */
export function SettingsPane(): React.JSX.Element | null {
  const selection = useSession((st) => st.selection)
  const tree = useSession((st) => st.tree)
  const load = useSession((st) => st.load)
  const submitRename = useSession((st) => st.submitRename)
  const mutate = useSession((st) => st.mutate)
  const [pane, setPane] = useState<PaneId | 'root'>('root')
  const lastDetail = useRef<PaneId>('properties')
  const [iconOpen, setIconOpen] = useState(false)
  const iconRef = useRef<HTMLButtonElement>(null)

  const node =
    selection.kind === 'collection'
      ? findCollection(tree, selection.id)
      : selection.kind === 'set'
        ? findSet(tree, selection.id)
        : undefined
  const activeViewId = useSession((st) => st.activeViews[node?.id ?? ''])
  if (!node) return null

  // Schema lives only on the Collection; a Set inherits its ancestor Collection's schema.
  const schemaCollection = node.kind === 'collection' ? node : findCollectionForSet(tree, node.id)
  const schema = schemaCollection?.properties ?? []

  const open = (id: PaneId): void => {
    lastDetail.current = id
    setPane(id)
  }
  const back = (): void => setPane('root')
  const detailId = pane === 'root' ? lastDetail.current : pane

  // Open In is Collection-owned: a Set writes to (and reads from) its ancestor Collection.
  const openInValue: OpenIn = schemaCollection?.openIn ?? 'full-page'
  const setOpenIn = async (v: OpenIn): Promise<void> => {
    if (!schemaCollection) return
    await window.nexus.container.configure(schemaCollection.path, 'collection', { open_in: v })
    await load()
  }
  const pickOpenIn = async (): Promise<void> => {
    if (!isMac) return
    const v = await window.nexus.openInMenu(openInValue)
    if (v) await setOpenIn(v)
  }

  const blankLeaf = <MenuPaneTopRow label="Settings" current={CURRENT_LABEL[detailId]} onBack={back} />
  const schemaUnavailable = (
    <>
      <MenuPaneTopRow label="Settings" current={CURRENT_LABEL[detailId]} onBack={back} />
      <MenuCaption>Schema unavailable.</MenuCaption>
    </>
  )

  const configurationLeaf = (
    <>
      <MenuPaneTopRow label="Settings" current="Configuration" onBack={back} />
      <MenuItem
        className={flushTrailing}
        leading={<Icon name="layout-grid" size={ICON.rootEntry} />}
        trailing={
          <span className={side}>
            <span className={detailText}>{openInValue === 'page-preview' ? 'Preview' : 'Full Page'}</span>
            <Icon name="chevrons-up-down" size={ICON.rowChevron} />
          </span>
        }
        onClick={() => void pickOpenIn()}
      >
        Open In
      </MenuItem>
    </>
  )

  const root = (
    <>
      <InlineEditHeader
        value={node.title}
        icon={node.icon}
        iconRef={iconRef}
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
    detailId === 'configuration' ? (
      configurationLeaf
    ) : detailId === 'properties' ? (
      schemaCollection ? (
        <PropertiesPane collectionPath={schemaCollection.path} schema={schema} onBack={back} source={node} />
      ) : (
        schemaUnavailable
      )
    ) : detailId === 'visibility' ? (
      schemaCollection ? (
        <HiddenPane source={node} schema={schema} onBack={back} />
      ) : (
        schemaUnavailable
      )
    ) : detailId === 'layout' ? (
      <ViewSettings source={node} view={pickView(node, activeViewId, schema)} schema={schema} door="flat" onBack={back} onClose={back} />
    ) : detailId === 'group' ? (
      <GroupingPane source={node} view={pickView(node, activeViewId, schema)} schema={schema} label="Settings" onBack={back} />
    ) : detailId === 'sort' ? (
      <SortingPane source={node} view={pickView(node, activeViewId, schema)} schema={schema} label="Settings" onBack={back} />
    ) : (
      blankLeaf
    )

  return (
    <>
      <PaneSlider open={pane !== 'root'} root={root} detail={detail} minWidth={225} minHeight={245} />
      <IconPicker
        open={iconOpen}
        onClose={() => setIconOpen(false)}
        triggerRef={iconRef}
        value={node.icon}
        onSelect={(id) => void mutate({ op: 'setIcon', path: node.path, kind: node.kind, icon: id })}
      />
    </>
  )
}
