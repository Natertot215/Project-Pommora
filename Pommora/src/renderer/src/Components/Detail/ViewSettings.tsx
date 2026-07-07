import { useRef, useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { DEFAULT_VIEW_ID, type SavedView, type ViewFormat, type ViewType } from '@shared/views'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import { MenuItem, MenuSeparator, MenuPaneTopRow, MenuScrollFrame, AccessoryButton } from '../../design-system/components/menu'
import { detail, flushTrailing, footingLabel, footingSymbol, side } from '../../design-system/components/menu/menu.css'
import { PickerMenu } from '../../design-system/components/PickerMenu'
import { useSession } from '../../store'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { InlineEditHeader } from './InlineEditHeader'
import { VisibilityList } from './HiddenPane'
import { LayoutToggles } from './LayoutToggles'
import { PaneSlider } from './PaneSlider'
import { cx } from '../../design-system/cx'
import * as vs from './viewSettings.css'

// Grid order (D-4) + each type's glyph (D-5). Only Table is buildable this cycle; the rest render at
// full weight but their tiles are inert.
const TYPE_ORDER: ViewType[] = ['table', 'cards', 'list', 'gallery', 'calendar', 'timeline']
const TYPE_GLYPH: Record<ViewType, IconName> = {
  table: 'table',
  cards: 'cards-grid',
  list: 'list-rounded',
  gallery: 'gallery-stack',
  calendar: 'calendar-days',
  timeline: 'chart-gantt'
}
const IMPLEMENTED: ReadonlySet<ViewType> = new Set(['table'])
const isMac = navigator.platform.toLowerCase().includes('mac')

// ── KNOB — ViewSettings' own height ceiling (its own, not the shared MENU_MAX_HEIGHT): the full door
// stacks the tallest content (title + grid + four leaf rows + the pinned Format), so it earns more
// room before the body scrolls. Applies to the editor + its Layout leaf. ──
const VIEWSETTINGS_MAX_HEIGHT = 375
// ── KNOB — the leaf slider's floors (matches the SettingsPane sibling): a blank Group/Filter/Sort leaf
// reserves this square instead of collapsing to a bare header strip mid-slide. ──
const LEAF_MIN_WIDTH = 225
const LEAF_MIN_HEIGHT = 245

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

  // Full-door leaves — the detail slot of the leaf slider (below). Layout opens the visibility list
  // (+ its icon toggles); Group/Filter/Sort ship blank, matching the SettingsPane's — the shared panes
  // land in their own arcs. Only mounted while a leaf is open, so a push measures it before the flip.
  const leafPane =
    leaf === 'layout' ? (
      <VisibilityList
        source={source}
        schema={schema}
        view={view}
        label="Views"
        current="Layout"
        maxHeight={VIEWSETTINGS_MAX_HEIGHT}
        onBack={() => setLeaf(null)}
        footer={<LayoutToggles source={source} view={view} />}
      />
    ) : leaf ? (
      <MenuPaneTopRow label="Views" current={LEAF_CURRENT[leaf]} onBack={() => setLeaf(null)} />
    ) : null

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
          <Icon name={TYPE_GLYPH[t]} size={23} />
        </button>
      ))}
    </div>
  )

  // Format — the pinned footer (D-8): persists, dual-wired (native menu on mac, PickerMenu else), inert
  // visually this cycle. Table-only.
  const formatRow =
    view.type === 'table' ? (
      <div ref={formatRef}>
        {/* The divider above the footing — separates the pinned Format control from the scrolling body. */}
        <MenuSeparator flush />
        <MenuItem
          className={flushTrailing}
          leading={
            <span className={footingSymbol}>
              <Icon name="layers-2" size={12} />
            </span>
          }
          trailing={
            <span className={side}>
              <span className={detail}>{format === 'compact' ? 'Compact' : 'Standard'}</span>
              <span className={footingSymbol}>
                <Icon name="chevrons-up-down" size={12} />
              </span>
            </span>
          }
          onClick={() => void openFormat()}
        >
          <span className={footingLabel}>Format</span>
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

  const mainFrame = (
    <MenuScrollFrame header={header} footer={formatRow} maxHeight={VIEWSETTINGS_MAX_HEIGHT}>
      {/* Click-to-edit title (no auto-focus/select on open) — shared with the container header. */}
      {title}
      <MenuSeparator flush />
      {grid}
      {view.type === 'table' &&
        (door === 'full' ? (
          LEAF_ROWS.map((r) => (
            <MenuItem
              key={r.id}
              className={flushTrailing}
              leading={<Icon name={r.icon} size={16} />}
              trailing={<Icon name="chevron-right" size={16} />}
              onClick={() => setLeaf(r.id)}
            >
              {r.label}
            </MenuItem>
          ))
        ) : (
          <LayoutToggles source={source} view={view} />
        ))}
    </MenuScrollFrame>
  )

  // The leaf slider — the same primitive the ViewPane rides one level up, nested here so a full-door
  // leaf (Layout/Group/Filter/Sort) slides in over the editor instead of hard-swapping. Flat door never
  // opens a leaf, so this stays parked on the main frame.
  return (
    <PaneSlider open={leaf !== null} root={mainFrame} detail={leafPane} minWidth={LEAF_MIN_WIDTH} minHeight={LEAF_MIN_HEIGHT} />
  )
}
