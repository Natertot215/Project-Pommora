import { useRef, useState } from 'react'
import {
  Server,
  Eye,
  LayoutDashboard,
  Layers,
  ListFilter,
  ArrowUpDown,
  SlidersHorizontal,
  type LucideIcon,
} from 'lucide-react'
import type { OpenIn } from '@shared/types'
import { Icon, defaultEntityIcon, iconNameOr } from '@renderer/design-system/symbols'
import {
  detail as detailText,
  flushTrailing,
  footingSymbol,
  side,
} from '../../design-system/components/menu/menu.css'
import {
  crumbRow,
  footerLock,
  footerLockActive,
  ICON,
  switchScale,
  toggleRow,
} from './settingsPane.css'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { cx } from '../../design-system/cx'
import { useSession } from '../../store'
import { findCollection, findSet, findCollectionForSet } from '../../Detail/Scope'
import { pickView } from '../../Detail/Views/Table/TableView'
import { PropertiesPane } from './PropertiesPane'
import { HiddenPane } from './HiddenPane'
import { GroupingPane } from './GroupingPane'
import { SortingPane } from './SortingPane'
import { ViewSettings } from './ViewSettings'
import { PaneSlider } from './PaneSlider'
import {
  AccessoryButton,
  MenuBottomRow,
  MenuItem,
  MenuScrollFrame,
  MenuSeparator,
  MenuCaption,
  MenuPaneTopRow,
} from '../../design-system/components/menu'
import { IconPicker } from '../IconPicker'
import { InlineEditHeader } from './InlineEditHeader'
import { useViewEmbedScope } from '@renderer/Embeds/ViewEmbedScope'

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
  { id: 'sort', label: 'Sort', Icon: ArrowUpDown },
]

// A detail pane's right-side breadcrumb — the entry label, but Group/Filter/Sort read the active tense.
const CURRENT_LABEL: Record<PaneId, string> = {
  configuration: 'Configuration',
  properties: 'Properties',
  visibility: 'Visibility',
  layout: 'Layout',
  group: 'Grouping',
  filter: 'Filtering',
  sort: 'Sorting',
}

/**
 * The Collection/Set settings menu — the content rendered inside the settings dropdown when a
 * Collection or Set is selected: an icon+title header over Configuration · Properties · Visibility ·
 * Layout · Group · Filter · Sort as a push/back nav stack. Layout opens the active view's ViewSettings
 * (the flat door); Configuration holds the collection's Open In.
 */
