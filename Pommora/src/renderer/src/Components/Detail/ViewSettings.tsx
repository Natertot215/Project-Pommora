import { useRef, useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { DEFAULT_VIEW_ID, type SavedView, type ViewFormat, type ViewType } from '@shared/views'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import { MenuItem, MenuSeparator, MenuPaneTopRow, AccessoryButton } from '../../design-system/components/menu'
import { detail, flushTrailing, side } from '../../design-system/components/menu/menu.css'
import { PickerMenu } from '../../design-system/components/PickerMenu'
import { useSession } from '../../store'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { EditableInput } from '../EditableInput'
import { DashIcon } from './DashIcon'
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

/**
 * ViewSettings — the shared per-view editor, both doors (D-1). The full door (a ViewPane row's
 * chevron) carries the leaf rows + the ⋮ (Duplicate/Delete); the flat door (SettingsPane → Layout)
 * drops the leafs and the ⋮. Header + type grid + (for Table) the Layout leaf and the Format row.
 * `onClose` closes the whole dropdown (a Delete that removes the active view).
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
  const [leaf, setLeaf] = useState(false)
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
        ids.splice(at + 1, 0, res.id)
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

  if (leaf) {
    // The Layout leaf — order + visibility (deferred to the Figma redesign); blank chrome for now.
    return <MenuPaneTopRow label="Settings" onBack={() => setLeaf(false)} />
  }

  return (
    <>
      <MenuPaneTopRow
        label={door === 'full' ? 'Views' : 'Settings'}
        onBack={onBack}
        trailing={
          door === 'full' ? (
            <AccessoryButton icon="ellipsis-vertical" size={14} box={20} ariaLabel="View menu" onClick={() => void openItemMenu()} />
          ) : undefined
        }
      />
      <div className={vs.header}>
        <button type="button" className={vs.iconButton} aria-label="View icon">
          <DashIcon />
        </button>
        <EditableInput value={view.name} className={vs.titleField} onCommit={rename} onCancel={() => {}} />
      </div>
      <MenuSeparator flush />
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
      {view.type === 'table' && (
        <>
          <MenuSeparator flush />
          {door === 'full' && (
            <MenuItem
              className={flushTrailing}
              leading={<Icon name="layout-panel-left" size={16} />}
              trailing={<Icon name="chevron-right" size={16} />}
              onClick={() => setLeaf(true)}
            >
              Layout
            </MenuItem>
          )}
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
          </div>
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
        </>
      )}
    </>
  )
}
