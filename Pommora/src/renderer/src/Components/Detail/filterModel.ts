// The FilterPane's pure model — the flat And/Or row list ↔ the on-disk FilterGroup tree, plus the
// pane's target + per-type operator vocabularies. The pane owns the filter slot wholesale for the
// shapes it writes; anything it can't faithfully represent decodes as `locked` and is never
// silently flattened (a rewrite would change the filter's truth table). Pure: no fs, no React.

import type { PropertyDefinition } from '@shared/properties'
import { RESERVED_PROPERTY_ID } from '@shared/properties'
import type { FilterGroup, FilterRule } from '@shared/views'
import type { Icon } from '@renderer/design-system/symbols'
import { asRenderableIcon } from '@renderer/design-system/symbols'
import { declaredType } from '../../Detail/Views/pipeline/value'
import { FILTER_OPS } from '../../Detail/Views/pipeline/filter'
import { propertyTypeIconName, TITLE_META } from './PropertyTypes'

export type Connector = 'and' | 'or'

/** One pane row — `connector` is null on row 0 (nothing to join). */
export interface PaneRow {
  connector: Connector | null
  rule: FilterRule
}

export type DecodedFilter =
  | { kind: 'rows'; enabled: boolean; mode: 'all' | 'any'; rows: PaneRow[] }
  | { kind: 'locked'; enabled: boolean }

const isLeaf = (node: FilterRule | FilterGroup): node is FilterRule => !('rules' in node)
const isAllOfLeaves = (node: FilterRule | FilterGroup): node is FilterGroup =>
  !isLeaf(node) && node.match === 'all' && node.rules.every(isLeaf)

/** Rows → tree. Connectors derive the structure: the list splits into AND-runs at each 'or';
 *  one run = a flat all group, several = any-of-runs (a one-rule run stays a bare leaf). Disable
 *  wraps the live root as the single child of `{match:'none'}` — lossless, so the All/Any base
 *  mode and the run structure survive re-enable verbatim. */
export function encodeFilter(enabled: boolean, rows: PaneRow[]): FilterGroup | undefined {
  const live = (): FilterGroup | undefined => {
    if (rows.length === 0) return undefined
    const runs: FilterRule[][] = [[]]
    for (const row of rows) {
      if (row.connector === 'or' && runs[runs.length - 1].length > 0) runs.push([])
      runs[runs.length - 1].push(row.rule)
    }
    if (runs.length === 1) return { match: 'all', rules: runs[0] }
    return { match: 'any', rules: runs.map((run) => (run.length === 1 ? run[0] : { match: 'all', rules: run })) }
  }
  if (enabled) return live()
  const inner = live()
  return { match: 'none', rules: inner ? [inner] : [] }
}

/** Tree → rows, or `locked` when the shape isn't one the pane writes (defined by SHAPE, never
 *  depth — an `any` nested under an `all` root is only 2 deep but inexpressible flat). Mixed
 *  connectors display mode `all` ("Or" is a valid deviation under All — D-10). */
export function decodeFilter(filter: FilterGroup | undefined): DecodedFilter {
  if (!filter) return { kind: 'rows', enabled: true, mode: 'all', rows: [] }

  if (filter.match === 'none') {
    if (filter.rules.length === 0) return { kind: 'rows', enabled: false, mode: 'all', rows: [] }
    const inner = filter.rules[0]
    if (filter.rules.length !== 1 || isLeaf(inner)) return { kind: 'locked', enabled: false }
    const decoded = decodeFilter(inner)
    return decoded.kind === 'rows' ? { ...decoded, enabled: false } : { kind: 'locked', enabled: false }
  }

  if (filter.match === 'all') {
    if (!filter.rules.every(isLeaf)) return { kind: 'locked', enabled: true }
    return {
      kind: 'rows',
      enabled: true,
      mode: 'all',
      rows: filter.rules.map((rule, i) => ({ connector: i === 0 ? null : 'and', rule }))
    }
  }

  // match === 'any': every child must be a leaf or an all-of-leaves run.
  if (!filter.rules.every((n) => isLeaf(n) || isAllOfLeaves(n))) return { kind: 'locked', enabled: true }
  const rows: PaneRow[] = []
  for (const child of filter.rules) {
    const run = isLeaf(child) ? [child] : (child.rules as FilterRule[])
    run.forEach((rule, i) => rows.push({ connector: rows.length === 0 ? null : i === 0 ? 'or' : 'and', rule }))
  }
  const pureOr = filter.rules.every(isLeaf)
  return { kind: 'rows', enabled: true, mode: pureOr ? 'any' : 'all', rows }
}

// ---- vocabulary ----

export type ValueSlot = 'none' | 'text' | 'number' | 'date' | 'chips' | 'set'

export interface OperatorChoice {
  op: string
  label: string
  slot: ValueSlot
  /** Chip ops: the picker toggles values[] and stays open. */
  multi?: boolean
  /** Self-contained ops (checkbox) write this into `value` on pick. */
  impliedValue?: string
}

const EMPTIES: OperatorChoice[] = [
  { op: FILTER_OPS.isEmpty, label: 'Is Empty', slot: 'none' },
  { op: FILTER_OPS.isNotEmpty, label: "Isn't Empty", slot: 'none' }
]

const TEXT_OPS: OperatorChoice[] = [
  { op: FILTER_OPS.is, label: 'Is', slot: 'text' },
  { op: FILTER_OPS.isNot, label: "Isn't", slot: 'text' },
  { op: FILTER_OPS.startsWith, label: 'Starts With', slot: 'text' },
  { op: FILTER_OPS.contains, label: 'Contains', slot: 'text' },
  { op: FILTER_OPS.doesNotContain, label: "Doesn't Contain", slot: 'text' }
]

