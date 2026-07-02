import { useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import { isReservedPropertyId, type PropertyDefinition, type PropertyType } from '@shared/properties'
import { MenuItem, MenuSeparator, MenuCaption, MenuBackRow } from '../../design-system/components/menu'
import { IconPicker } from '../IconPicker'
import { InlineEditHeader } from './InlineEditHeader'
import { CREATABLE_TYPES, PropertyTypeIcon, propertyTypeLabel } from './PropertyTypes'
import { cx } from '../../design-system/cx'
import * as s from './viewPane.css'

type SubView = { kind: 'list' } | { kind: 'type' } | { kind: 'edit'; id: string }
type WriteResult = { ok: true } | { ok: false; error: string }

/**
 * The Properties pane — the page-schema CRUD surface, a sub-nav inside the ViewPane: a list of
 * user-defined properties → a type picker for new ones → a per-property editor. Writes route to the
 * `schema:*` IPC; the tree refresh after each write re-flows the live schema back in as `schema`,
 * so the editor re-reads the property by id. Per-type option/format editing + drag-reorder + the
 * lossy change-type confirm land next; this increment covers create / rename / icon / delete.
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
  const [view, setView] = useState<SubView>({ kind: 'list' })
  const [iconOpen, setIconOpen] = useState(false)

  const props = schema.filter((d) => !isReservedPropertyId(d.id))
  const backToList = (): void => setView({ kind: 'list' })

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
      setView({ kind: 'edit', id: res.id })
    } else await window.nexus.showError(res.error)
  }
  const rename = async (id: string, name: string): Promise<void> => {
    await commit(await window.nexus.schema.rename(collectionPath, id, name))
  }
  const remove = async (id: string): Promise<void> => {
    if (await commit(await window.nexus.schema.delete(collectionPath, id))) backToList()
  }

  if (view.kind === 'type') {
    return (
      <>
        {backHeader('Properties', backToList)}
        {CREATABLE_TYPES.map((type) => (
          <MenuItem key={type} leading={<PropertyTypeIcon type={type} />} trailing={<Icon name="chevron-right" size={16} />} onClick={() => void create(type)}>
            {propertyTypeLabel(type)}
          </MenuItem>
        ))}
      </>
    )
  }

  if (view.kind === 'edit') {
    const def = props.find((d) => d.id === view.id)
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
        <IconPicker open={iconOpen} onClose={() => setIconOpen(false)} />
      </>
    )
  }

  return (
    <>
      {backHeader('Properties', onBack)}
      {props.length === 0 ? (
        <MenuCaption>No properties yet.</MenuCaption>
      ) : (
        props.map((d) => (
          <MenuItem
            key={d.id}
            leading={<PropertyTypeIcon type={d.type} />}
            detail={propertyTypeLabel(d.type)}
            trailing={<Icon name="chevron-right" size={16} />}
            onClick={() => setView({ kind: 'edit', id: d.id })}
          >
            {d.name}
          </MenuItem>
        ))
      )}
      <div className={s.footer}>
        <MenuSeparator flush />
        <MenuItem className={s.footerAction} leading={<Icon name="plus" size={12} />} onClick={() => setView({ kind: 'type' })}>
          New Property
        </MenuItem>
      </div>
    </>
  )
}
