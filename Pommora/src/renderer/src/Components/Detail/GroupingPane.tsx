// The Grouping leaf — authors a table view's group config behind both doors (SettingsPane's Group
// entry, ViewSettings' Group leaf). Group By is the pane-flip disclosure (the Swift GroupingPane
// precedent); Order / Date By / Sub-Group are PickerControl dropdown rows. Structural-only settings
// (structural_order_mode, sub_group) live VIEW-level, so they survive Group By switches for free.
import { useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type {
  DateGranularity,
  GroupConfig,
  GroupOrderMode,
  SavedView,
  StructuralOrderMode,
  SubGroupConfig
} from '@shared/views'
import { Icon, asRenderableIcon, defaultEntityIcon, iconNameOr, type IconName } from '@renderer/design-system/symbols'
import { MenuItem, MenuSeparator, MenuPaneTopRow } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { Reveal } from '../../design-system/components/Reveal'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { declaredType } from '../../Detail/Views/pipeline/value'
import { bucketOrder } from '../../Detail/Views/pipeline/group'
import type { Band } from '../../Detail/Views/Table/bandDndModel'
import { reparentFsOrder, structuralOrderAfterDrop } from '../../Detail/Views/Table/bandDndModel'
import { nextOrder } from '@renderer/Sidebar/sidebarDndModel'
import { Chip, chipShapeForType } from '../Chip'
import { chipColorFor } from '../../design-system/tokens/colorMap'
import { useSession } from '../../store'
import { PickerControl, type PickerChoice } from './PickerControl'
import { useGroupingListDrag, type GroupingDrop } from './groupingDnd'
import * as gp from './groupingPane.css'

/** The pane's Group By offering — location + these property types. Checkbox is deliberately absent
 *  (the pipeline still renders it from a foreign sidecar; the pane never authors it). */
const GROUPABLE_PANE = new Set(['select', 'status', 'datetime'])

const STRUCTURAL_ORDER: PickerChoice<StructuralOrderMode>[] = [
  { value: 'custom', label: 'Custom' },
  { value: 'location', label: 'Location' }
]
const OPTION_ORDER: PickerChoice<GroupOrderMode>[] = [
  { value: 'configured', label: 'Default' },
  { value: 'reversed', label: 'Reversed' },
  { value: 'manual', label: 'Custom' }
]
const DATE_ORDER: PickerChoice<GroupOrderMode>[] = [
  { value: 'configured', label: 'Ascending' },
  { value: 'reversed', label: 'Descending' }
]
const GRANULARITY: PickerChoice<DateGranularity>[] = [
  { value: 'day', label: 'Day' },
  { value: 'week', label: 'Week' },
  { value: 'month', label: 'Month' },
  { value: 'year', label: 'Year' }
]

const orderOptionsFor = (type: string | undefined): PickerChoice<GroupOrderMode>[] =>
  type === 'datetime' ? DATE_ORDER : OPTION_ORDER

/** A labeled row whose trailing PickerControl pops the option menu — the DateTimeEditor PickerRow
 *  shape on the MenuItem chassis. `tier: 'sub'` is the subordinate Order treatment (C-8). */
function ValueRow<T extends string>({
  tier = 'primary',
  icon,
  label,
  value,
  options,
  onPick
}: {
  tier?: 'primary' | 'sub'
  icon?: IconName
  label: string
  value: T
  options: PickerChoice<T>[]
  onPick: (v: T) => void
}): React.JSX.Element {
  return (
    <MenuItem
      className={tier === 'sub' ? `${flushTrailing} ${gp.subRow}` : flushTrailing}
      leading={icon ? <Icon name={icon} size={14} /> : undefined}
      trailing={<PickerControl ariaLabel={label} value={value} options={options} onPick={onPick} />}
    >
      {tier === 'sub' ? <span className={gp.subLabel}>{label}</span> : label}
    </MenuItem>
  )
}

export function GroupingPane({
  source,
  view,
  schema,
  label,
  onBack
}: {
  source: CollectionNode | SetNode
  view: SavedView
  schema: PropertyDefinition[]
  /** The back-destination breadcrumb — 'Settings' from SettingsPane, 'Views' from ViewSettings. */
  label: string
  onBack: () => void
}): React.JSX.Element {
  const load = useSession((st) => st.load)
  const [groupByOpen, setGroupByOpen] = useState(false)
  const save = (patch: Partial<SavedView>): void => void saveViewAdopting(source, { ...view, ...patch }, load)
  const saveGroup = (group: GroupConfig): void => save({ group })

  const group = view.group ?? { kind: 'structural' as const }
  const structural = group.kind !== 'property'
  const groupable = schema.filter((d) => GROUPABLE_PANE.has(declaredType(d.id, schema) ?? ''))
  const activeDef = group.kind === 'property' ? schema.find((d) => d.id === group.property_id) : undefined
  const subGroup = structural ? view.sub_group : undefined

  // E-3 preservation is free: structural_order_mode / sub_group are view-level, so switching the
  // one group slot never touches them — flip back to Location and they're still in force.
  const pickGroupBy = (target: 'location' | PropertyDefinition): void => {
    setGroupByOpen(false)
    if (target === 'location') {
      if (!structural) saveGroup({ kind: 'structural' })
      return
    }
    if (group.kind === 'property' && group.property_id === target.id) return
    saveGroup({
      kind: 'property',
      property_id: target.id,
      order_mode: 'configured',
      empty_placement: view.ungrouped_placement ?? 'bottom',
      hide_empty_groups: false
    })
  }

  const saveSub = (sub: SubGroupConfig | undefined): void => save({ sub_group: sub })

  return (
    <>
      <MenuPaneTopRow label={label} current="Grouping" onBack={onBack} />
      <MenuItem
        className={flushTrailing}
        leading={<Icon name="layers" size={14} />}
        trailing={
          <span className={gp.groupByValue}>
            {structural ? 'Location' : (activeDef?.name ?? 'Location')}
            <Icon name="chevrons-up-down" size={12} />
          </span>
        }
        onClick={() => setGroupByOpen((o) => !o)}
      >
        Group By
      </MenuItem>
      <Reveal open={groupByOpen}>
        <div>
          <MenuItem
            leading={<Icon name="folder" size={13} />}
            trailing={structural ? <Icon name="check" size={12} /> : undefined}
            onClick={() => pickGroupBy('location')}
          >
            Location
          </MenuItem>
          {groupable.map((d) => (
            <MenuItem
              key={d.id}
              leading={<Icon name={asRenderableIcon(d.icon) ?? 'tag'} size={13} />}
              trailing={group.kind === 'property' && group.property_id === d.id ? <Icon name="check" size={12} /> : undefined}
              onClick={() => pickGroupBy(d)}
            >
              {d.name}
            </MenuItem>
          ))}
        </div>
      </Reveal>
      {!groupByOpen && (
        <>
          {group.kind === 'property' && declaredType(group.property_id, schema) === 'datetime' && (
            <ValueRow
              icon="calendar"
              label="Date By"
              value={group.date_granularity ?? 'month'}
              options={GRANULARITY}
              onPick={(g) => saveGroup({ ...group, date_granularity: g })}
            />
          )}
          {group.kind === 'property' ? (
            <ValueRow
              tier="sub"
              label="Order"
              value={group.order_mode}
              options={orderOptionsFor(declaredType(group.property_id, schema))}
              onPick={(m) => saveGroup({ ...group, order_mode: m })}
            />
          ) : (
            <ValueRow
              tier="sub"
              label="Order"
              value={view.structural_order_mode ?? 'custom'}
              options={STRUCTURAL_ORDER}
              onPick={(m) => save({ structural_order_mode: m })}
            />
          )}
          {structural && (
            <>
              <SubGroupRow subGroup={subGroup} groupable={groupable} onSave={saveSub} />
              {subGroup && declaredType(subGroup.property_id, schema) === 'datetime' && (
                <ValueRow
                  icon="calendar"
                  label="Date By"
                  value={subGroup.date_granularity ?? 'month'}
                  options={GRANULARITY}
                  onPick={(g) => saveSub({ ...subGroup, date_granularity: g })}
                />
              )}
              {subGroup && (
                <ValueRow
                  tier="sub"
                  label="Order"
                  value={subGroup.order_mode}
                  options={orderOptionsFor(declaredType(subGroup.property_id, schema))}
                  onPick={(m) => saveSub({ ...subGroup, order_mode: m })}
                />
              )}
            </>
          )}
          <MenuSeparator flush />
          <div className={`${gp.middle} overflow-eclipse-y`}>
            {group.kind === 'property' ? (
              group.order_mode === 'manual' ? (
                <CustomList group={group} def={activeDef} onSave={saveGroup} />
              ) : (
                <PropertyPreview group={group} def={activeDef} />
              )
            ) : (
              <LocationHierarchy source={source} view={view} flat={subGroup !== undefined} onSaveView={save} />
            )}
          </div>
          {/* T10: the footings. */}
        </>
      )}
    </>
  )
}

// ---- middle-region bodies ----

const optionsOf = (def: PropertyDefinition | undefined): { value: string; label: string; color?: string }[] =>
  def?.select_options ?? def?.status_groups?.flatMap((g) => g.options) ?? []

type PropertyGroupConfig = Extract<GroupConfig, { kind: 'property' }>

/** Default/Reversed read-only preview (D-9): status renders its groups as muted headings with each
 *  group's option chips beneath; select renders one flat chip run; datetime has no finite list. */
function PropertyPreview({ group, def }: { group: PropertyGroupConfig; def: PropertyDefinition | undefined }): React.JSX.Element | null {
  if (!def) return null
  const type = def.type === 'status' ? 'status' : 'select'
  const chip = (o: { value: string; label: string; color?: string }): React.JSX.Element => (
    <div key={o.value} className={gp.chipRow}>
      <Chip color={chipColorFor(o.color)} label={o.label} shape={chipShapeForType(type)} />
    </div>
  )
  if (def.status_groups) {
    const groups = group.order_mode === 'reversed' ? [...def.status_groups].reverse() : def.status_groups
    return (
      <>
        {groups.map((g) => (
          <div key={g.id}>
            <div className={gp.previewHeading}>{g.label}</div>
            {(group.order_mode === 'reversed' ? [...g.options].reverse() : g.options).map(chip)}
          </div>
        ))}
      </>
    )
  }
  const ordered = bucketOrder(group, def, new Set(optionsOf(def).map((o) => o.value)))
  const byValue = new Map(optionsOf(def).map((o) => [o.value, o]))
  return <>{ordered.flatMap((v) => (byValue.has(v) ? [chip(byValue.get(v)!)] : []))}</>
}

/** Custom (manual) order: one flat "Options" list of draggable chips writing group.order (D-2). */
function CustomList({
  group,
  def,
  onSave
}: {
  group: PropertyGroupConfig
  def: PropertyDefinition | undefined
  onSave: (g: GroupConfig) => void
}): React.JSX.Element | null {
  const all = optionsOf(def)
  const ordered = bucketOrder(group, def, new Set(all.map((o) => o.value)))
  const byValue = new Map(all.map((o) => [o.value, o]))
  const bands: Band[] = ordered.map((v) => ({ id: v, kind: 'property', depth: 0, parentId: null }))
  const dnd = useGroupingListDrag({
    bands,
    nestable: false,
    onDrop: (draggedId, drop) => onSave({ ...group, order: nextOrder(ordered, draggedId, drop.beforeId) })
  })
  if (!def) return null
  const type = def.type === 'status' ? 'status' : 'select'
  return (
    <div ref={dnd.containerRef} style={{ position: 'relative' }}>
      <div className={gp.previewHeading}>Options</div>
      {ordered.flatMap((v) => {
        const o = byValue.get(v)
        if (!o) return []
        return [
          <div key={v} ref={dnd.rowRef(v)} {...dnd.rowHandle(v)} className={gp.chipRow} style={dnd.draggingId === v ? { opacity: 0.4 } : undefined}>
            <Chip color={chipColorFor(o.color)} label={o.label} shape={chipShapeForType(type)} />
          </div>
        ]
      })}
      {dnd.line && <div className={gp.dropLine} style={{ top: dnd.line.y }} />}
    </div>
  )
}

/** The set hierarchy (C-2): sets with sub-sets disclosed beneath them, no pages; FLAT when
 *  sub-grouped (F-3). Drags mirror the table band rules (F-4): sibling reorder writes view order
 *  in Custom / the filesystem in Location; a cross-nesting drop is always an fs reparent. */
function LocationHierarchy({
  source,
  view,
  flat,
  onSaveView
}: {
  source: CollectionNode | SetNode
  view: SavedView
  flat: boolean
  onSaveView: (patch: Partial<SavedView>) => void
}): React.JSX.Element {
  const mutate = useSession((st) => st.mutate)
  const [collapsedSets, setCollapsedSets] = useState<Set<string>>(new Set())

  type Row = { id: string; title: string; icon?: string; depth: number; parentId: string | null; hasChildren: boolean; path: string }
  const rows: Row[] = []
  const allIds: string[] = []
  const childIds = new Map<string | null, string[]>()
  const paths = new Map<string, string>()
  const walk = (sets: SetNode[] | undefined, depth: number, parentId: string | null, visible: boolean): void => {
    childIds.set(parentId, (sets ?? []).map((s) => s.id))
    for (const s of sets ?? []) {
      allIds.push(s.id)
      paths.set(s.id, s.path)
      if (visible) {
        rows.push({ id: s.id, title: s.title, icon: s.icon, depth, parentId, hasChildren: (s.sets ?? []).length > 0, path: s.path })
      }
      walk(s.sets, depth + 1, s.id, visible && !flat && !collapsedSets.has(s.id))
    }
  }
  walk(source.sets, 0, null, true)

  const onDrop = (draggedId: string, drop: GroupingDrop): void => {
    if (drop.kind === 'reorder') {
      if (view.structural_order_mode === 'location') {
        const parentPath = drop.targetParentId === null ? source.path : paths.get(drop.targetParentId)
        const siblings = childIds.get(drop.targetParentId) ?? []
        if (!parentPath) return
        void mutate({ op: 'reorderChildren', parentPath, key: 'set_order', order: nextOrder(siblings, draggedId, drop.beforeId) })
        return
      }
      onSaveView({ group_order: structuralOrderAfterDrop(view.group_order ?? [], allIds, draggedId, drop.beforeId) })
      return
    }
    const path = paths.get(draggedId)
    const destPath = drop.targetParentId === null ? source.path : paths.get(drop.targetParentId)
    const destChildren = childIds.get(drop.targetParentId) ?? []
    if (!path || !destPath) return
    const group_order = structuralOrderAfterDrop(view.group_order ?? [], allIds, draggedId, drop.beforeId)
    void (async () => {
      if (!(await mutate({ op: 'moveSet', path, newParentPath: destPath, order: reparentFsOrder(destChildren, draggedId) }))) return
      onSaveView({ group_order })
    })()
  }

  const bands: Band[] = rows.map((r) => ({ id: r.id, kind: 'set', depth: r.depth, parentId: flat ? null : r.parentId }))
  const dnd = useGroupingListDrag({ bands, nestable: !flat, onDrop })
  return (
    <div ref={dnd.containerRef} style={{ position: 'relative' }}>
      {rows.map((r) => (
        <div key={r.id} ref={dnd.rowRef(r.id)} {...dnd.rowHandle(r.id)} style={dnd.draggingId === r.id ? { opacity: 0.4 } : undefined}>
          <MenuItem
            indent={r.depth}
            selected={dnd.nestTarget === r.id}
            leading={<Icon name={iconNameOr(r.icon, defaultEntityIcon('set'))} size={13} />}
            trailing={
              !flat && r.hasChildren ? (
                <Icon
                  name="chevron-right"
                  size={12}
                  className={collapsedSets.has(r.id) ? undefined : 'open'}
                  onClick={(e) => {
                    e.stopPropagation()
                    setCollapsedSets((prev) => {
                      const next = new Set(prev)
                      if (next.has(r.id)) next.delete(r.id)
                      else next.add(r.id)
                      return next
                    })
                  }}
                />
              ) : undefined
            }
          >
            {r.title}
          </MenuItem>
        </div>
      ))}
      {dnd.line && <div className={gp.dropLine} style={{ top: dnd.line.y }} />}
    </div>
  )
}

/** The Sub-Group picker row — its pick genuinely branches (Location CLEARS the view-level field;
 *  a property writes a fresh config), so it stays its own component. Empty schema ⇒ Location alone. */
function SubGroupRow({
  subGroup,
  groupable,
  onSave
}: {
  subGroup: SubGroupConfig | undefined
  groupable: PropertyDefinition[]
  onSave: (sub: SubGroupConfig | undefined) => void
}): React.JSX.Element {
  const options: PickerChoice<string>[] = [
    { value: '_location', label: 'Location', icon: 'folder' as const },
    ...groupable.map((d) => ({ value: d.id, label: d.name, icon: asRenderableIcon(d.icon) ?? 'tag' }))
  ]
  return (
    <ValueRow
      icon="layers"
      label="Sub-Group"
      value={subGroup?.property_id ?? '_location'}
      options={options}
      onPick={(v) => onSave(v === '_location' ? undefined : { property_id: v, order_mode: 'configured' })}
    />
  )
}
