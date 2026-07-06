import { useRef, useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { DEFAULT_VIEW_ID, type SavedView, type ViewFormat, type ViewType } from '@shared/views'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import { MenuItem, MenuSeparator, MenuPaneTopRow, MenuScrollFrame, AccessoryButton } from '../../design-system/components/menu'
import { detail, flushTrailing, side } from '../../design-system/components/menu/menu.css'
import { PickerMenu } from '../../design-system/components/PickerMenu'
import { useSession } from '../../store'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { InlineEditHeader } from './InlineEditHeader'
import { VisibilityList } from './HiddenPane'
import { LayoutToggles } from './LayoutToggles'
import { cx } from '../../design-system/cx'
import * as vs from './viewSettings.css'

// Grid order (D-4) + each type's glyph (D-5). Only Table is buildable this cycle; the rest render at
// full weight but their tiles are inert.
const TYPE_ORDER: ViewType[] = ['table', 'cards', 'list', 'gallery', 'calendar', 'timeline']
const TYPE_GLYPH: Record<ViewType, IconName> = {
  table: 'table',
  cards: 'cards-grid',
  list: 'list-rounded',
  gallery: 'layout-dashboard',
  calendar: 'calendar-days',
  timeline: 'chart-gantt'
}
const IMPLEMENTED: ReadonlySet<ViewType> = new Set(['table'])
const isMac = navigator.platform.toLowerCase().includes('mac')

// The full-door config leaves below the grid — same rows the SettingsPane carries, so the view config
// is reachable without the dropdown (the future Toolbar mode). Layout opens the visibility list; the
// rest ship blank-leafed. Right-side breadcrumb reads the active tense.
type Leaf = 'layout' | 'group' | 'filter' | 'sort'
const LEAF_ROWS: { id: Leaf; label: string; icon: IconName }[] = [
  { id: 'layout', label: 'Layout', icon: 'layout-dashboard' },
  { id: 'group', label: 'Group', icon: 'layers' },
  { id: 'filter', label: 'Filter', icon: 'list-filter' },
  { id: 'sort', label: 'Sort', icon: 'arrow-up-down' }
]
const LEAF_CURRENT: Record<Exclude<Leaf, 'layout'>, string> = { group: 'Grouping', filter: 'Filtering', sort: 'Sorting' }

/**
 * ViewSettings — the shared per-view editor, both doors (D-1). The full door (a ViewPane row's
 * chevron) carries the ⋮ (Duplicate/Delete) + the Layout/Group/Filter/Sort leaf rows; the flat door
 * (SettingsPane → Layout) drops the ⋮ and the leaf rows and reads `Settings · Layout`. Both frame the
 * same body — title + type grid (+ the flat door's icon toggles) — with the Format control pinned as
 * the footer so it holds while the body scrolls. `onClose` closes the whole dropdown.
 */
export function ViewSettings({
  source,
  view,
  schema,
  door,
  onBack,
  onClose
}: {
  source: CollectionNode | SetNode
  view: SavedView
  schema: PropertyDefinition[]
  door: 'full' | 'flat'
  onBack: () => void
  onClose: () => void
}): React.JSX.Element {
  const load = useSession((s) => s.load)
  const [leaf, setLeaf] = useState<Leaf | null>(null)
  const [formatOpen, setFormatOpen] = useState(false)
  const formatRef = useRef<HTMLDivElement>(null)
  const views = source.views ?? []
  const canDelete = views.length > 1 && view.id !== DEFAULT_VIEW_ID
  const format: ViewFormat = view.format ?? 'standard'

  const write = (patch: Partial<SavedView>): void => void saveViewAdopting(source, { ...view, ...patch }, load)
  const rename = (name: string): void => {
    if (name && name !== view.name) write({ name })
  }
  const setType = (type: ViewType): void => {
    if (type !== view.type) write({ type })
  }
  const setFormat = (f: ViewFormat): void => write({ format: f })

  const openItemMenu = async (): Promise<void> => {
    const action = await window.nexus.viewItemMenu(canDelete)
    if (action === 'view:duplicate') {
      const res = await window.nexus.views.save(source.path, source.kind, { ...view, id: DEFAULT_VIEW_ID })
      if (res.ok) {
        const ids = views.map((v) => v.id).filter((id) => id !== res.id)
        const at = ids.indexOf(view.id)
        ids.splice(at < 0 ? ids.length : at + 1, 0, res.id)
        await window.nexus.views.reorder(source.path, source.kind, ids)
      }
      await load()
    } else if (action === 'view:delete') {
      await window.nexus.views.delete(source.path, source.kind, view.id)
      onClose()
      await load()
    }
  }

  const openFormat = async (): Promise<void> => {
    if (isMac) {
      const f = await window.nexus.viewFormatMenu(format)
      if (f) setFormat(f)
    } else {
      setFormatOpen(true)
    }
  }

  // Full-door leaves. Layout opens the visibility list (+ its icon toggles); Group/Filter/Sort ship
  // blank, matching the SettingsPane's — the shared panes land in their own arcs.
  if (leaf === 'layout') {
    return (
      <VisibilityList
        source={source}
        schema={schema}
        view={view}
        label="Views"
        current="Layout"
        onBack={() => setLeaf(null)}
        footer={<LayoutToggles source={source} view={view} />}
      />
    )
  }
  if (leaf) {
    return <MenuPaneTopRow label="Views" current={LEAF_CURRENT[leaf]} onBack={() => setLeaf(null)} />
  }

  const title = <InlineEditHeader value={view.name} onCommit={rename} onIconClick={() => {}} />
  const grid = (
    <div className={vs.grid}>
      {TYPE_ORDER.map((t) => (
        <button
          key={t}
          type="button"
          className={cx(vs.tile, t === view.type && vs.tileSelected)}
          aria-label={t}
          onClick={() => IMPLEMENTED.has(t) && setType(t)}
        >
          <Icon name={TYPE_GLYPH[t]} size={20} />
        </button>
      ))}
    </div>
  )

  // Format — the pinned footer (D-8): persists, dual-wired (native menu on mac, PickerMenu else), inert
  // visually this cycle. Table-only.
  const formatRow =
    view.type === 'table' ? (
      <div ref={formatRef}>
        <MenuItem
          className={flushTrailing}
          leading={<Icon name="layers-2" size={16} />}
          trailing={
            <span className={side}>
              <span className={detail}>{format === 'compact' ? 'Compact' : 'Standard'}</span>
              <Icon name="chevrons-up-down" size={16} />
            </span>
          }
          onClick={() => void openFormat()}
        >
          Format
        </MenuItem>
        {formatOpen && (
          <PickerMenu open={formatOpen} onDismiss={() => setFormatOpen(false)} triggerRef={formatRef}>
            {(['standard', 'compact'] as ViewFormat[]).map((f) => (
              <button
                key={f}
                type="button"
                onClick={() => {
                  setFormat(f)
                  setFormatOpen(false)
                }}
              >
                {f === 'compact' ? 'Compact' : 'Standard'}
              </button>
            ))}
          </PickerMenu>
        )}
      </div>
    ) : null

  const header =
    door === 'full' ? (
      <MenuPaneTopRow
        label="Views"
        onBack={onBack}
        trailing={
          <AccessoryButton icon="ellipsis-vertical" size={14} box={20} ariaLabel="View menu" onClick={() => void openItemMenu()} />
        }
      />
    ) : (
      <MenuPaneTopRow label="Settings" current="Layout" onBack={onBack} />
    )

  return (
    <MenuScrollFrame header={header} footer={formatRow}>
      {/* Click-to-edit title (no auto-focus/select on open) — shared with the container header. */}
      {title}
      <MenuSeparator flush />
      {grid}
      {view.type === 'table' &&
        (door === 'full' ? (
          <>
            <MenuSeparator flush />
            {LEAF_ROWS.map((r) => (
              <MenuItem
                key={r.id}
                className={flushTrailing}
                leading={<Icon name={r.icon} size={16} />}
                trailing={<Icon name="chevron-right" size={16} />}
                onClick={() => setLeaf(r.id)}
              >
                {r.label}
              </MenuItem>
            ))}
          </>
        ) : (
          <LayoutToggles source={source} view={view} />
        ))}
    </MenuScrollFrame>
  )
}
