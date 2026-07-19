// Grouping + container flattening for the view pipeline. Ports Swift GroupResolver (collection
// scope) + DateBucket. React renders ONE container, so Swift's vault scope + isStructuralAnchor
// machinery are dropped: the setTree is built from node.sets (the real folder walk), so empty Sets
// still appear as disclosure groups, and a CollectionNode and a SetNode container flow through the
// identical structural path. Pure: no fs, no React.

import type { CollectionNode, PageNode, ResolvedGroup, SetNode, ViewRow } from '@shared/types'
import type { DateGranularity, EmptyPlacement, GroupConfig, SubGroupConfig } from '@shared/views'
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

const applySort = (rows: ViewRow[], sorter: Sorter | null): ViewRow[] =>
  sorter ? sorter(rows) : rows

const placeTail = (
  groups: ResolvedGroup[],
  tail: ResolvedGroup,
  placement: EmptyPlacement,
): ResolvedGroup[] => (placement === 'top' ? [tail, ...groups] : [...groups, tail])

/** The one group-by core every resolver shares (property buckets, by-set, sub-group re-bucketing). */
function groupRows<K>(rows: ViewRow[], keyOf: (r: ViewRow) => K): Map<K, ViewRow[]> {
  const m = new Map<K, ViewRow[]>()
  for (const r of rows) {
    const k = keyOf(r)
    const arr = m.get(k)
    if (arr) arr.push(r)
    else m.set(k, [r])
  }
  return m
}

// ---- flatten ----

function buildSetTree(sets: SetNode[] | undefined): SetTreeNode[] {
  return (sets ?? []).map((s) => ({ id: s.id, children: buildSetTree(s.sets) }))
}

/** A node's id plus every descendant's — THE subtree walk (sub-grouping, the filter's location
 *  index). */
export function subtreeIds(node: SetTreeNode): string[] {
  return [node.id, ...node.children.flatMap(subtreeIds)]
}

function toRow(
  page: PageNode,
  parentSetId: string | undefined,
  values: Record<string, PageFrontmatter>,
): ViewRow {
  return {
    id: page.id,
    title: page.title,
    icon: page.icon,
    path: page.path,
    ...(parentSetId !== undefined ? { parentSetId } : {}),
    frontmatter: values[page.id] ?? { id: page.id },
  }
}

/** Walk a container into flat ViewRows (each stamped with its immediate parent Set id, undefined
 *  for a container-root page) plus the setTree for structural grouping. */