export function SettingsPane(): React.JSX.Element | null {
  const selection = useSession((st) => st.selection)
  const defaultIcons = useSession((st) => st.personalization.defaultIcons)
  const tree = useSession((st) => st.tree)
  const load = useSession((st) => st.load)
  const setPersonalization = useSession((st) => st.setPersonalization)
  const connectionsInPreview = useSession(
    (st) => st.personalization.connectionsOpenInPreview ?? false,
  )
  const submitRename = useSession((st) => st.submitRename)
  const mutate = useSession((st) => st.mutate)
  const [pane, setPane] = useState<PaneId | 'root'>('root')
  const lastDetail = useRef<PaneId>('properties')
  const [iconOpen, setIconOpen] = useState(false)
  const iconRef = useRef<HTMLButtonElement>(null)

  // In a view embed the ENTIRE node derivation goes scope-first — the selection names
  // whatever the sidebar has open, not the embed's source; and the pane is a view-config
  // surface there: view-identity header, no Configuration leaf, config writes → payload.
  const scope = useViewEmbedScope()
  const selectionNode =
    selection.kind === 'collection'
      ? findCollection(tree, selection.id)
      : selection.kind === 'set'
        ? findSet(tree, selection.id)
        : undefined
  const node = scope?.source ?? selectionNode
  const activeViewId = useSession((st) => st.activeViews[node?.id ?? ''])
  if (!node) return null

  // Schema lives only on the Collection; a Set inherits its ancestor Collection's schema.
  const schemaCollection = node.kind === 'collection' ? node : findCollectionForSet(tree, node.id)
  const schema = schemaCollection?.properties ?? []
  const view = scope?.view ?? pickView(node, activeViewId, schema)
  const entries = scope
    ? ENTRIES.filter((e) => e.id !== 'configuration' && e.id !== 'filter')
    : ENTRIES

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

  const blankLeaf = (
    <MenuPaneTopRow label="Settings" current={CURRENT_LABEL[detailId]} onBack={back} />
  )
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
            <span className={detailText}>
              {openInValue === 'page-preview' ? 'Preview' : 'Full Page'}
            </span>
            <Icon name="chevrons-up-down" size={ICON.rowChevron} />
          </span>
        }
        onClick={() => void pickOpenIn()}
      >
        Open In
      </MenuItem>
      {/* B-6 — nexus-wide (Personalization, not this collection's config): wiki-link clicks
          route to the Page Preview window instead of navigating; ⌘-click takes the other route. */}
      <MenuItem
        className={cx(flushTrailing, toggleRow)}
        leading={<Icon name="app-window-mac" size={ICON.rootEntry} />}
        trailing={
          <span className={switchScale}>
            <Switch
              checked={connectionsInPreview}
              onChange={(next) => setPersonalization('connectionsOpenInPreview', next)}
              ariaLabel="Connections Open In Preview"
            />
          </span>
        }
      >
        Connections Open In Preview
      </MenuItem>
    </>
  )

  const root = (
    <>
      <InlineEditHeader
        value={scope ? view.name : node.title}
        icon={
          scope
            ? iconNameOr(view.icon, 'table')
            : iconNameOr(node.icon, defaultEntityIcon(node.kind, defaultIcons))
        }
        iconRef={iconRef}
        onIconClick={() => setIconOpen(true)}
        onCommit={(next) => {
          // The header is the VIEW's identity in scope (G-6/H-5) — renaming the source
          // folder from an embed is exactly the mutation the scope exists to prevent.
          if (scope) {
            if (next && next !== view.name) scope.persistConfig({ ...view, name: next })
          } else void submitRename(node.path, node.kind, next)
        }}
      />
      <MenuSeparator flush />
      {entries.map((e) => (
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

  // The scoped footer follows the house footing (ViewPane / PropertiesPane): a
  // MenuBottomRow in the scroll frame's footer slot, footing-toned content, the B-5
  // config lock as a 12-in-20 AccessoryButton — pressed while it freezes the view config.
  const scopedRoot = scope && schemaCollection && (
    <MenuScrollFrame
      footer={
        <MenuBottomRow
          leading={
            <span className={crumbRow}>
              <span className={footingSymbol}>
                <Icon
                  name={iconNameOr(
                    schemaCollection.icon,
                    defaultEntityIcon('collection', defaultIcons),
                  )}
                  size={12}
                />
              </span>
              <span>{schemaCollection.title}</span>
              {node.kind === 'set' && (
                <>
                  <span>›</span>
                  <span className={footingSymbol}>
                    <Icon
                      name={iconNameOr(node.icon, defaultEntityIcon('set', defaultIcons))}
                      size={12}
                    />
                  </span>
                  <span>{node.title}</span>
                </>
              )}
            </span>
          }
          trailing={
            <AccessoryButton
              icon="lock"
              size={12}
              box={20}
              ariaLabel={scope.locked ? 'Unlock view configuration' : 'Lock view configuration'}
              className={scope.locked ? `${footerLock} ${footerLockActive}` : footerLock}
              onClick={() => scope.setLocked(!scope.locked)}
            />
          }
        />
      }
    >
      {root}
    </MenuScrollFrame>
  )

  const detail =
    detailId === 'configuration' ? (
      configurationLeaf
    ) : detailId === 'properties' ? (
      schemaCollection ? (
        <PropertiesPane
          collectionPath={schemaCollection.path}
          schema={schema}
          onBack={back}
          source={node}
        />
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
      <ViewSettings
        source={node}
        view={view}
        schema={schema}
        door="flat"
        onBack={back}
        onClose={back}
      />
    ) : detailId === 'group' ? (
      <GroupingPane source={node} view={view} schema={schema} label="Settings" onBack={back} />
    ) : detailId === 'sort' ? (
      <SortingPane source={node} view={view} schema={schema} label="Settings" onBack={back} />
    ) : (
      blankLeaf
    )

  return (
    <>
      <PaneSlider
        open={pane !== 'root'}
        root={scopedRoot || root}
        detail={detail}
        minWidth={225}
        minHeight={245}
      />
      <IconPicker
        open={iconOpen}
        onClose={() => setIconOpen(false)}
        triggerRef={iconRef}
        value={scope ? view.icon : node.icon}
        onSelect={(id) => {
          if (scope) scope.persistConfig({ ...view, icon: id })
          else void mutate({ op: 'setIcon', path: node.path, kind: node.kind, icon: id })
        }}
      />
    </>
  )
}
