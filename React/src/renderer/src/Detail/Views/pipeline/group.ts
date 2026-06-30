// Grouping + container flattening for the view pipeline. Ports Swift GroupResolver (collection
// scope) + DateBucket. React renders ONE container, so Swift's vault scope + isStructuralAnchor
// machinery are dropped: the setTree is built from node.sets (the real folder walk), so empty Sets
// still appear as disclosure groups, and a CollectionNode and a SetNode container flow through the
// identical structural path. Pure: no fs, no React.

import type { CollectionNode, PageNode, ResolvedGroup, SetNode, ViewRow } from '@shared/types'
import type { DateGranularity, GroupConfig } from '@shared/views'
import type { PageFrontmatter } from '@shared/schemas'
import type { PropertyDefinition } from '@shared/properties'
import { UNGROUPED } from '@shared/types'
import { declaredType, resolveFieldValue } from './value'

/** Only these declared types group; everything else falls back to structural (Global Constraint:
 *  NOT number/multi_select/url/relation/file/last_edited/tier/title). */
const GROUPABLE = new Set<string>(['select', 'status', 'checkbox', 'date', 'datetime'])

type PropertyGroup = Extract<GroupConfig, { kind: 'property' }>
type Sorter = (rows: ViewRow[]) => ViewRow[]

/** The set hierarchy used to build structural disclosure groups — ids only (titles are derived at
 *  render time from the tree). Built from node.sets, so empty Sets are present. */
export interface SetTreeNode {
  id: string
  children: SetTreeNode[]
}

const applySort = (rows: ViewRow[], sorter: Sorter | null): ViewRow[] => (sorter ? sorter(rows) : rows)

// ---- flatten ----

function buildSetTree(sets: SetNode[] | undefined): SetTreeNode[] {
  return (sets ?? []).map((s) => ({ id: s.id, children: buildSetTree(s.sets) }))
}

function toRow(
  page: PageNode,
  parentSetId: string | undefined,
  values: Record<string, PageFrontmatter>
): ViewRow {
  return {
    id: page.id,
    title: page.title,
    icon: page.icon,
    path: page.path,
    ...(parentSetId !== undefined ? { parentSetId } : {}),
    frontmatter: values[page.id] ?? { id: page.id }
  }
}

/** Walk a container into flat ViewRows (each stamped with its immediate parent Set id, undefined
 *  for a container-root page) plus the setTree for structural grouping. */
export function flattenContainer(
  node: CollectionNode | SetNode,
  valuesByPageId: Record<string, PageFrontmatter>
): { rows: ViewRow[]; setTree: SetTreeNode[] } {
  const rows: ViewRow[] = []
  const walk = (container: CollectionNode | SetNode, parentSetId: string | undefined): void => {
    for (const p of container.pages) rows.push(toRow(p, parentSetId, valuesByPageId))
    for (const child of container.sets ?? []) walk(child, child.id)
  }
  walk(node, undefined)
  return { rows, setTree: buildSetTree(node.sets) }
}

// ---- date buckets ----

const pad = (n: number, width: number): string => String(n).padStart(width, '0')

/** ISO 8601 week + week-year from a calendar date's components (already resolved to the chosen zone
 *  by the caller), via UTC arithmetic so adding days never crosses a DST boundary. A week belongs to
 *  the year of its Thursday; weeks start Monday. */
function isoWeek(year: number, month: number, day: number): [year: number, week: number] {
  const d = new Date(Date.UTC(year, month, day))
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7)) // shift to this week's Thursday
  const yearStart = Date.UTC(d.getUTCFullYear(), 0, 1)
  const week = Math.ceil(((d.getTime() - yearStart) / 86400000 + 1) / 7)
  return [d.getUTCFullYear(), week]
}

/** Date → a stable, zero-padded bucket key (lexicographic order == chronological). A datetime is an
 *  absolute instant bucketed display-local (Swift parity); a date-only value (`utc`) is a no-time
 *  calendar date that must NOT shift across timezones, so it buckets by its stored (UTC) date — the
 *  date the user picked, for every viewer. Null for an unparseable date. */
export function dateBucketKey(iso: string, granularity: DateGranularity, utc = false): string | null {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return null
  const year = utc ? d.getUTCFullYear() : d.getFullYear()
  const month = utc ? d.getUTCMonth() : d.getMonth()
  const day = utc ? d.getUTCDate() : d.getDate()
  switch (granularity) {
    case 'year':
      return pad(year, 4)
    case 'month':
      return `${pad(year, 4)}-${pad(month + 1, 2)}`
    case 'day':
      return `${pad(year, 4)}-${pad(month + 1, 2)}-${pad(day, 2)}`
    case 'week': {
      const [wy, w] = isoWeek(year, month, day)
      return `${pad(wy, 4)}-W${pad(w, 2)}`
    }
  }
}

// ---- property buckets ----

/** The grouping key for a row under one property (null = no value → caller routes to the no-value
 *  band, or the checkbox 'false' bucket). Mirrors Swift bucketKey. */
export function bucketKey(
  row: ViewRow,
  propertyId: string,
  schema: PropertyDefinition[],
  granularity: DateGranularity
): string | null {
  const v = resolveFieldValue(row, propertyId)
  switch (declaredType(propertyId, schema)) {
    case 'select':
    case 'status':
      return v.kind === 'select' || v.kind === 'status' ? v.value : null
    case 'checkbox':
      return v.kind === 'checkbox' ? (v.value ? 'true' : 'false') : null
    case 'datetime':
      // a bare date-only value (no 'T') buckets by its stored calendar date so it never shifts by
      // timezone; a full datetime is an absolute instant, bucketed display-local.
      return v.kind === 'datetime' ? dateBucketKey(v.value, granularity, !v.value.includes('T')) : null
    default:
      return null
  }
}