export function flattenContainer(
  node: CollectionNode | SetNode,
  valuesByPageId: Record<string, PageFrontmatter>,
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
export function dateBucketKey(
  iso: string,
  granularity: DateGranularity,
  utc = false,
): string | null {
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
  granularity: DateGranularity,
): string | null {
  const v = resolveFieldValue(row, propertyId, schema)
  switch (declaredType(propertyId, schema)) {
    case 'select':
    case 'status':
      return v.kind === 'select' || v.kind === 'status' ? v.value : null
    case 'checkbox':
      return v.kind === 'checkbox' ? (v.value ? 'true' : 'false') : null
    case 'datetime':
      // a bare date-only value (no 'T') buckets by its stored calendar date so it never shifts by
      // timezone; a full datetime is an absolute instant, bucketed display-local.
      return v.kind === 'datetime'
        ? dateBucketKey(v.value, granularity, !v.value.includes('T'))
        : null
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
  ...[...present].filter((k) => !base.includes(k)).sort(),
]

function configuredOrder(def: PropertyDefinition | undefined, present: Set<string>): string[] {
  const schemaOrder = schemaOptionOrder(def)
  if (schemaOrder) return appendTail(schemaOrder, present)
  if (def?.type === 'checkbox') return ['false', 'true']
  return [...present].sort()
}

/** Bucket display order: manual (explicit `order` then sorted tail), configured (schema order),
 *  or reversed (configured, reversed). Mirrors Swift bucketOrder. Exported for the Grouping
 *  pane's Custom list — the one order source for property AND sub-group buckets. */
export function bucketOrder(
  group: Pick<PropertyGroup, 'order_mode' | 'order'>,
  def: PropertyDefinition | undefined,
  present: Set<string>,
): string[] {
  if (group.order_mode === 'manual') return appendTail(group.order ?? [], present)
  const configured = configuredOrder(def, present)
  return group.order_mode === 'reversed' ? [...configured].reverse() : configured
}

function property(
  rows: ViewRow[],
  group: PropertyGroup,
  schema: PropertyDefinition[],
  sorter: Sorter | null,
  collapsed: Set<string>,
  placement: EmptyPlacement,
): ResolvedGroup[] {
  const def = schema.find((d) => d.id === group.property_id)
  const isCheckbox = def?.type === 'checkbox'
  const granularity = group.date_granularity ?? 'month'

  const byBucket = groupRows(
    rows,
    (r) => bucketKey(r, group.property_id, schema, granularity) ?? (isCheckbox ? 'false' : null),
  )
  const noValue = byBucket.get(null) ?? []
  byBucket.delete(null)
  const buckets = byBucket as Map<string, ViewRow[]>

  const groups: ResolvedGroup[] = []
  // bucketOrder yields the FULL schema option order for select/status, so an empty option renders
  // as an empty band — hide_empty_groups is the knob that drops those. Only LIVE schema keys earn
  // an empty band: a stale manual-order key (deleted option, an old date bucket snapshotted by a
  // band drag) must never render a ghost band.
  const liveKeys = new Set(schemaOptionOrder(def) ?? (isCheckbox ? ['false', 'true'] : []))
  for (const key of bucketOrder(group, def, new Set(buckets.keys()))) {
    const items = buckets.get(key) ?? []
    if (items.length === 0 && (group.hide_empty_groups || !liveKeys.has(key))) continue
    groups.push({
      key,
      kind: 'property',
      items: applySort(items, sorter),
      isCollapsed: collapsed.has(key),
    })
  }
  // No "None" band: value-less rows are a flattened, header-less tail placed by the VIEW-level
  // knob — it holds rows, so hide_empty_groups never touches it. The property config's own
  // `empty_placement` stays decode parity, never read.
  if (isCheckbox || noValue.length === 0) return groups
  return placeTail(
    groups,
    {
      key: UNGROUPED,
      kind: 'ungrouped',
      items: applySort(noValue, sorter),
      isCollapsed: collapsed.has(UNGROUPED),
    },
    placement,
  )
}

// ---- structural + flat ----

function structural(
  rows: ViewRow[],
  setTree: SetTreeNode[],
  sorter: Sorter | null,
  collapsed: Set<string>,
  placement: EmptyPlacement,
): ResolvedGroup[] {
  const bySet = groupRows(rows, (r) => r.parentSetId)
  const rootRows = bySet.get(undefined) ?? []
  const build = (node: SetTreeNode): ResolvedGroup => {
    const children = node.children.map(build)
    return {
      key: node.id,
      kind: 'structural-set',
      items: applySort(bySet.get(node.id) ?? [], sorter),
      ...(children.length > 0 ? { children } : {}),
      isCollapsed: collapsed.has(node.id),
    }
  }
  const groups = setTree.map(build)
  if (rootRows.length === 0) return groups
  return placeTail(
    groups,
    {
      key: UNGROUPED,
      kind: 'ungrouped',
      items: applySort(rootRows, sorter),
      isCollapsed: collapsed.has(UNGROUPED),
    },
    placement,
  )
}

/** Cards variant (E-2: cards never indent): each TOP-LEVEL set is ONE flat band — its whole subtree's
 *  pages roll into a single sorted items list with no nested children, so a manual reorder spans the
 *  whole band instead of snapping back within a sub-set. Loose root pages stay the ungrouped tail. */
function structuralFlat(
  rows: ViewRow[],
  setTree: SetTreeNode[],
  sorter: Sorter | null,
  collapsed: Set<string>,
  placement: EmptyPlacement,
): ResolvedGroup[] {
  const byParent = groupRows(rows, (r) => r.parentSetId)
  const rootRows = byParent.get(undefined) ?? []
  const groups: ResolvedGroup[] = setTree.map((node) => ({
    key: node.id,
    kind: 'structural-set',
    items: applySort(
      subtreeIds(node).flatMap((id) => byParent.get(id) ?? []),
      sorter,
    ),
    isCollapsed: collapsed.has(node.id),
  }))
  if (rootRows.length === 0) return groups
  return placeTail(
    groups,
    {
      key: UNGROUPED,
      kind: 'ungrouped',
      items: applySort(rootRows, sorter),
      isCollapsed: collapsed.has(UNGROUPED),
    },
    placement,
  )
}

/** Sort by Location (E-4): resolve structurally-flat, then concatenate every band's items — set
 *  bands in tree order plus the root tail per `placement` — into ONE headerless, force-open
 *  UNGROUPED band. Location order without the bands; the sorter still ranks within. */
function locationFlat(
  rows: ViewRow[],
  setTree: SetTreeNode[],
  sorter: Sorter | null,
  placement: EmptyPlacement,
): ResolvedGroup[] {
  const bands = structuralFlat(rows, setTree, sorter, new Set(), placement)
  return [
    { key: UNGROUPED, kind: 'ungrouped', items: bands.flatMap((g) => g.items), isCollapsed: false },
  ]
}

/** Composite collapse key for a sub-group region — set ids are ULIDs, never containing `/`, so
 *  one set's collapse never bleeds into its twin bucket in another set (D-11a). */
export const subGroupKey = (setId: string, bucket: string): string => `${setId}/${bucket}`

/** Location + property Sub-Group: each TOP-LEVEL set stays a band, its whole subtree's pages
 *  flatten and re-bucket by the property inside it (global bucket order, per-bucket sort); loose
 *  root pages stay one un-bucketed tail. */
function structuralSubGrouped(
  rows: ViewRow[],
  setTree: SetTreeNode[],
  sub: SubGroupConfig,
  schema: PropertyDefinition[],
  sorter: Sorter | null,
  collapsed: Set<string>,
  placement: EmptyPlacement,
): ResolvedGroup[] {
  const def = schema.find((d) => d.id === sub.property_id)
  const granularity = sub.date_granularity ?? 'month'
  const byParent = groupRows(rows, (r) => r.parentSetId)
  const rootRows = byParent.get(undefined) ?? []

  const groups: ResolvedGroup[] = setTree.map((node) => {
    const pages = subtreeIds(node).flatMap((id) => byParent.get(id) ?? [])
    const byBucket = groupRows(pages, (r) => bucketKey(r, sub.property_id, schema, granularity))
    const noValue = byBucket.get(null) ?? []
    byBucket.delete(null)
    const buckets = byBucket as Map<string, ViewRow[]>

    let children = bucketOrder(sub, def, new Set(buckets.keys())).flatMap((b): ResolvedGroup[] => {
      const items = buckets.get(b)
      if (!items) return []
      const key = subGroupKey(node.id, b)
      return [
        {
          key,
          bucket: b,
          kind: 'property',
          items: applySort(items, sorter),
          isCollapsed: collapsed.has(key),
        },
      ]
    })
    if (noValue.length > 0) {
      const key = subGroupKey(node.id, UNGROUPED)
      children = placeTail(
        children,
        {
          key,
          kind: 'ungrouped',
          items: applySort(noValue, sorter),
          isCollapsed: collapsed.has(key),
        },
        placement,
      )
    }
    return {
      key: node.id,
      kind: 'structural-set',
      items: [],
      ...(children.length > 0 ? { children } : {}),
      isCollapsed: collapsed.has(node.id),
    }
  })
  if (rootRows.length === 0) return groups
  return placeTail(
    groups,
    {
      key: UNGROUPED,
      kind: 'ungrouped',
      items: applySort(rootRows, sorter),
      isCollapsed: collapsed.has(UNGROUPED),
    },
    placement,
  )
}

function flat(rows: ViewRow[], sorter: Sorter | null, collapsed: Set<string>): ResolvedGroup[] {
  if (rows.length === 0) return []
  return [
    {
      key: UNGROUPED,
      kind: 'ungrouped',
      items: applySort(rows, sorter),
      isCollapsed: collapsed.has(UNGROUPED),
    },
  ]
}

/** The pipeline's EFFECTIVE grouping mode: a property group whose property is unresolvable or not
 *  a groupable type renders structurally — every consumer (resolveView's location/sub-group gates,
 *  the Grouping pane's chrome) must read this, never the raw `kind`, or they diverge from what the
 *  table actually draws. */
export function groupsStructurally(
  group: GroupConfig | undefined,
  schema: PropertyDefinition[],
): boolean {
  if (group?.kind === 'flat') return false
  if (group?.kind !== 'property') return true
  const t = declaredType(group.property_id, schema)
  return t === undefined || !GROUPABLE.has(t)
}

/** Resolve rows into display groups, sorting within each. A property group falls back to structural
 *  when its property isn't a groupable type (groupsStructurally) — honoring the sub-group like any
 *  structural view. `collapsed` carries the view's collapsed_groups so each group's `isCollapsed`
 *  is populated. */
export function resolveGroups(
  rows: ViewRow[],
  group: GroupConfig | undefined,
  schema: PropertyDefinition[],
  setTree: SetTreeNode[],
  sorter: Sorter | null,
  collapsed: string[] = [],
  placement: EmptyPlacement = 'bottom',
  subGroup?: SubGroupConfig,
  flattenStructural = false,
  locationFlatten = false,
): ResolvedGroup[] {
  const collapsedSet = new Set(collapsed)
  // Sort by Location (E-4) forces structural resolution and flattens every band into one — it wins
  // over a property group (mutually exclusive) and over collapse state (force-open).
  if (locationFlatten) return locationFlat(rows, setTree, sorter, placement)
  if (group?.kind === 'flat') return flat(rows, sorter, collapsedSet)
  if (!groupsStructurally(group, schema))
    return property(rows, group as PropertyGroup, schema, sorter, collapsedSet, placement)
  // Cards flatten each top-level set's subtree into one band (E-2), so their manual order spans it.
  if (flattenStructural) return structuralFlat(rows, setTree, sorter, collapsedSet, placement)
  const t = subGroup ? declaredType(subGroup.property_id, schema) : undefined
  if (subGroup && t !== undefined && GROUPABLE.has(t))
    return structuralSubGrouped(rows, setTree, subGroup, schema, sorter, collapsedSet, placement)
  return structural(rows, setTree, sorter, collapsedSet, placement)
}
