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
import { flushTrailing, footingLabel, footingSymbol } from '../../design-system/components/menu/menu.css'
import { Reveal } from '../../design-system/components/Reveal'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { declaredType } from '../../Detail/Views/pipeline/value'
import { bucketOrder } from '../../Detail/Views/pipeline/group'
import { NUMERIC_FORMATS } from '../../Detail/Views/PropertyEditing/formatValue'
import type { Band } from '../../Detail/Views/Table/bandDndModel'
import { reparentFsOrder, structuralOrderAfterDrop } from '../../Detail/Views/Table/bandDndModel'
import { nextOrder } from '@renderer/Sidebar/sidebarDndModel'
import { Chip, chipShapeForType } from '../Chip'
import { chipColorFor } from '../../design-system/tokens/colorMap'
import { chipBox, chipColor } from '../../design-system/tokens'
import { cx } from '../../design-system/cx'
import { checkboxBoxStyle } from '../../Detail/Views/Table/checkboxLook'
import { useSession } from '../../store'
import { PickerControl, type PickerChoice } from './PickerControl'
import { propertyTypeIconName } from './PropertyTypes'
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
      className={cx(flushTrailing, gp.pickerTone, tier === 'sub' && gp.subRow)}
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
  // The property whose date buckets head bands right now (top-level date grouping, or the date
  // sub-group) — the Separation footing appears only when its column wears a numeric format (D-8).
  const dateHeadingProp =
    group.kind === 'property' && declaredType(group.property_id, schema) === 'datetime'
      ? group.property_id
      : subGroup && declaredType(subGroup.property_id, schema) === 'datetime'
        ? subGroup.property_id
        : undefined

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
  // A date grouping has no finite option list — its middle region (and separator) collapses.
  const hasMiddle = group.kind !== 'property' || declaredType(group.property_id, schema) !== 'datetime'

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
              leading={<Icon name={asRenderableIcon(d.icon) ?? propertyTypeIconName(d.type) ?? 'tag'} size={13} />}
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
              icon="arrow-up-down"
              label="Order"
              value={group.order_mode}
              options={orderOptionsFor(declaredType(group.property_id, schema))}
              onPick={(m) => saveGroup({ ...group, order_mode: m })}
            />
          ) : (
            <ValueRow
              tier={subGroup ? 'sub' : 'primary'}
              icon="arrow-up-down"
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
                  icon="arrow-up-down"
                  label="Order"
                  value={subGroup.order_mode}
                  options={orderOptionsFor(declaredType(subGroup.property_id, schema))}
                  onPick={(m) => saveSub({ ...subGroup, order_mode: m })}
                />
              )}
            </>
          )}
          {hasMiddle && (
            <>
              <MenuSeparator flush />
              <div className={`${gp.middle} overflow-eclipse-y`}>
                {group.kind === 'property' ? (
                  group.order_mode === 'manual' ? (
                    <CustomList group={group} def={activeDef} onSave={saveGroup} />
                  ) : (
                    <PropertyPreview group={group} def={activeDef} />
                  )
                ) : (
                  <LocationHierarchy
                    source={source}
                    view={view}
                    subDef={subGroup ? schema.find((d) => d.id === subGroup.property_id) : undefined}
                    onSaveView={save}
                  />
                )}
              </div>
            </>
          )}
          <MenuSeparator flush />
          <FootingPick
            icon="folder-minus"
            label="Ungrouped"
            value={view.ungrouped_placement ?? 'bottom'}
            options={[
              { value: 'top', label: 'Top' },
              { value: 'bottom', label: 'Bottom' }
            ]}
            onPick={(v) => save({ ungrouped_placement: v })}
          />
          {dateHeadingProp && NUMERIC_FORMATS.has(view.column_styles?.[dateHeadingProp]?.date_format ?? 'full') && (
            <FootingPick
              icon="type"
              label="Separation"
              value={view.date_separator ?? 'dash'}
              options={[
                { value: 'dash', label: 'Dash' },
                { value: 'slash', label: 'Slash' }
              ]}
              onPick={(v) => save({ date_separator: v })}
            />
          )}
          {group.kind === 'property' && (
            <MenuItem
              className={flushTrailing}
              leading={
                <span className={footingSymbol}>
                  <Icon name="eye-off" size={12} />
                </span>
              }
              trailing={
                <span className={cx(chipBox, group.hide_empty_groups ? undefined : chipColor.default)} style={checkboxBoxStyle(group.hide_empty_groups, undefined)}>
                  {group.hide_empty_groups ? <Icon name="check" size={12} strokeWidth={3} /> : null}
                </span>
              }
              onClick={() => saveGroup({ ...group, hide_empty_groups: !group.hide_empty_groups })}
            >
              <span className={footingLabel}>Hide Empty Groups</span>
            </MenuItem>
          )}
        </>
      )}
    </>
  )
}

