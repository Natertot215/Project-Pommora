// Pure view pipeline: filter → group → sort. No React, no DOM, no fs.
// Given a vault's rows + a ViewSpec, returns ResolvedGroup[] deterministically.
// Side-effect-free: inputs are never mutated (filter/sort operate on copies).

import type {
  FilterRule,
  ResolvedGroup,
  SortSpec,
  ViewField,
  ViewRow,
  ViewSpec
} from '@shared/types'

const ALL_GROUP_KEY = '__all__'
const EMPTY_GROUP_KEY = ''

/**
 * Resolve an addressable field on a row. `title` | `icon` | `path` read the
 * intrinsic field; any other field name reads `frontmatter[field]`.
 */
function fieldValue(row: ViewRow, field: ViewField): unknown {
  switch (field) {
    case 'title':
      return row.title
    case 'icon':
      return row.icon
    case 'path':
      return row.path
    default:
      return row.frontmatter?.[field]
  }
}

/**
 * Flatten a field value to a comparable string. Arrays join with ', ';
 * null/undefined become ''. The single source of value→text used by filter,
 * group, and sort so all three agree on what a cell "says".
 */
function valueToString(v: unknown): string {
  if (v === null || v === undefined) return ''
  if (Array.isArray(v)) return v.map(valueToString).join(', ')
  if (typeof v === 'string') return v
  if (typeof v === 'number' || typeof v === 'boolean') return String(v)
  return String(v)
}

function rowText(row: ViewRow, field: ViewField): string {
  return valueToString(fieldValue(row, field))
}

// ---------- filter ----------

function ruleMatches(row: ViewRow, rule: FilterRule): boolean {
  const cell = rowText(row, rule.field).toLowerCase()
  const target = (rule.value ?? '').toLowerCase()
  switch (rule.operator) {
    case 'equals':
      return cell === target
    case 'notEquals':
      return cell !== target
    case 'contains':
      return cell.includes(target)
    case 'isEmpty':
      return cell.length === 0
    case 'isNotEmpty':
      return cell.length > 0
  }
}

/** All rules must pass (AND). Returns a new array; input untouched. */
function applyFilters(rows: ViewRow[], filters: FilterRule[] | undefined): ViewRow[] {
  if (!filters || filters.length === 0) return rows.slice()
  return rows.filter((row) => filters.every((rule) => ruleMatches(row, rule)))
}

// ---------- sort ----------

/**
 * Stable, locale-aware, numeric-friendly comparator on the grouped/sorted field.
 * Empty values sort last (regardless of direction) so blank cells never lead.
 */
function compareRows(a: ViewRow, b: ViewRow, sort: SortSpec): number {
  const av = rowText(a, sort.field)
  const bv = rowText(b, sort.field)
  const aEmpty = av.length === 0
  const bEmpty = bv.length === 0
  if (aEmpty || bEmpty) {
    if (aEmpty && bEmpty) return 0
    return aEmpty ? 1 : -1 // empties last, both directions
  }
  const cmp = av.localeCompare(bv, undefined, { numeric: true, sensitivity: 'base' })
  return sort.direction === 'desc' ? -cmp : cmp
}

/** Returns a new sorted array (Array.prototype.sort is stable in modern engines). */
function applySort(rows: ViewRow[], sort: SortSpec | undefined): ViewRow[] {
  if (!sort) return rows.slice()
  return rows.slice().sort((a, b) => compareRows(a, b, sort))
}

// ---------- group ----------

function groupLabel(key: string): string {
  if (key === ALL_GROUP_KEY) return 'All'
  if (key === EMPTY_GROUP_KEY) return 'Empty'
  return key
}

/**
 * Partition rows into groups, preserving first-seen group order. With no
 * `groupBy`, all rows fall into one implicit `__all__` group.
 */
function groupRows(rows: ViewRow[], groupBy: ViewField | undefined): ResolvedGroup[] {
  if (!groupBy) {
    return [{ key: ALL_GROUP_KEY, label: groupLabel(ALL_GROUP_KEY), rows }]
  }
  const order: string[] = []
  const buckets = new Map<string, ViewRow[]>()
  for (const row of rows) {
    const key = rowText(row, groupBy)
    let bucket = buckets.get(key)
    if (!bucket) {
      bucket = []
      buckets.set(key, bucket)
      order.push(key)
    }
    bucket.push(row)
  }
  return order.map((key) => ({ key, label: groupLabel(key), rows: buckets.get(key)! }))
}

/**
 * Run the full pipeline: filter (AND of rules) → group (by field) → sort (within
 * each group). Pure: the input `rows` array and its elements are never mutated.
 */
export function resolveView(rows: ViewRow[], spec: ViewSpec = {}): ResolvedGroup[] {
  const filtered = applyFilters(rows, spec.filters)
  const groups = groupRows(filtered, spec.groupBy)
  return groups.map((g) => ({ ...g, rows: applySort(g.rows, spec.sort) }))
}