function schemaOptionOrder(def: PropertyDefinition | undefined): string[] | null {
  if (!def) return null
  if (def.select_options) return def.select_options.map((o) => o.value)
  if (def.status_groups) return def.status_groups.flatMap((g) => g.options.map((o) => o.value))
  return null
}

/** `base` followed by any present keys not in it, sorted (present date keys sort chronologically). */
const appendTail = (base: string[], present: Set<string>): string[] => [
  ...base,
  ...[...present].filter((k) => !base.includes(k)).sort()
]

function configuredOrder(def: PropertyDefinition | undefined, present: Set<string>): string[] {
  const schemaOrder = schemaOptionOrder(def)
  if (schemaOrder) return appendTail(schemaOrder, present)
  if (def?.type === 'checkbox') return ['false', 'true']
  return [...present].sort()
}

/** Bucket display order: manual (explicit `order` then sorted tail), configured (schema order),
 *  or reversed (configured, reversed). Mirrors Swift bucketOrder. */
function bucketOrder(group: PropertyGroup, def: PropertyDefinition | undefined, present: Set<string>): string[] {
  if (group.order_mode === 'manual') return appendTail(group.order ?? [], present)
  const configured = configuredOrder(def, present)
  return group.order_mode === 'reversed' ? [...configured].reverse() : configured
}

function property(
  rows: ViewRow[],
  group: PropertyGroup,
  schema: PropertyDefinition[],
  sorter: Sorter | null,
  collapsed: Set<string>
): ResolvedGroup[] {
  const def = schema.find((d) => d.id === group.property_id)
  const isCheckbox = def?.type === 'checkbox'
  const granularity = group.date_granularity ?? 'month'

  const buckets = new Map<string, ViewRow[]>()
  const noValue: ViewRow[] = []
  const push = (key: string, r: ViewRow): void => {
    const arr = buckets.get(key)
    if (arr) arr.push(r)
    else buckets.set(key, [r])
  }
  for (const r of rows) {
    const key = bucketKey(r, group.property_id, schema, granularity)
    if (key !== null) push(key, r)
    else if (isCheckbox) push('false', r)
    else noValue.push(r)
  }

  const groups: ResolvedGroup[] = []
  for (const key of bucketOrder(group, def, new Set(buckets.keys()))) {
    const items = buckets.get(key)
    if (items) {
      groups.push({ key, kind: 'property', items: applySort(items, sorter), isCollapsed: collapsed.has(key) })
    }
  }
  if (!isCheckbox && noValue.length > 0 && !group.hide_empty_groups) {
    const band: ResolvedGroup = {
      key: UNGROUPED,
      kind: 'ungrouped',
      items: applySort(noValue, sorter),
      isCollapsed: collapsed.has(UNGROUPED)
    }
    if (group.empty_placement === 'top') groups.unshift(band)
    else groups.push(band)
  }
  return groups
}

// ---- structural + flat ----

function structural(
  rows: ViewRow[],
  setTree: SetTreeNode[],
  sorter: Sorter | null,
  collapsed: Set<string>
): ResolvedGroup[] {
  const bySet = new Map<string, ViewRow[]>()
  const rootRows: ViewRow[] = []
  for (const r of rows) {
    if (r.parentSetId === undefined) rootRows.push(r)
    else {
      const arr = bySet.get(r.parentSetId)
      if (arr) arr.push(r)
      else bySet.set(r.parentSetId, [r])
    }
  }
  const build = (node: SetTreeNode): ResolvedGroup => {
    const children = node.children.map(build)
    return {
      key: node.id,
      kind: 'structural-set',
      items: applySort(bySet.get(node.id) ?? [], sorter),
      ...(children.length > 0 ? { children } : {}),
      isCollapsed: collapsed.has(node.id)
    }
  }
  const groups = setTree.map(build)
  if (rootRows.length > 0) {
    groups.push({
      key: UNGROUPED,
      kind: 'ungrouped',
      items: applySort(rootRows, sorter),
      isCollapsed: collapsed.has(UNGROUPED)
    })
  }
  return groups
}

function flat(rows: ViewRow[], sorter: Sorter | null, collapsed: Set<string>): ResolvedGroup[] {
  if (rows.length === 0) return []
  return [{ key: UNGROUPED, kind: 'ungrouped', items: applySort(rows, sorter), isCollapsed: collapsed.has(UNGROUPED) }]
}

/** Resolve rows into display groups, sorting within each. A property group falls back to structural
 *  when its property isn't a groupable type. `collapsed` carries the view's collapsed_groups so each
 *  group's `isCollapsed` is populated. */
export function resolveGroups(
  rows: ViewRow[],
  group: GroupConfig | undefined,
  schema: PropertyDefinition[],
  setTree: SetTreeNode[],
  sorter: Sorter | null,
  collapsed: string[] = []
): ResolvedGroup[] {
  const collapsedSet = new Set(collapsed)
  switch (group?.kind) {
    case 'flat':
      return flat(rows, sorter, collapsedSet)
    case 'property': {
      const t = declaredType(group.property_id, schema)
      if (t === undefined || !GROUPABLE.has(t)) return structural(rows, setTree, sorter, collapsedSet)
      return property(rows, group, schema, sorter, collapsedSet)
    }
    default:
      return structural(rows, setTree, sorter, collapsedSet)
  }
}