const DATE_OPS: OperatorChoice[] = [
  { op: FILTER_OPS.is, label: 'Is', slot: 'date' },
  { op: FILTER_OPS.isBefore, label: 'Is Before', slot: 'date' },
  { op: FILTER_OPS.isAfter, label: 'Is After', slot: 'date' },
  { op: FILTER_OPS.onOrBefore, label: 'Is On or Before', slot: 'date' },
  { op: FILTER_OPS.onOrAfter, label: 'Is On or After', slot: 'date' },
  ...EMPTIES
]

/** Array-valued membership (multi-select, tiers, context relations). */
const SET_OPS: OperatorChoice[] = [
  { op: FILTER_OPS.containsAny, label: 'Is Any', slot: 'chips', multi: true },
  { op: FILTER_OPS.containsAll, label: 'Is All', slot: 'chips', multi: true },
  { op: FILTER_OPS.doesNotContain, label: "Isn't", slot: 'chips', multi: true },
  ...EMPTIES
]

const NUMBER_OPS: OperatorChoice[] = [
  { op: FILTER_OPS.is, label: 'Is', slot: 'number' },
  { op: FILTER_OPS.isNot, label: "Isn't", slot: 'number' },
  { op: FILTER_OPS.greaterThan, label: 'Greater Than', slot: 'number' },
  { op: FILTER_OPS.greaterOrEqual, label: 'At Least', slot: 'number' },
  { op: FILTER_OPS.lessThan, label: 'Less Than', slot: 'number' },
  { op: FILTER_OPS.lessOrEqual, label: 'At Most', slot: 'number' },
  ...EMPTIES
]

/** Single-valued options (select/status): Is/Isn't are chip pickers whose multi-chips mean
 *  any-of/none-of (B-5) — never Is All, which is unsatisfiable on a one-value property. */
const OPTION_OPS: OperatorChoice[] = [
  { op: FILTER_OPS.is, label: 'Is', slot: 'chips', multi: true },
  { op: FILTER_OPS.isNot, label: "Isn't", slot: 'chips', multi: true },
  ...EMPTIES
]

const CHECKBOX_OPS: OperatorChoice[] = [
  { op: FILTER_OPS.is, label: 'Is Checked', slot: 'none', impliedValue: 'true' },
  { op: FILTER_OPS.is, label: "Isn't Checked", slot: 'none', impliedValue: 'false' }
]

const FILE_OPS: OperatorChoice[] = [
  { op: FILTER_OPS.isNotEmpty, label: 'Has File', slot: 'none' },
  { op: FILTER_OPS.isEmpty, label: 'No File', slot: 'none' }
]

const LOCATION_OPS: OperatorChoice[] = [
  { op: FILTER_OPS.isInside, label: 'Is Inside', slot: 'set' },
  { op: FILTER_OPS.isNotInside, label: "Isn't Inside", slot: 'set' }
]

/** Title never offers empty ops — a title (the filename basename) is never empty. */
const TITLE_OPS: OperatorChoice[] = TEXT_OPS

export function operatorsFor(propertyId: string, schema: PropertyDefinition[]): OperatorChoice[] {
  if (propertyId === RESERVED_PROPERTY_ID.title) return TITLE_OPS
  if (propertyId === RESERVED_PROPERTY_ID.location) return LOCATION_OPS
  switch (declaredType(propertyId, schema)) {
    case 'select':
    case 'status':
      return OPTION_OPS
    case 'multi_select':
    case 'tier':
    case 'context':
      return SET_OPS
    case 'number':
      return NUMBER_OPS
    case 'datetime':
    case 'last_edited_time':
      return DATE_OPS
    case 'checkbox':
      return CHECKBOX_OPS
    case 'url':
      return [...TEXT_OPS, ...EMPTIES]
    case 'file':
      return FILE_OPS
    default:
      return []
  }
}

export interface FilterTarget {
  id: string
  label: string
  icon: React.ComponentProps<typeof Icon>['name'] | undefined
}

/** Default tier labels — the pane overrides with the nexus's own (tierLabel) when a tree is up. */
const TIER_TARGETS: FilterTarget[] = [
  { id: RESERVED_PROPERTY_ID.tier1, label: 'Areas', icon: 'layout-grid' },
  { id: RESERVED_PROPERTY_ID.tier2, label: 'Topics', icon: 'layout-grid' },
  { id: RESERVED_PROPERTY_ID.tier3, label: 'Projects', icon: 'layout-grid' }
]

/** The pane's What offering: the reserved targets ahead of every schema def with a non-empty
 *  operator vocabulary (the sortTargets recipe — real def icon, else the type glyph). */
export function filterTargets(schema: PropertyDefinition[]): FilterTarget[] {
  return [
    { id: RESERVED_PROPERTY_ID.title, label: 'Title', icon: TITLE_META.icon },
    { id: RESERVED_PROPERTY_ID.location, label: 'Location', icon: 'folder' },
    { id: RESERVED_PROPERTY_ID.modifiedAt, label: 'Modified', icon: propertyTypeIconName('last_edited_time') },
    ...TIER_TARGETS,
    ...schema
      .filter((d) => operatorsFor(d.id, schema).length > 0)
      .map((d) => ({ id: d.id, label: d.name, icon: asRenderableIcon(d.icon) ?? propertyTypeIconName(d.type) }))
  ]
}
