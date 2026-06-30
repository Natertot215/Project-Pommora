// Type-aware view filter. Ports Swift FilterEvaluator's per-rule, per-type operator matrix (NOT the
// narrower Part-3 picker) and EXTENDS it with nested groups (divergence #2): Swift's rules are flat;
// here a rule child may itself be a FilterGroup, expressing mixed AND/OR like `(A AND B) OR C`. `op`
// raw strings are snake_case (on-disk parity). An unknown op, a property absent from the schema, or
// an op outside a type's matrix is a NO-OP PASS — a filter never excludes on what it can't apply.
// Pure: no fs, no React.

import type { FilterGroup, FilterRule } from '@shared/views'
import type { ViewRow } from '@shared/types'
import { type PropertyDefinition, type PropertyType, RESERVED_PROPERTY_ID } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { declaredType, modifiedStampString, resolveFieldValue } from './value'

/** Operator raw strings — snake_case = the on-disk `op` values (parity with Swift FilterOperator). */
export const FILTER_OPS = {
  is: 'is',
  isNot: 'is_not',
  contains: 'contains',
  doesNotContain: 'does_not_contain',
  isEmpty: 'is_empty',
  isNotEmpty: 'is_not_empty',
  greaterThan: 'greater_than',
  lessThan: 'less_than',
  onOrAfter: 'on_or_after',
  onOrBefore: 'on_or_before'
} as const

const FILTER_OP_SET = new Set<string>(Object.values(FILTER_OPS))

type Op = string
type Expected = string | undefined

/** Filter rows by a (possibly nested) FilterGroup. undefined ⇒ no filtering. */
export function applyFilter(
  rows: ViewRow[],
  filter: FilterGroup | undefined,
  schema: PropertyDefinition[]
): ViewRow[] {
  if (!filter) return rows
  return rows.filter((row) => matchesGroup(row, filter, schema))
}

/** A child is a nested group iff it carries `rules`; otherwise it's a leaf FilterRule. */
function isGroup(node: FilterRule | FilterGroup): node is FilterGroup {
  return 'rules' in node
}

function matchesGroup(row: ViewRow, group: FilterGroup, schema: PropertyDefinition[]): boolean {
  if (group.rules.length === 0) return true // empty filter = identity
  const results = group.rules.map((node) =>
    isGroup(node) ? matchesGroup(row, node, schema) : evaluateRule(row, node, schema)
  )
  return group.match === 'all' ? results.every(Boolean) : results.some(Boolean)
}

function evaluateRule(row: ViewRow, rule: FilterRule, schema: PropertyDefinition[]): boolean {
  if (!FILTER_OP_SET.has(rule.op)) return true // unknown op → no-op pass

  // "Last edited" resolves to the modified∥created stamp (never a stored property) → date matrix.
  if (rule.property_id === RESERVED_PROPERTY_ID.modifiedAt) {
    const s = modifiedStampString(row)
    return evaluateDate(s ? { kind: 'datetime', value: s } : { kind: 'null' }, rule.op, rule.value)
  }

  const t = declaredType(rule.property_id, schema)
  if (t === undefined) return true // property absent from schema → no-op pass
  return evaluateByType(resolveFieldValue(row, rule.property_id), rule.op, rule.value, t)
}

function evaluateByType(v: PropertyValue, op: Op, expected: Expected, t: PropertyType | 'title' | 'tier'): boolean {
  switch (t) {
    case 'tier':
      return evaluateList(v.kind === 'context' ? v.value : [], op, expected)
    case 'number':
      return evaluateNumber(v, op, expected)
    case 'datetime':
    case 'last_edited_time':
      return evaluateDate(v, op, expected)
    case 'checkbox':
      return evaluateCheckbox(v, op, expected)
    case 'select':
    case 'status':
    case 'url':
      return evaluateText(v, op, expected)
    case 'multi_select':
      return evaluateMulti(v, op, expected)
    case 'context':
    case 'file':
      return evaluatePresence(v, op)
    default: // 'title' (and any unmodeled type) → no-op pass
      return true
  }
}

// ---- operand parsers ----

function parseNum(s: Expected): number | null {
  if (s == null || s.trim() === '') return null
  const n = Number(s)
  return Number.isNaN(n) ? null : n
}

function parseDateMs(s: Expected): number | null {
  if (s == null) return null
  const t = Date.parse(s)
  return Number.isNaN(t) ? null : t
}

function parseBool(s: Expected): boolean | null {
  switch (s?.toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
      return true
    case 'false':
    case '0':
    case 'no':
      return false
    default:
      return null
  }
}

function textValue(v: PropertyValue): string | null {
  switch (v.kind) {
    case 'select':
    case 'status':
    case 'url':
      return v.value
    default:
      return null
  }
}

