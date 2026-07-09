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
import { Icon, asRenderableIcon, type IconName } from '@renderer/design-system/symbols'
import { MenuItem, MenuSeparator, MenuPaneTopRow } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { Reveal } from '../../design-system/components/Reveal'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { declaredType } from '../../Detail/Views/pipeline/value'
import { useSession } from '../../store'
import { PickerControl, type PickerChoice } from './PickerControl'
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
        trailing={<Icon name="chevrons-up-down" size={12} />}
        detail={structural ? 'Location' : (activeDef?.name ?? 'Location')}
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
          {/* T9: the middle region (hierarchy / preview / custom list). T10: the footings. */}
        </>
      )}
    </>
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
    { value: '_location', label: 'Location' },
    ...groupable.map((d) => ({ value: d.id, label: d.name }))
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