/** A value footing — the ViewSettings Format-footer look (footing icon + label) with the Order
 *  rows' PickerControl as its trailing picker. */
function FootingPick<T extends string>({
  icon,
  label,
  value,
  options,
  onPick
}: {
  icon: React.ComponentProps<typeof Icon>['name']
  label: string
  value: T
  options: PickerChoice<T>[]
  onPick: (v: T) => void
}): React.JSX.Element {
  return (
    <MenuItem
      className={`${flushTrailing} ${gp.pickerTone}`}
      leading={
        <span className={footingSymbol}>
          <Icon name={icon} size={12} />
        </span>
      }
      trailing={<PickerControl ariaLabel={label} value={value} options={options} onPick={onPick} />}
    >
      <span className={footingLabel}>{label}</span>
    </MenuItem>
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
  const all = optionsOf(def)
  const ordered = bucketOrder(group, def, new Set(all.map((o) => o.value)))
  const byValue = new Map(all.map((o) => [o.value, o]))
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

/** The set hierarchy (C-2): sets with their sub-group disclosed beneath them, no pages. Each set
 *  discloses what the sub-group yields — sub-sets under Location, the property's value chips under
 *  a property sub-group (sub-sets flatten, F-3) — both riding the rail. Drags mirror the table
 *  band rules (F-4): sibling reorder writes view order in Custom / the filesystem in Location; a
 *  cross-nesting drop is always an fs reparent. Chip rows are inert (their reorder surface is the
 *  table bands, F-1). */
function LocationHierarchy({
  source,
  view,
  subDef,
  onSaveView
}: {
  source: CollectionNode | SetNode
  view: SavedView
  /** The sub-group property's definition when sub-grouped by a property; undefined = Location. */
  subDef: PropertyDefinition | undefined
  onSaveView: (patch: Partial<SavedView>) => void
}): React.JSX.Element {
  const mutate = useSession((st) => st.mutate)
  const hideChevrons = useSession((st) => st.personalization.hideChevrons ?? false)
  // Sub-groups are hidden by default — a set discloses on demand.
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const flat = subDef !== undefined

  // The property sub-group's disclosed chips — the same value run under every top-level set.
  const subOptions = optionsOf(subDef)
  const subByValue = new Map(subOptions.map((o) => [o.value, o]))
  const subChips = subDef
    ? bucketOrder({ order_mode: view.sub_group?.order_mode ?? 'configured', order: view.sub_group?.order }, subDef, new Set(subOptions.map((o) => o.value)))
        .flatMap((v) => {
          const o = subByValue.get(v)
          return o ? [o] : []
        })
    : []

  const allIds: string[] = []
  const childIds = new Map<string | null, string[]>()
  const paths = new Map<string, string>()
  const bands: Band[] = []
  const chipValueOf = new Map<string, string>()
  const chipBandId = (setId: string, value: string): string => {
    const id = `sub:${setId}:${value}`
    chipValueOf.set(id, value)
    return id
  }
  const index = (sets: SetNode[] | undefined, depth: number, parentId: string | null, visible: boolean): void => {
    childIds.set(parentId, (sets ?? []).map((s) => s.id))
    for (const s of sets ?? []) {
      allIds.push(s.id)
      paths.set(s.id, s.path)
      if (visible) {
        bands.push({ id: s.id, kind: 'set', depth, parentId })
        // A disclosed chip run registers as property bands so the SAME gesture drags them (F-1's
        // pane surface) — the drop resolves back to the value through chipValueOf.
        if (flat && expanded.has(s.id)) {
          for (const o of subChips) bands.push({ id: chipBandId(s.id, o.value), kind: 'property', depth: depth + 1, parentId: s.id })
        }
      }
      index(s.sets, depth + 1, s.id, visible && !flat && expanded.has(s.id))
    }
  }
  index(source.sets, 0, null, true)

  const onDrop = (draggedId: string, drop: GroupingDrop): void => {
    // A chip drag is a GLOBAL sub-order write regardless of drop kind or target set (F-1's
    // semantics); dragging also flips the sub-order to Custom (the first-UI-writer pattern).
    if (chipValueOf.has(draggedId)) {
      const value = chipValueOf.get(draggedId)
      const before = drop.beforeId === null ? null : (chipValueOf.get(drop.beforeId) ?? null)
      if (value === undefined || !view.sub_group) return
      onSaveView({
        sub_group: {
          ...view.sub_group,
          order_mode: 'manual',
          order: nextOrder(subChips.map((o) => o.value), value, before)
        }
      })
      return
    }
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

  const dnd = useGroupingListDrag({ bands, nestable: true, onDrop })
  const toggle = (id: string): void =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  const subType = subDef?.type === 'status' ? 'status' : 'select'

  // Recursive render: each set row + a Reveal (the sidebar's disclosure motion) carrying its
  // sub-group — sub-sets under Location, the chip run under a property sub-group. The chevron sits
  // LEFT of the icon (the sidebar cluster) and honors the Hide Chevrons personalization; the row
  // itself toggles either way.
  const renderSet = (s: SetNode): React.JSX.Element => {
    const kids = flat ? [] : (s.sets ?? [])
    const disclosable = flat ? subChips.length > 0 : kids.length > 0
    const isOpen = expanded.has(s.id)
    return (
      <div key={s.id}>
        <div ref={dnd.rowRef(s.id)} {...dnd.rowHandle(s.id)} style={dnd.draggingId === s.id ? { opacity: 0.4 } : undefined}>
          <MenuItem
            selected={dnd.nestTarget === s.id}
            leading={
              <>
                {!hideChevrons && disclosable ? (
                  <Icon
                    name="chevron-right"
                    size={12}
                    className={isOpen ? 'twisty open' : 'twisty'}
                    onClick={(e) => {
                      e.stopPropagation()
                      toggle(s.id)
                    }}
                    onPointerDown={(e) => e.stopPropagation()}
                  />
                ) : null}
                <Icon name={iconNameOr(s.icon, defaultEntityIcon('set'))} size={13} />
              </>
            }
            onClick={disclosable ? () => toggle(s.id) : undefined}
          >
            {s.title}
          </MenuItem>
        </div>
        {disclosable && (
          <Reveal open={isOpen}>
            <div className={gp.railRow}>
              {flat
                ? subChips.map((o) => {
                    const id = `sub:${s.id}:${o.value}`
                    return (
                      <div
                        key={o.value}
                        ref={dnd.rowRef(id)}
                        {...dnd.rowHandle(id)}
                        className={`${gp.chipRow} ${gp.subChip}`}
                        style={dnd.draggingId === id ? { opacity: 0.4 } : undefined}
                      >
                        <Chip color={chipColorFor(o.color)} label={o.label} shape={chipShapeForType(subType)} />
                      </div>
                    )
                  })
                : kids.map(renderSet)}
            </div>
          </Reveal>
        )}
      </div>
    )
  }

  return (
    <div ref={dnd.containerRef} style={{ position: 'relative' }}>
      {(source.sets ?? []).map(renderSet)}
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
    ...groupable.map((d) => ({ value: d.id, label: d.name, icon: asRenderableIcon(d.icon) ?? propertyTypeIconName(d.type) }))
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