// ---- per-type evaluators (mirror Swift FilterEvaluator; unmatched op → no-op pass) ----

function evaluateNumber(v: PropertyValue, op: Op, expected: Expected): boolean {
  const n = v.kind === 'number' ? v.value : null
  switch (op) {
    case FILTER_OPS.isEmpty:
      return n === null
    case FILTER_OPS.isNotEmpty:
      return n !== null
    case FILTER_OPS.is: {
      const e = parseNum(expected)
      return n === null || e === null ? true : n === e
    }
    case FILTER_OPS.isNot: {
      const e = parseNum(expected)
      return n === null || e === null ? true : n !== e
    }
    case FILTER_OPS.greaterThan: {
      const e = parseNum(expected)
      return n === null || e === null ? true : n > e
    }
    case FILTER_OPS.lessThan: {
      const e = parseNum(expected)
      return n === null || e === null ? true : n < e
    }
    default:
      return true
  }
}

function evaluateDate(v: PropertyValue, op: Op, expected: Expected): boolean {
  const d = v.kind === 'datetime' ? parseDateMs(v.value) : null
  switch (op) {
    case FILTER_OPS.isEmpty:
      return d === null
    case FILTER_OPS.isNotEmpty:
      return d !== null
    case FILTER_OPS.onOrAfter: {
      const e = parseDateMs(expected)
      return d === null || e === null ? true : d >= e
    }
    case FILTER_OPS.onOrBefore: {
      const e = parseDateMs(expected)
      return d === null || e === null ? true : d <= e
    }
    default:
      return true
  }
}

function evaluateCheckbox(v: PropertyValue, op: Op, expected: Expected): boolean {
  const present = v.kind === 'checkbox'
  const b = v.kind === 'checkbox' ? v.value : false
  switch (op) {
    case FILTER_OPS.isEmpty:
      return !present
    case FILTER_OPS.is: {
      const e = parseBool(expected)
      return e === null ? true : b === e
    }
    case FILTER_OPS.isNot: {
      const e = parseBool(expected)
      return e === null ? true : b !== e
    }
    default:
      return true
  }
}

function evaluateText(v: PropertyValue, op: Op, expected: Expected): boolean {
  const s = textValue(v)
  switch (op) {
    case FILTER_OPS.isEmpty:
      return s === null || s === ''
    case FILTER_OPS.isNotEmpty:
      return !(s === null || s === '')
    case FILTER_OPS.is:
      return s === null || expected == null ? true : s === expected
    case FILTER_OPS.isNot:
      return expected == null ? true : s !== expected
    case FILTER_OPS.contains:
      return s === null || expected == null ? true : s.toLowerCase().includes(expected.toLowerCase())
    case FILTER_OPS.doesNotContain:
      return expected == null ? true : !(s?.toLowerCase().includes(expected.toLowerCase()) ?? false)
    default:
      return true
  }
}

function evaluateMulti(v: PropertyValue, op: Op, expected: Expected): boolean {
  const xs = v.kind === 'multiSelect' ? v.value : []
  switch (op) {
    case FILTER_OPS.isEmpty:
      return xs.length === 0
    case FILTER_OPS.isNotEmpty:
      return xs.length > 0
    case FILTER_OPS.is:
    case FILTER_OPS.contains:
      return expected == null ? true : xs.includes(expected)
    case FILTER_OPS.isNot:
    case FILTER_OPS.doesNotContain:
      return expected == null ? true : !xs.includes(expected)
    default:
      return true
  }
}

/** Tier / id-list membership + presence (Swift evaluateList). Note: is/contains with no operand →
 *  false (cannot match), mirroring Swift — distinct from multi-select's pass. */
function evaluateList(ids: string[], op: Op, expected: Expected): boolean {
  switch (op) {
    case FILTER_OPS.isEmpty:
      return ids.length === 0
    case FILTER_OPS.isNotEmpty:
      return ids.length > 0
    case FILTER_OPS.is:
    case FILTER_OPS.contains:
      return expected == null ? false : ids.includes(expected)
    case FILTER_OPS.isNot:
    case FILTER_OPS.doesNotContain:
      return expected == null ? true : !ids.includes(expected)
    default:
      return true
  }
}

/** User relation / file: presence only (is/contains/etc. are no-op passes — Swift evaluatePresence). */
function evaluatePresence(v: PropertyValue, op: Op): boolean {
  const empty =
    v.kind === 'context' || v.kind === 'file' ? v.value.length === 0 : v.kind === 'null' ? true : false
  switch (op) {
    case FILTER_OPS.isEmpty:
      return empty
    case FILTER_OPS.isNotEmpty:
      return !empty
    default:
      return true
  }
}
