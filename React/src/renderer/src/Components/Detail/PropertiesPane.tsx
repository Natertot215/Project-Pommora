import { useRef, useState, type ReactNode } from 'react'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import { isReservedPropertyId, type PropertyDefinition, type PropertyType } from '@shared/properties'
import { MenuItem, MenuSeparator, MenuCaption, MenuBackRow } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { Reveal } from '../../design-system/components/Reveal'
import { duration } from '../../design-system/tokens/motion'
import { IconPicker } from '../IconPicker'
import { EditableInput } from '../EditableInput'
import { InlineEditHeader } from './InlineEditHeader'
import { PaneSlider } from './PaneSlider'
import { PaneDnd, RowShell, usePaneRegions } from './paneDnd'
import { nexusReorderIndex, type PaneDrop, type PaneRow } from './paneDndModel'
import { CREATABLE_TYPES, PropertyTypeIcon, propertyTypeLabel } from './PropertyTypes'
import { cx } from '../../design-system/cx'
import * as s from './viewPane.css'

type DetailView = { kind: 'type' } | { kind: 'edit'; id: string }
type SubView = { kind: 'list' } | DetailView
type WriteResult = { ok: true } | { ok: false; error: string }

/** The two drag regions (E-4): assigned rows on top, the bottom-pinned All Properties block below
 *  the elastic spacer. Lives outside PropertiesPane so rows never remount on its re-renders. */
function ListGroups({
  assigned,
  unassigned,
  allOpen,
  renamingId,
  onToggleAll,
  onOpenEditor,
  onAssign,
  onRowMenu,
  onRenameCommit,
  onRenameCancel
}: {
  assigned: PropertyDefinition[]
  unassigned: PropertyDefinition[]
  allOpen: boolean
  renamingId: string | null
  onToggleAll: () => void
  onOpenEditor: (id: string) => void
  onAssign: (id: string) => void
  onRowMenu: (d: PropertyDefinition, group: 'assigned' | 'all') => void
  onRenameCommit: (next: string, current: string) => void
  onRenameCancel: () => void
}): React.JSX.Element {
  const { assignedRef, allRef, allHighlighted } = usePaneRegions()
  // The row title swaps to the store-driven inline rename input (A-10) — the RenamableTitle UX
  // over the property-keyed channel (properties are registry ids, not paths).
  const title = (d: PropertyDefinition): ReactNode =>
    renamingId === d.id ? (
      <EditableInput
        value={d.name}
        className="row-title-input"
        onCommit={(next) => {
          if (next && next !== d.name) onRenameCommit(next, d.name)
          else onRenameCancel()
        }}
        onCancel={onRenameCancel}
      />
    ) : (
      d.name
    )
  return (
    <>
      <div data-group="assigned" ref={assignedRef}>
        {assigned.length === 0 ? (
          <MenuCaption>No properties yet.</MenuCaption>
        ) : (
          assigned.map((d) => (
            <RowShell key={d.id} id={d.id}>
              <MenuItem
                className={flushTrailing}
                leading={<PropertyTypeIcon type={d.type} size={s.ICON.doc} />}
                detail={propertyTypeLabel(d.type)}
                trailing={<Icon name="chevron-right" size={s.ICON.rowChevron} />}
                onClick={() => onOpenEditor(d.id)}
                onContextMenu={(e) => {
                  e.preventDefault()
                  onRowMenu(d, 'assigned')
                }}
              >
                {title(d)}
              </MenuItem>
            </RowShell>
          ))
        )}
      </div>
      {/* Closed, the elastic spacer holds the block at the pane's bottom; opening collapses it on
          the same beat as the Reveal, so the heading RISES to meet the assigned rows (Nathan's call). */}
      <div className={cx(s.allSpacer, allOpen && s.allSpacerCollapsed)} aria-hidden />
      <div data-group="all" ref={allRef} className={cx(allHighlighted && s.allHighlight)}>
        <MenuItem
          className={s.allHeading}
          leading={<Icon name="chevron-right" size={s.ICON.twisty} className={cx(s.twisty, allOpen && s.twistyOpen)} />}
          onClick={onToggleAll}
        >
          All Properties
        </MenuItem>
        <Reveal open={allOpen} duration={duration.base}>
          <div>
            {unassigned.map((d) => (
              <RowShell key={d.id} id={d.id}>
                <MenuItem
                  className={cx(s.allRow, flushTrailing)}
                  leading={<PropertyTypeIcon type={d.type} size={s.ICON.doc} />}
                  onContextMenu={(e) => {
                    e.preventDefault()
                    onRowMenu(d, 'all')
                  }}
                  trailing={
                    <button
                      type="button"
                      className={s.rowPlus}
                      aria-label={`Assign ${d.name}`}
                      onClick={(e) => {
                        e.stopPropagation()
                        onAssign(d.id)
                      }}
                    >
                      <Icon name="plus" size={s.ICON.rowPlus} />
                    </button>
                  }
                >
                  {title(d)}
                </MenuItem>
              </RowShell>
            ))}
          </div>
        </Reveal>
      </div>
    </>
  )
}

