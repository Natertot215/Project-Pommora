// The Filtering leaf — authors a table view's filter behind both doors (SettingsPane's Filter
// entry, ViewSettings' Filter leaf). The lead Matches row (All / Any / None — None disables,
// dimming and locking the rules without deleting them) sits over the flat rule grid: each row is
// (connector)(what)(operator)(value)(×), serialized to the nested FilterGroup by filterModel. The
// pane owns the filter slot wholesale for shapes it writes; a hand-authored tree it can't
// represent renders locked behind an explicit Reset (never silently flattened).
import { useRef, useState } from 'react'
import type { CollectionNode, NexusTree, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { RESERVED_PROPERTY_ID } from '@shared/properties'
import type { FilterRule, SavedView } from '@shared/views'
import { Icon } from '@renderer/design-system/symbols'
import { Chip, chipShapeForType } from '@renderer/Components/Chip'
import { ContextChip } from '@renderer/Components/ContextChip'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { MenuItem, MenuPaneTopRow, MenuSeparator } from '../../design-system/components/menu'
import { flushTrailing, footingLabel, footingSymbol } from '../../design-system/components/menu/menu.css'
import { PickerMenu, PickerOption } from '../../design-system/components/PickerMenu'
import { CalendarPicker } from '../../design-system/components/CalendarPicker/CalendarPicker'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { tierLabel, TIER_LEVEL_BY_ID } from '../../Detail/Views/Table/columnLabel'
import { styleFor } from '../../Detail/Views/Table/columnStyles'
import { condensedDate, formatDate } from '../../Detail/Views/PropertyEditing/formatValue'
import { contextOptionsFor, type ContextOption } from '../../Detail/Views/pipeline/contextOptions'
import { declaredType } from '../../Detail/Views/pipeline/value'
import { solidColorCss } from '../../Detail/Views/Table/solidColor'
import { cx } from '../../design-system/cx'
import { useSession } from '../../store'
import { PickerControl, type PickerChoice } from './PickerControl'
import { optionsOf } from './GroupingPane'
import {
  type Connector,
  type DecodedFilter,
  type FilterTarget,
  type OperatorChoice,
  type PaneRow,
  decodeFilter,
  encodeFilter,
  filterTargets,
  operatorsFor
} from './filterModel'
import * as gp from './groupingPane.css'
import * as fp from './filterPane.css'

type MatchPick = 'all' | 'any' | 'none'
const MATCH_OPTIONS: PickerChoice<MatchPick>[] = [
  { value: 'all', label: 'All' },
  { value: 'any', label: 'Any' },
  { value: 'none', label: 'None' }
]

/** A grid-cell trigger field popping a beaked PickerMenu — the What/Operator control. */
function FieldPicker({
  ariaLabel,
  display,
  icon,
  iconColor,
  placeholder,
  children
}: {
  ariaLabel: string
  display: string | null
  icon?: React.ComponentProps<typeof Icon>['name']
  iconColor?: string
  placeholder: string
  children: (close: () => void) => React.ReactNode
}): React.JSX.Element {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLButtonElement>(null)
  return (
    <>
      <button ref={ref} type="button" className={fp.cellField} aria-label={ariaLabel} onClick={() => setOpen(true)}>
        {icon ? <Icon name={icon} size={13} {...(iconColor ? { style: { color: iconColor } } : {})} /> : null}
        <span className={display === null ? fp.placeholder : undefined}>{display ?? placeholder}</span>
        <Icon name="chevrons-up-down" size={12} />
      </button>
      <PickerMenu open={open} onDismiss={() => setOpen(false)} triggerRef={ref} solid>
        {children(() => setOpen(false))}
      </PickerMenu>
    </>
  )
}

/** A fresh rule for a just-picked target: its type's first operator, operands cleared (the
 *  checkbox family's implied value rides along). */
function mintRule(targetId: string, schema: PropertyDefinition[]): FilterRule {
  const first = operatorsFor(targetId, schema)[0]
  return { property_id: targetId, op: first?.op ?? '', ...(first?.impliedValue ? { value: first.impliedValue } : {}) }
}

/** The typed value input (text / number) — commits on blur and Enter. Keyed remount on external
 *  value change keeps it uncontrolled between commits. */
function ValueInput({
  value,
  numeric,
  onCommit
}: {
  value: string | undefined
  numeric: boolean
  onCommit: (next: string | undefined) => void
}): React.JSX.Element {
  const commit = (raw: string): void => {
    const next = raw.trim() === '' ? undefined : raw
    if (next !== value) onCommit(next)
  }
  return (
    <input
      key={value ?? ''}
      className={fp.cellInput}
      defaultValue={value ?? ''}
      placeholder="Value"
      {...(numeric ? { inputMode: 'decimal' as const } : {})}
      onBlur={(e) => commit(e.currentTarget.value)}
      onKeyDown={(e) => {
        if (e.key === 'Enter') commit(e.currentTarget.value)
      }}
    />
  )
}

/** The chips field — the FILTER-OWNED picker host: the same stay-open toggle vocabulary as the
 *  cell pickers, but committing raw option-value strings into the rule's values[] (never a
 *  PropertyValue — the cell pickers' commit shape is a different axis). */
function ChipsField({
  values,
  options,
  isContext,
  chipShape,
  onCommit
}: {
  values: string[]
  options: ContextOption[]
  isContext: boolean
  chipShape: 'pill' | 'label'
  onCommit: (next: string[]) => void
}): React.JSX.Element {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLButtonElement>(null)
  const byValue = new Map(options.map((o) => [o.value, o]))
  const toggle = (v: string): void => onCommit(values.includes(v) ? values.filter((x) => x !== v) : [...values, v])
  return (
    <>
      <button ref={ref} type="button" className={fp.cellField} aria-label="Filter values" onClick={() => setOpen(true)}>
        {values.length === 0 ? (
          <span className={fp.placeholder}>Value</span>
        ) : (
          <span className={cx(fp.chipRun, gp.subChip)}>
            {values.map((v) => {
              const o = byValue.get(v)
              return isContext ? (
                <ContextChip key={v} color={chipColorFor(o?.color)} title={o?.label ?? v} />
              ) : (
                <Chip key={v} color={chipColorFor(o?.color)} label={o?.label ?? v} shape={chipShape} onRemove={() => toggle(v)} />
              )
            })}
          </span>
        )}
        <Icon name="chevrons-up-down" size={12} />
      </button>
      <PickerMenu open={open} onDismiss={() => setOpen(false)} triggerRef={ref} solid>
        {options.length === 0 ? (
          <div style={{ minWidth: 96, height: 24 }} />
        ) : (
          options.map((o) => (
            <PickerOption key={o.value} selected={values.includes(o.value)} onClick={() => toggle(o.value)}>
              {isContext ? (
                <ContextChip color={chipColorFor(o.color)} title={o.label} />
              ) : (
                <Chip color={chipColorFor(o.color)} label={o.label} shape={chipShape} />
              )}
            </PickerOption>
          ))
        )}
      </PickerMenu>
    </>
  )
}

/** A Collection/Set's sets flattened depth-first with indentation depth — the Location picker's list. */
function flattenSets(sets: SetNode[] | undefined, depth = 0): Array<{ id: string; title: string; depth: number }> {
  return (sets ?? []).flatMap((s) => [{ id: s.id, title: s.title, depth }, ...flattenSets(s.sets, depth + 1)])
}

export function FilterPane({
  source,
  view,
  schema,
  tree,
  label,
  onBack
}: {
  source: CollectionNode | SetNode
  view: SavedView
  schema: PropertyDefinition[]
  tree: NexusTree | null
  /** The back-destination breadcrumb — 'Settings' from SettingsPane, 'Views' from ViewSettings. */
  label: string
  onBack: () => void
}): React.JSX.Element {
  const load = useSession((st) => st.load)
  // The "+" draft — local until it gains a target (an incomplete rule is never written). Cleared
  // synchronously in the same handler that dispatches its write; the hosts key the pane by view id,
  // so a view switch can never float a stale draft onto another view's rows.
  const [draft, setDraft] = useState<Connector | null | false>(false)

  const decoded: DecodedFilter = decodeFilter(view.filter)
  const enabled = decoded.enabled
  const rows: PaneRow[] = decoded.kind === 'rows' ? decoded.rows : []
  const mode: MatchPick = !enabled ? 'none' : decoded.kind === 'rows' ? decoded.mode : 'all'

  const save = (nextEnabled: boolean, nextRows: PaneRow[]): void =>
    void saveViewAdopting(source, { ...view, filter: encodeFilter(nextEnabled, nextRows) }, load)

  const targets = filterTargets(schema).map(
    (t): FilterTarget =>
      tree && TIER_LEVEL_BY_ID[t.id] ? { ...t, label: tierLabel(TIER_LEVEL_BY_ID[t.id], tree.labels) } : t
  )
  const targetById = new Map(targets.map((t) => [t.id, t]))

  const pickMatch = (pick: MatchPick): void => {
    if (pick === mode) return
    if (pick === 'none') {
      save(false, rows)
      return
    }
    // Re-enable and/or bulk-set: every connector takes the picked mode (deviations reset).
    const bulk: Connector = pick === 'any' ? 'or' : 'and'
    save(
      true,
      rows.map((row, i) => ({ ...row, connector: i === 0 ? null : bulk }))
    )
  }

  const replaceRule = (index: number, rule: FilterRule): void =>
    save(
      enabled,
      rows.map((row, i) => (i === index ? { ...row, rule } : row))
    )

  const removeRow = (index: number): void => {
    const next = rows.filter((_, i) => i !== index)
    if (next.length > 0) next[0] = { ...next[0], connector: null }
    save(enabled, next)
  }

  const toggleConnector = (index: number): void =>
    save(
      enabled,
      rows.map((row, i) => (i === index ? { ...row, connector: row.connector === 'and' ? 'or' : 'and' } : row))
    )

  /** The draft's What pick — the one moment a draft becomes a real (written) rule. */
  const completeDraft = (targetId: string): void => {
    setDraft(false)
    save(enabled, [...rows, { connector: rows.length === 0 ? null : draft === false ? null : draft, rule: mintRule(targetId, schema) }])
  }

  const targetOptions = (onPick: (id: string) => void, close: () => void): React.ReactNode =>
    targets.map((t) => (
      <PickerOption
        key={t.id}
        selected={false}
        onClick={() => {
          close()
          onPick(t.id)
        }}
      >
        <span className={fp.pickerOptionRow}>
          <Icon name={t.icon ?? 'tag'} size={13} />
          {t.label}
        </span>
      </PickerOption>
    ))

  /** The per-slot value editor (F-4). */
  const valueCell = (row: PaneRow, index: number, op: OperatorChoice | undefined): React.ReactNode => {
    if (!op || op.slot === 'none') return <span />
    const rule = row.rule
    const def = schema.find((d) => d.id === rule.property_id)
    const patch = (next: Partial<Pick<FilterRule, 'value' | 'values'>>): void =>
      replaceRule(index, {
        property_id: rule.property_id,
        op: rule.op,
        ...(next.value !== undefined ? { value: next.value } : {}),
        ...(next.values !== undefined && next.values.length > 0 ? { values: next.values } : {})
      })

    if (op.slot === 'text' || op.slot === 'number')
      return <ValueInput value={rule.value} numeric={op.slot === 'number'} onCommit={(v) => patch({ value: v })} />

    if (op.slot === 'date') {
      const fmtRaw = styleFor(rule.property_id, schema, view).date_format ?? 'full'
      const fmt = fmtRaw === 'relative' ? 'short' : fmtRaw
      return (
        <FieldPicker
          ariaLabel="Filter date"
          display={rule.value ? formatDate(rule.value, fmt, 'none') : null}
          placeholder="Date"
        >
          {() => (
            <CalendarPicker
              range={false}
              value={rule.value ?? null}
              timeFormat={tree?.timeFormat}
              formatDateValue={(k, condensed) => (condensed ? condensedDate(k, fmt, condensed.withYear) : formatDate(k, fmt, 'none'))}
              onChange={(iso) => patch({ value: iso ?? undefined })}
            />
          )}
        </FieldPicker>
      )
    }

    if (op.slot === 'chips') {
      const type = declaredType(rule.property_id, schema)
      const tierLevel = TIER_LEVEL_BY_ID[rule.property_id] ?? def?.context_target?.tier
      const isContext = type === 'tier' || type === 'context'
      const options: ContextOption[] = isContext ? (tree && tierLevel ? contextOptionsFor(tierLevel, tree) : []) : optionsOf(def)
      return (
        <ChipsField
          values={rule.values ?? []}
          options={options}
          isContext={isContext}
          chipShape={chipShapeForType(type ?? 'select')}
          onCommit={(values) => patch({ values })}
        />
      )
    }

    // slot === 'set' (Location)
    const sets = flattenSets(source.kind === 'collection' ? source.sets : source.sets)
    const current = sets.find((s) => s.id === rule.value)
    return (
      <FieldPicker ariaLabel="Filter location" display={current?.title ?? rule.value ?? null} placeholder="Set">
        {(close) =>
          sets.length === 0 ? (
            <div style={{ minWidth: 96, height: 24 }} />
          ) : (
            sets.map((s) => (
              <PickerOption
                key={s.id}
                selected={s.id === rule.value}
                onClick={() => {
                  close()
                  patch({ value: s.id })
                }}
              >
                <span className={fp.pickerOptionRow} style={{ paddingLeft: s.depth * 12 }}>
                  <Icon name="folder" size={13} />
                  {s.title}
                </span>
              </PickerOption>
            ))
          )
        }
      </FieldPicker>
    )
  }

  const ruleRow = (row: PaneRow, index: number): React.JSX.Element => {
    const ops = operatorsFor(row.rule.property_id, schema)
    const current = ops.find((o) => o.op === row.rule.op && (o.impliedValue === undefined || o.impliedValue === row.rule.value))
    const target = targetById.get(row.rule.property_id)
    // The checkbox family leads with its box glyph — checked wears the def's property-wide
    // checkbox_color (absent = the accent), an empty box stays neutral (F-5, the Cell recipe).
    const isCheckbox = declaredType(row.rule.property_id, schema) === 'checkbox'
    const checkboxColor = solidColorCss(schema.find((d) => d.id === row.rule.property_id)?.checkbox_color)
    const checkboxGlyph = (o: OperatorChoice): { icon: 'square-check' | 'square'; color?: string } =>
      o.impliedValue === 'true' ? { icon: 'square-check', color: checkboxColor } : { icon: 'square' }
    return (
      <div key={index} className={fp.gridRow}>
        {row.connector === null ? (
          <span className={fp.connectorSpacer} />
        ) : (
          <button type="button" className={fp.connector} aria-label="Toggle connector" onClick={() => toggleConnector(index)}>
            {row.connector === 'and' ? 'And' : 'Or'}
            <Icon name="chevrons-up-down" size={10} />
          </button>
        )}
        <FieldPicker
          ariaLabel="Filter property"
          display={target?.label ?? row.rule.property_id}
          icon={target?.icon}
          placeholder="Property"
        >
          {(close) => targetOptions((id) => id !== row.rule.property_id && replaceRule(index, mintRule(id, schema)), close)}
        </FieldPicker>
        <FieldPicker
          ariaLabel="Filter operator"
          display={current?.label ?? row.rule.op}
          {...(isCheckbox && current ? { icon: checkboxGlyph(current).icon, iconColor: checkboxGlyph(current).color } : {})}
          placeholder="Condition"
        >
          {(close) =>
            ops.map((o) => (
              <PickerOption
                key={o.label}
                selected={o === current}
                onClick={() => {
                  close()
                  // Operands survive only within the same slot; an implied value writes through.
                  const keep = o.slot === current?.slot
                  replaceRule(index, {
                    property_id: row.rule.property_id,
                    op: o.op,
                    ...(o.impliedValue !== undefined
                      ? { value: o.impliedValue }
                      : keep
                        ? { ...(row.rule.value !== undefined ? { value: row.rule.value } : {}), ...(row.rule.values ? { values: row.rule.values } : {}) }
                        : {})
                  })
                }}
              >
                {isCheckbox ? (
                  <span className={fp.pickerOptionRow}>
                    <Icon
                      name={checkboxGlyph(o).icon}
                      size={13}
                      {...(checkboxGlyph(o).color ? { style: { color: checkboxGlyph(o).color } } : {})}
                    />
                    {o.label}
                  </span>
                ) : (
                  o.label
                )}
              </PickerOption>
            ))
          }
        </FieldPicker>
        {valueCell(row, index, current)}
        <button type="button" className={fp.removeButton} aria-label="Remove filter" onClick={() => removeRow(index)}>
          <Icon name="circle-x" size={12} />
        </button>
      </div>
    )
  }

  const draftRow = draft !== false && (
    <div className={fp.gridRow}>
      {rows.length === 0 ? (
        <span className={fp.connectorSpacer} />
      ) : (
        <span className={fp.connector}>{mode === 'any' ? 'Or' : 'And'}</span>
      )}
      <FieldPicker ariaLabel="Filter property" display={null} placeholder="Property">
        {(close) => targetOptions((id) => completeDraft(id), close)}
      </FieldPicker>
      <span className={cx(fp.cellField, fp.placeholder)}>Condition</span>
      <span />
      <button type="button" className={fp.removeButton} aria-label="Remove filter" onClick={() => setDraft(false)}>
        <Icon name="circle-x" size={12} />
      </button>
    </div>
  )

  return (
    <div className={fp.pane}>
      <MenuPaneTopRow label={label} current="Filtering" onBack={onBack} />
      <MenuItem
        className={cx(flushTrailing, gp.pickerTone)}
        trailing={<PickerControl ariaLabel="Matches" value={mode} options={MATCH_OPTIONS} onPick={pickMatch} />}
      >
        Matches
      </MenuItem>
      <MenuSeparator flush />
      {decoded.kind === 'locked' ? (
        <>
          <div className={fp.lockedCaption}>Hand-authored filter — edited outside the pane.</div>
          <MenuItem
            className={flushTrailing}
            leading={
              <span className={footingSymbol}>
                <Icon name="rotate-ccw" size={12} />
              </span>
            }
            onClick={() => save(true, [])}
          >
            <span className={footingLabel}>Reset Filter</span>
          </MenuItem>
        </>
      ) : (
        <>
          <div className={cx(gp.middle, 'overflow-eclipse-y', !enabled && fp.disabled)}>
            <div className={fp.grid}>
              {rows.map(ruleRow)}
              {draftRow}
            </div>
          </div>
          <MenuSeparator flush />
          <MenuItem
            className={cx(flushTrailing, !enabled && fp.disabled)}
            leading={
              <span className={footingSymbol}>
                <Icon name="plus" size={13} />
              </span>
            }
            onClick={() => setDraft(rows.length === 0 ? null : mode === 'any' ? 'or' : 'and')}
          >
            <span />
          </MenuItem>
        </>
      )}
    </div>
  )
}
