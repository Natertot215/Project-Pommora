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
import { MenuItem, MenuPaneTopRow, MenuSeparator } from '../../design-system/components/menu'
import { flushTrailing, footingLabel, footingSymbol } from '../../design-system/components/menu/menu.css'
import { PickerMenu, PickerOption } from '../../design-system/components/PickerMenu'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { tierLabel, TIER_LEVEL_BY_ID } from '../../Detail/Views/Table/columnLabel'
import { cx } from '../../design-system/cx'
import { useSession } from '../../store'
import { PickerControl, type PickerChoice } from './PickerControl'
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
  placeholder,
  children
}: {
  ariaLabel: string
  display: string | null
  icon?: React.ComponentProps<typeof Icon>['name']
  placeholder: string
  children: (close: () => void) => React.ReactNode
}): React.JSX.Element {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLButtonElement>(null)
  return (
    <>
      <button ref={ref} type="button" className={fp.cellField} aria-label={ariaLabel} onClick={() => setOpen(true)}>
        {icon ? <Icon name={icon} size={13} /> : null}
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

  /** Task 8 replaces this static display with the per-slot editors. */
  const valueCell = (row: PaneRow, op: OperatorChoice | undefined): React.ReactNode => {
    if (!op || op.slot === 'none') return <span />
    const shown = row.rule.values?.join(', ') ?? row.rule.value ?? null
    return (
      <span className={fp.cellField}>
        <span className={shown === null ? fp.placeholder : undefined}>{shown ?? 'Value'}</span>
      </span>
    )
  }

  const ruleRow = (row: PaneRow, index: number): React.JSX.Element => {
    const ops = operatorsFor(row.rule.property_id, schema)
    const current = ops.find((o) => o.op === row.rule.op && (o.impliedValue === undefined || o.impliedValue === row.rule.value))
    const target = targetById.get(row.rule.property_id)
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
        <FieldPicker ariaLabel="Filter operator" display={current?.label ?? row.rule.op} placeholder="Condition">
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
                {o.label}
              </PickerOption>
            ))
          }
        </FieldPicker>
        {valueCell(row, current)}
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
