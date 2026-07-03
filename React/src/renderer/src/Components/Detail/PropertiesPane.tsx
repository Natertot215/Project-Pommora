import { useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import { isReservedPropertyId, type PropertyDefinition, type PropertyType } from '@shared/properties'
import { MenuItem, MenuSeparator, MenuCaption, MenuBackRow } from '../../design-system/components/menu'
import { Reveal } from '../../design-system/components/Reveal'
import { duration } from '../../design-system/tokens/motion'
import { IconPicker } from '../IconPicker'
import { InlineEditHeader } from './InlineEditHeader'
import { PaneSlider } from './PaneSlider'
import { CREATABLE_TYPES, PropertyTypeIcon, propertyTypeLabel } from './PropertyTypes'
import { cx } from '../../design-system/cx'
import * as s from './viewPane.css'

type DetailView = { kind: 'type' } | { kind: 'edit'; id: string }
type SubView = { kind: 'list' } | DetailView
type WriteResult = { ok: true } | { ok: false; error: string }

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
      <MenuBackRow label={label} onClick={onClick} />
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

  const typePicker = (
    <>
      {backHeader('Properties', backToList)}
      {CREATABLE_TYPES.map((type) => (
        <MenuItem key={type} leading={<PropertyTypeIcon type={type} />} trailing={<Icon name="chevron-right" size={16} />} onClick={() => void create(type)}>
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
        {backHeader(def.name, backToList)}
        <InlineEditHeader value={def.name} onIconClick={() => setIconOpen(true)} onCommit={(next) => void rename(def.id, next)} />
        <MenuCaption>{propertyTypeLabel(def.type)} options — pending</MenuCaption>
        <div className={s.footer}>
          <MenuSeparator flush />
          <MenuItem className={cx(s.deleteRow, s.footerAction)} onClick={() => void remove(def.id)}>
            Delete Property
          </MenuItem>
        </div>
      </>
    )
  }

  const list = (
    <>
      <div className={s.paneHeader}>
        <div className={s.paneHeaderBack}>
          <MenuBackRow label="Properties" onClick={onBack} />
        </div>
        <button type="button" className={s.headerAction} aria-label="New Property" onClick={() => openDetail({ kind: 'type' })}>
          <Icon name="square-plus" size={16} />
        </button>
      </div>
      <MenuSeparator flush />
      <div data-group="assigned">
        {props.length === 0 ? (
          <MenuCaption>No properties yet.</MenuCaption>
        ) : (
          props.map((d) => (
            <MenuItem
              key={d.id}
              leading={<PropertyTypeIcon type={d.type} />}
              detail={propertyTypeLabel(d.type)}
              trailing={<Icon name="chevron-right" size={16} />}
              onClick={() => openDetail({ kind: 'edit', id: d.id })}
            >
              {d.name}
            </MenuItem>
          ))
        )}
      </div>
      {/* Bottom-pinned closed (the footer slot); the unfold grows the block while margin-top:auto
          keeps it bottom-anchored, so the heading RISES to meet the assigned rows on the same beat. */}
      <div className={s.footer} data-group="all">
        <MenuItem
          className={s.allHeading}
          leading={<Icon name="chevron-right" size={12} className={cx(s.twisty, allOpen && s.twistyOpen)} />}
          onClick={() => setAllOpen((o) => !o)}
        >
          All Properties
        </MenuItem>
        <Reveal open={allOpen} duration={duration.base}>
          <div>
            {unassigned.map((d) => (
              <MenuItem
                key={d.id}
                className={s.allRow}
                leading={<PropertyTypeIcon type={d.type} />}
                trailing={
                  <button
                    type="button"
                    className={s.rowPlus}
                    aria-label={`Assign ${d.name}`}
                    onClick={(e) => {
                      e.stopPropagation()
                      void assign(d.id)
                    }}
                  >
                    <Icon name="plus" size={12} />
                  </button>
                }
              >
                {d.name}
              </MenuItem>
            ))}
          </div>
        </Reveal>
      </div>
    </>
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