/**
 * The Properties pane — the page-schema CRUD surface, a sub-nav inside the ViewPane: a list of
 * user-defined properties → a type picker for new ones → a per-property editor. Writes route to the
 * `schema:*` IPC; the tree refresh after each write re-flows the live schema back in as `schema`,
 * so the editor re-reads the property by id. The subviews ride an inner PaneSlider nested in the
 * ViewPane's outer one, so every push at every depth slides on the same beat (A-7) — one primitive,
 * zero per-window wiring.
 */
export function PropertiesPane({
  collectionPath,
  schema,
  onBack
}: {
  collectionPath: string
  schema: PropertyDefinition[]
  onBack: () => void
}): React.JSX.Element {
  const load = useSession((st) => st.load)
  const registry = useSession((st) => st.tree?.registry) ?? []
  const renamingProperty = useSession((st) => st.renamingProperty)
  const beginPropertyRename = useSession((st) => st.beginPropertyRename)
  const cancelPropertyRename = useSession((st) => st.cancelPropertyRename)
  const submitPropertyRename = useSession((st) => st.submitPropertyRename)
  const [view, setView] = useState<SubView>({ kind: 'list' })
  const [iconOpen, setIconOpen] = useState(false)
  const [allOpen, setAllOpen] = useState(false)
  const lastDetail = useRef<DetailView>({ kind: 'type' })

  const props = schema.filter((d) => !isReservedPropertyId(d.id))
  const assignedIds = new Set(schema.map((d) => d.id))
  const unassigned = registry.filter((d) => !assignedIds.has(d.id) && !isReservedPropertyId(d.id))
  const backToList = (): void => setView({ kind: 'list' })
  const openDetail = (v: DetailView): void => {
    lastDetail.current = v
    setView(v)
  }
  // Slot B keeps rendering the last-opened detail while sliding back, so it doesn't blank mid-retract.
  const detailView = view.kind === 'list' ? lastDetail.current : view

  const backHeader = (label: string, onClick: () => void): React.JSX.Element => (
    <>
      <MenuBackRow label={label} onClick={onClick} className={s.backRowPad} />
      <MenuSeparator flush />
    </>
  )
  // Back row + a trailing icon action on the right edge (⊕ create on the list, ⋮ menu on the editor).
  const actionHeader = (
    label: string,
    onBackClick: () => void,
    action: { icon: IconName; size: number; ariaLabel: string; onClick: () => void }
  ): React.JSX.Element => (
    <>
      <div className={s.paneHeader}>
        <div className={s.paneHeaderBack}>
          <MenuBackRow label={label} onClick={onBackClick} className={s.backRowPad} />
        </div>
        <button type="button" className={s.headerAction} aria-label={action.ariaLabel} onClick={action.onClick}>
          <Icon name={action.icon} size={action.size} />
        </button>
      </div>
      <MenuSeparator flush />
    </>
  )

  // Surface an IPC error, else refresh the live schema; returns whether the write landed.
  const commit = async (res: WriteResult): Promise<boolean> => {
    if (!res.ok) {
      await window.nexus.showError(res.error)
      return false
    }
    await load()
    return true
  }

  const create = async (type: PropertyType): Promise<void> => {
    const res = await window.nexus.schema.add(collectionPath, { id: '', name: `New ${propertyTypeLabel(type)}`, type })
    if (res.ok) {
      await load()
      openDetail({ kind: 'edit', id: res.id })
    } else await window.nexus.showError(res.error)
  }
  const rename = async (id: string, name: string): Promise<void> => {
    await commit(await window.nexus.schema.rename(collectionPath, id, name))
  }
  const remove = async (id: string): Promise<void> => {
    if (await commit(await window.nexus.schema.delete(collectionPath, id))) backToList()
  }
  const assign = async (id: string): Promise<void> => {
    await commit(await window.nexus.schema.assign(collectionPath, id))
  }
  // The four drop kinds route to their persistence targets (E-4): collection order, nexus
  // order (the visible slot translated into the full-order index — assigned ids stay in it),
  // atomic assign-at-slot, and the strip-and-cache Remove.
  const handleDrop = async (drop: PaneDrop): Promise<void> => {
    const r =
      drop.kind === 'reorder-assigned'
        ? await window.nexus.schema.reorder(collectionPath, drop.propId, drop.toIndex)
        : drop.kind === 'reorder-nexus'
          ? await window.nexus.registry.reorder(
              drop.propId,
              nexusReorderIndex(
                registry.map((d) => d.id),
                unassigned.map((d) => d.id),
                drop.propId,
                drop.toIndex
              )
            )
          : drop.kind === 'assign'
            ? await window.nexus.schema.assign(collectionPath, drop.propId, drop.toIndex)
            : await window.nexus.schema.delete(collectionPath, drop.propId)
    await commit(r)
  }

  const paneRows: PaneRow[] = [
    ...props.map((d) => ({ id: d.id, group: 'assigned' as const })),
    ...unassigned.map((d) => ({ id: d.id, group: 'all' as const }))
  ]
  const nameFor = (id: string): string =>
    props.find((d) => d.id === id)?.name ?? unassigned.find((d) => d.id === id)?.name ?? ''

  // The editor's ⋮ (A-8): Remove, or the pane-gated Delete (main confirms before resolving).
  const editorMenu = async (def: PropertyDefinition): Promise<void> => {
    const action = await window.nexus.propertyMenu({ kind: 'editor', name: def.name })
    if (action === 'property:remove') await remove(def.id)
    else if (action === 'property:destroy' && (await commit(await window.nexus.property.delete(def.id)))) backToList()
  }
  // A row's right-click (A-10): Rename (both groups) · Remove (assigned only).
  const rowMenu = async (d: PropertyDefinition, group: 'assigned' | 'all'): Promise<void> => {
    const action = await window.nexus.propertyMenu({
      kind: group === 'assigned' ? 'assigned-row' : 'registry-row',
      name: d.name
    })
    if (action === 'property:rename') beginPropertyRename({ collectionPath, propertyId: d.id })
    else if (action === 'property:remove') await commit(await window.nexus.schema.delete(collectionPath, d.id))
  }

  const typePicker = (
    <>
      {backHeader('Properties', backToList)}
      {CREATABLE_TYPES.map((type) => (
        <MenuItem
          key={type}
          className={flushTrailing}
          leading={<PropertyTypeIcon type={type} size={s.ICON.doc} />}
          trailing={<Icon name="chevron-right" size={s.ICON.rowChevron} />}
          onClick={() => void create(type)}
        >
          {propertyTypeLabel(type)}
        </MenuItem>
      ))}
    </>
  )

  const editor = (id: string): React.JSX.Element => {
    const def = props.find((d) => d.id === id)
    if (!def) {
      return (
        <>
          {backHeader('Properties', backToList)}
          <MenuCaption>Property not found.</MenuCaption>
        </>
      )
    }
    return (
      <>
        {actionHeader('Properties', backToList, {
          icon: 'ellipsis-vertical',
          size: s.ICON.editorMenu,
          ariaLabel: 'Property Menu',
          onClick: () => void editorMenu(def)
        })}
        <InlineEditHeader value={def.name} onIconClick={() => setIconOpen(true)} onCommit={(next) => void rename(def.id, next)} />
        <MenuCaption>{propertyTypeLabel(def.type)} options — pending</MenuCaption>
      </>
    )
  }

  const list = (
    <PaneDnd rows={paneRows} labelFor={nameFor} onDrop={(drop) => void handleDrop(drop)}>
      {actionHeader('Settings', onBack, {
        icon: 'square-plus',
        size: s.ICON.add,
        ariaLabel: 'New Property',
        onClick: () => openDetail({ kind: 'type' })
      })}
      <ListGroups
        assigned={props}
        unassigned={unassigned}
        allOpen={allOpen}
        renamingId={renamingProperty?.collectionPath === collectionPath ? renamingProperty.propertyId : null}
        onToggleAll={() => setAllOpen((o) => !o)}
        onOpenEditor={(id) => openDetail({ kind: 'edit', id })}
        onAssign={(id) => void assign(id)}
        onRowMenu={(d, group) => void rowMenu(d, group)}
        onRenameCommit={(next) => void submitPropertyRename(next)}
        onRenameCancel={cancelPropertyRename}
      />
    </PaneDnd>
  )

  return (
    <>
      <PaneSlider
        active={view.kind === 'list' ? 'a' : 'b'}
        slotA={list}
        slotB={detailView.kind === 'type' ? typePicker : editor(detailView.id)}
        minWidth={225}
        minHeight={245}
      />
      <IconPicker open={iconOpen} onClose={() => setIconOpen(false)} />
    </>
  )
}
