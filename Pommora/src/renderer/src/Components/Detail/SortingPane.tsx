// The Sorting leaf — authors a table view's sort[] behind both doors (SettingsPane's Sort entry,
// ViewSettings' Sort leaf) on the grouping chassis: Sort By (pane-flip disclosure) · Order ·
// Sub-Sort · its sub Order · the example order. The pane owns the sort slot WHOLESALE — every
// write is [primary], [primary, sub], or undefined (the Group By wholesale-replacement precedent);
// a foreign 3+-key tail renders by its first two slots until the first write replaces the slot.
import { useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { RESERVED_PROPERTY_ID } from '@shared/properties'
import type { SavedView, SortCriterion } from '@shared/views'
import { Icon, asRenderableIcon, type IconName } from '@renderer/design-system/symbols'
import { MenuItem, MenuPaneTopRow, MenuSeparator } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { Reveal } from '../../design-system/components/Reveal'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { declaredType } from '../../Detail/Views/pipeline/value'
import { cx } from '../../design-system/cx'
import { useSession } from '../../store'
import { PickerControl, type PickerChoice } from './PickerControl'
import { PropertyPreview } from './GroupingPane'
import { propertyTypeIconName, TITLE_META } from './PropertyTypes'
import * as gp from './groupingPane.css'

type Direction = SortCriterion['direction']

/** The pane's Sort By offering — only what makeSorter actually ranks. context/file route to a
 *  no-op text key in the sorter, so they're deliberately absent (never offer what the extractor
 *  can't rank); tiers are unsortable outright. */
const SORTABLE_PANE = new Set(['select', 'status', 'number', 'datetime', 'checkbox', 'url', 'multi_select'])

const OPTION_DIRECTIONS: PickerChoice<Direction>[] = [
  { value: 'ascending', label: 'Default' },
  { value: 'descending', label: 'Reversed' }
]
const VALUE_DIRECTIONS: PickerChoice<Direction>[] = [
  { value: 'ascending', label: 'Ascending' },
  { value: 'descending', label: 'Descending' }
]
const TEXT_DIRECTIONS: PickerChoice<Direction>[] = [
  { value: 'ascending', label: 'A → Z' },
  { value: 'descending', label: 'Z → A' }
]

/** Per-type direction vocabulary (D-3): option-ordered types read the grouping pane's locked
 *  Default/Reversed; temporal/numeric read Ascending/Descending; text reads A → Z. A dead def
 *  falls to the value labels. */
function directionOptions(propertyId: string, schema: PropertyDefinition[]): PickerChoice<Direction>[] {
  if (propertyId === RESERVED_PROPERTY_ID.title) return TEXT_DIRECTIONS
  if (propertyId === RESERVED_PROPERTY_ID.modifiedAt) return VALUE_DIRECTIONS
  switch (declaredType(propertyId, schema)) {
    case 'select':
    case 'status':
      return OPTION_DIRECTIONS
    case 'url':
    case 'multi_select':
      return TEXT_DIRECTIONS
    default:
      return VALUE_DIRECTIONS
  }
}

interface SortTarget {
  id: string
  label: string
  icon: IconName | undefined
}

/** Title + Modified are reserved columns, not schema defs — offered as fixed targets ahead of the
 *  schema's sortable set (they sort via buildCriterion's reserved-id branches). */
function sortTargets(schema: PropertyDefinition[]): SortTarget[] {
  return [
    { id: RESERVED_PROPERTY_ID.title, label: 'Title', icon: TITLE_META.icon },
    { id: RESERVED_PROPERTY_ID.modifiedAt, label: 'Modified', icon: propertyTypeIconName('last_edited_time') },
    ...schema
      .filter((d) => SORTABLE_PANE.has(declaredType(d.id, schema) ?? ''))
      .map((d) => ({ id: d.id, label: d.name, icon: asRenderableIcon(d.icon) ?? propertyTypeIconName(d.type) }))
  ]
}

/** A labeled row whose trailing PickerControl pops the option menu — the GroupingPane ValueRow
 *  shape; `tier: 'sub'` is the subordinate Order treatment. */
function ValueRow<T extends string>({
  tier = 'primary',
  icon,
  label,
  value,
  options,
  onPick
}: {
  tier?: 'primary' | 'sub'
  icon?: React.ComponentProps<typeof Icon>['name']
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

export function SortingPane({
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
  const [sortByOpen, setSortByOpen] = useState(false)
  const save = (sort: SortCriterion[] | undefined): void => void saveViewAdopting(source, { ...view, sort }, load)

  const primary = view.sort?.[0]
  const sub = view.sort?.[1]
  const targets = sortTargets(schema)
  const targetById = new Map(targets.map((t) => [t.id, t]))
  // A dead criterion (deleted def) renders by its raw id (D-6) — the pane never silently drops
  // config it didn't write; None clears it like any other.
  const nameOf = (c: SortCriterion): string => targetById.get(c.property_id)?.label ?? c.property_id

  const pickPrimary = (id: string | null): void => {
    setSortByOpen(false)
    if (id === null) {
      if (primary) save(undefined)
      return
    }
    if (primary?.property_id === id) return
    const fresh: SortCriterion = { property_id: id, direction: 'ascending' }
    save(sub && sub.property_id !== id ? [fresh, sub] : [fresh])
  }

  const pickSub = (id: string | null): void => {
    if (!primary) return
    if (id === null) {
      if (sub) save([primary])
      return
    }
    if (sub?.property_id === id) return
    save([primary, { property_id: id, direction: 'ascending' }])
  }

  // The example order (D-5): only a finite-ordered primary previews — the hasMiddle logic.
  const primaryType = primary ? declaredType(primary.property_id, schema) : undefined
  const finiteDef =
    primaryType === 'select' || primaryType === 'status' ? schema.find((d) => d.id === primary?.property_id) : undefined

  const subOptions: PickerChoice<string>[] = [
    { value: '_none', label: 'None', icon: 'circle-off' as const },
    ...targets.filter((t) => t.id !== primary?.property_id).map((t) => ({ value: t.id, label: t.label, icon: t.icon }))
  ]

  return (
    <>
      <MenuPaneTopRow label={label} current="Sorting" onBack={onBack} />
      <MenuItem
        className={flushTrailing}
        leading={<Icon name="arrow-up-down" size={14} />}
        trailing={
          <span className={gp.groupByValue}>
            {primary ? nameOf(primary) : 'None'}
            <Icon name="chevrons-up-down" size={12} />
          </span>
        }
        onClick={() => setSortByOpen((o) => !o)}
      >
        Sort By
      </MenuItem>
      <Reveal open={sortByOpen}>
        <div className={`${gp.middle} overflow-eclipse-y`}>
          <MenuItem
            leading={<Icon name="circle-off" size={13} />}
            trailing={!primary ? <Icon name="check" size={12} /> : undefined}
            onClick={() => pickPrimary(null)}
          >
            None
          </MenuItem>
          {targets
            .filter((t) => t.id !== sub?.property_id)
            .map((t) => (
              <MenuItem
                key={t.id}
                leading={<Icon name={t.icon ?? 'tag'} size={13} />}
                trailing={primary?.property_id === t.id ? <Icon name="check" size={12} /> : undefined}
                onClick={() => pickPrimary(t.id)}
              >
                {t.label}
              </MenuItem>
            ))}
        </div>
      </Reveal>
      {!sortByOpen && primary && (
        <>
          <ValueRow
            tier={sub ? 'sub' : 'primary'}
            icon="arrow-down-up"
            label="Order"
            value={primary.direction}
            options={directionOptions(primary.property_id, schema)}
            onPick={(d) => {
              const next = { ...primary, direction: d }
              save(sub ? [next, sub] : [next])
            }}
          />
          <ValueRow
            icon="arrow-up-down"
            label="Sub-Sort"
            value={sub?.property_id ?? '_none'}
            options={subOptions}
            onPick={(v) => pickSub(v === '_none' ? null : v)}
          />
          {sub && (
            <ValueRow
              tier="sub"
              icon="arrow-down-up"
              label="Order"
              value={sub.direction}
              options={declaredType(sub.property_id, schema) === 'checkbox' ? VALUE_DIRECTIONS : OPTION_DIRECTIONS}
              onPick={(d) => save([primary, { ...sub, direction: d }])}
            />
          )}
          {finiteDef && (
            <>
              <MenuSeparator flush />
              <div className={`${gp.middle} overflow-eclipse-y`}>
                <PropertyPreview
                  group={{ order_mode: primary.direction === 'descending' ? 'reversed' : 'configured' }}
                  def={finiteDef}
                />
              </div>
            </>
          )}
        </>
      )}
    </>
  )
}
