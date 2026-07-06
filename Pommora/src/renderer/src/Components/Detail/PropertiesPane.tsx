import { useRef, useState, type ReactNode } from 'react'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import { isReservedPropertyId, type PropertyDefinition, type PropertyType, type StatusGroup } from '@shared/properties'
import type { Option } from '@shared/optionModel'
import { MenuItem, MenuCaption, MenuPaneTopRow, MenuScrollFrame, MenuBottomRow, AccessoryButton } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { Reveal } from '../../design-system/components/Reveal'
import { duration } from '../../design-system/tokens/motion'
import { IconPicker } from '../IconPicker'
import { EditableInput } from '../EditableInput'
import { InlineEditHeader } from './InlineEditHeader'
import { OptionEditor } from './OptionEditor'
import { StatusEditor } from './StatusEditor'
import { URLEditor, type LinkConfig } from './URLEditor'
import { PaneSlider } from './PaneSlider'
import { PaneDnd, RowShell, usePaneRegions } from './paneDnd'
import { nexusReorderIndex, type PaneDrop, type PaneRow } from './paneDndModel'
import { CREATABLE_TYPES, PropertyTypeIcon, propertyTypeLabel } from './PropertyTypes'
import { cx } from '../../design-system/cx'
import * as s from './settingsPane.css'

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
    <MenuPaneTopRow label={label} onBack={onClick} />
  )
  // TopRow with a trailing icon action (the editor's ⋮ menu) — the action rides the row's trailing
  // slot, so it's part of the TopRow. stopPropagation keeps its click off the back-nav.
  const actionHeader = (
    label: string,
    onBackClick: () => void,
    action: { icon: IconName; size: number; ariaLabel: string; onClick: () => void }
  ): React.JSX.Element => (
    <MenuPaneTopRow
      label={label}
      onBack={onBackClick}
      trailing={
        <button
          type="button"
          className={s.topRowAction}
          aria-label={action.ariaLabel}
          onClick={(e) => {
            e.stopPropagation()
            action.onClick()
          }}
        >
          <Icon name={action.icon} size={action.size} />
        </button>
      }
    />
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
  const saveOptions = async (id: string, next: Option[]): Promise<void> => {
    await commit(await window.nexus.property.setOptions(id, next))
  }
  const saveStatusGroups = async (id: string, next: StatusGroup[]): Promise<void> => {
    await commit(await window.nexus.property.setStatusGroups(id, next))
  }
  const saveLinkConfig = async (id: string, patch: LinkConfig): Promise<void> => {
    await commit(await window.nexus.property.setLinkConfig(id, patch))
  }
  const renameOption = async (id: string, oldValue: string, newTitle: string): Promise<void> => {
    await commit(await window.nexus.property.renameOption(id, oldValue, newTitle))
  }
  const removeOption = async (id: string, value: string): Promise<void> => {
    await commit(await window.nexus.property.removeOption(id, value))
  }
  const clearOption = async (id: string, value: string): Promise<void> => {
    await commit(await window.nexus.property.clearOption(id, value))
  }
  const renameStatusOption = async (id: string, oldValue: string, newTitle: string): Promise<void> => {
    await commit(await window.nexus.property.renameStatusOption(id, oldValue, newTitle))
  }
  const removeStatusOption = async (id: string, value: string): Promise<void> => {
    await commit(await window.nexus.property.removeStatusOption(id, value))
  }
  const clearStatusOption = async (id: string, value: string): Promise<void> => {
    await commit(await window.nexus.property.clearStatusOption(id, value))
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
      <MenuScrollFrame
        header={actionHeader('Properties', backToList, {
          icon: 'ellipsis-vertical',
          size: s.ICON.editorMenu,
          ariaLabel: 'Property Menu',
          onClick: () => void editorMenu(def)
        })}
      >
        <InlineEditHeader value={def.name} onIconClick={() => setIconOpen(true)} onCommit={(next) => void rename(def.id, next)} />
        {def.type === 'select' || def.type === 'multi_select' ? (
          <OptionEditor
            type={def.type}
            options={def.select_options ?? []}
            onSetOptions={(next) => void saveOptions(def.id, next)}
            onRenameOption={(oldValue, newTitle) => void renameOption(def.id, oldValue, newTitle)}
            onRemoveOption={(value) => void removeOption(def.id, value)}
            onClearOption={(value) => void clearOption(def.id, value)}
          />
        ) : def.type === 'status' ? (
          <StatusEditor
            groups={def.status_groups ?? []}
            onSetGroups={(next) => void saveStatusGroups(def.id, next)}
            onRenameOption={(oldValue, newTitle) => void renameStatusOption(def.id, oldValue, newTitle)}
            onRemoveOption={(value) => void removeStatusOption(def.id, value)}
            onClearOption={(value) => void clearStatusOption(def.id, value)}
          />
        ) : def.type === 'url' ? (
          <URLEditor
            underline={def.link_underline ?? false}
            display={def.link_display ?? 'link-url'}
            color={def.link_color}
            onSetConfig={(patch) => void saveLinkConfig(def.id, patch)}
          />
        ) : (
          // Blank body until this type's options UI ships (Guidelines/UI-Copy.md).
          <div style={{ minHeight: 8 }} />
        )}
      </MenuScrollFrame>
    )
  }

  const list = (
    <MenuScrollFrame
      header={<MenuPaneTopRow label="Settings" current="Properties" onBack={onBack} />}
      footer={
        <MenuBottomRow
          leading={
            <AccessoryButton icon="plus" size={12} box={20} ariaLabel="New Property" onClick={() => openDetail({ kind: 'type' })} />
          }
        />
      }
    >
      <PaneDnd rows={paneRows} labelFor={nameFor} onDrop={(drop) => void handleDrop(drop)}>
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
    </MenuScrollFrame>
  )

  return (
    <>
      <PaneSlider
        open={view.kind !== 'list'}
        root={list}
        detail={detailView.kind === 'type' ? typePicker : editor(detailView.id)}
        minWidth={225}
        minHeight={245}
      />
      <IconPicker open={iconOpen} onClose={() => setIconOpen(false)} />
    </>
  )
}
