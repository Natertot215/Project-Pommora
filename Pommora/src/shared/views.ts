// SavedView — the portable, on-disk view config stored in a Collection/Set sidecar's
// `views[]`. Keys mirror the Swift build's SavedView key-for-key (snake_case on disk) so a
// view round-trips across both builds. `savedView` (zod) is the codec; the exported
// interfaces are the canonical types consumers use.
//
// Two deliberate React-ahead supersets of Swift, documented here (not "ports"):
//   - `sort` is the full array (multi-key, priority = array order). Swift's pipeline reads
//     only the first criterion today; a multi-key array still round-trips its decode.
//   - `filter.rules` may nest a FilterGroup for mixed AND/OR; Swift's rules are flat. A flat
//     filter is byte-identical across builds; a nested one is React-ahead until Swift aligns.
//
// Each enum has ONE source: an `as const` array drives both the TS type (indexed access) and
// the zod codec / runtime membership Set — never re-listed (the AREA_COLORS idiom in types.ts).

import { z } from 'zod'
import { columnStyle, type ColumnStyle } from './columnStyles'
import { type PropertyDefinition, RESERVED_PROPERTY_ID } from './properties'

const VIEW_TYPES = ['table', 'board', 'list', 'cards', 'gallery'] as const
export type ViewType = (typeof VIEW_TYPES)[number]

const CARD_SIZES = ['small', 'medium', 'large'] as const
export type CardSize = (typeof CARD_SIZES)[number]

const COLUMN_ALIGNS = ['left', 'center', 'right'] as const
export type ColumnAlign = (typeof COLUMN_ALIGNS)[number]

const SORT_DIRECTIONS = ['ascending', 'descending'] as const
const MATCH_MODES = ['all', 'any'] as const

const GROUP_ORDER_MODES = ['configured', 'reversed', 'manual'] as const
export type GroupOrderMode = (typeof GROUP_ORDER_MODES)[number]

const DATE_GRANULARITIES = ['day', 'week', 'month', 'year'] as const
export type DateGranularity = (typeof DATE_GRANULARITIES)[number]

const EMPTY_PLACEMENTS = ['top', 'bottom'] as const
export type EmptyPlacement = (typeof EMPTY_PLACEMENTS)[number]

/** One sort criterion; `direction` raw strings match Swift on-disk. */
export interface SortCriterion {
  property_id: string
  direction: (typeof SORT_DIRECTIONS)[number]
}

/** One filter rule. `op` is a snake_case raw string (see FILTER_OPS in pipeline/filter.ts);
 *  `value` is the serialized payload (absent for is_empty / is_not_empty). */
export interface FilterRule {
  property_id: string
  op: string
  value?: string
}

/** A group of filter rules combined by `match` (all = AND, any = OR). RECURSIVE: a child may
 *  itself be a FilterGroup, expressing mixed AND/OR like `(A AND B) OR C` (React-ahead of
 *  Swift's flat rules). */
export interface FilterGroup {
  match: (typeof MATCH_MODES)[number]
  rules: Array<FilterRule | FilterGroup>
}

/** Group-by config — a tagged union on `kind` (matches Swift's GroupConfig). */
export type GroupConfig =
  | { kind: 'structural' }
  | { kind: 'flat' }
  | {
      kind: 'property'
      property_id: string
      order_mode: GroupOrderMode
      order?: string[]
      date_granularity?: DateGranularity
      empty_placement: EmptyPlacement
      hide_empty_groups: boolean
    }

export interface SavedView {
  id: string
  name: string
  icon?: string
  type: ViewType
  property_order: string[]
  hidden_properties: string[]
  column_widths?: Record<string, number>
  column_alignments?: Record<string, ColumnAlign>
  column_styles?: Record<string, ColumnStyle>
  collapsed_groups?: string[]
  card_size?: CardSize
  show_cover?: boolean
  show_banner?: boolean
  hide_page_icons?: boolean
  hide_borders?: boolean
  sort?: SortCriterion[]
  filter?: FilterGroup
  group?: GroupConfig
  /** Manual structural band order — ONE flat set-id array covering every nesting level (ids are
   *  unique across the tree). View-level, not on `group`: the structural GroupConfig decoder
   *  drops extra fields. Unlisted sets trail in fs order; absent = derive from fs `set_order`. */
  group_order?: string[]
}

// ---- zod codec (snake_case on-disk keys; enums reuse the const arrays above) ----

const sortCriterion = z.object({
  property_id: z.string(),
  direction: z.enum(SORT_DIRECTIONS)
})

const filterRule = z.object({
  property_id: z.string(),
  op: z.string(),
  value: z.string().optional()
})

const filterGroup: z.ZodType<FilterGroup> = z.lazy(() =>
  z.object({
    match: z.enum(MATCH_MODES),
    rules: z.array(z.union([filterRule, filterGroup]))
  })
)

const GROUP_ORDER_MODE_SET = new Set<string>(GROUP_ORDER_MODES)
const DATE_GRANULARITY_SET = new Set<string>(DATE_GRANULARITIES)
const EMPTY_PLACEMENT_SET = new Set<string>(EMPTY_PLACEMENTS)

/** Narrow an unknown to one of `allowed`'s members, else undefined — the single guard the
 *  lenient group decode reuses for every enum field. */
function asEnum<T extends string>(value: unknown, allowed: ReadonlySet<string>): T | undefined {
  return typeof value === 'string' && allowed.has(value) ? (value as T) : undefined
}

/** Lenient group decode mirroring Swift GroupConfig.init(from:) — it never throws; an
 *  unknown or malformed shape degrades to `structural` (a throw would poison the whole
 *  sidecar decode). A bare legacy `{property_id}` (no `kind`) is read as a property group. */
export function decodeGroupConfig(raw: unknown): GroupConfig {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return { kind: 'structural' }
  const obj = raw as Record<string, unknown>
  const kind = typeof obj.kind === 'string' ? obj.kind : undefined

  const asProperty = (): GroupConfig => {
    const order = Array.isArray(obj.order)
      ? (obj.order.filter((x) => typeof x === 'string') as string[])
      : undefined
    const granularity = asEnum<DateGranularity>(obj.date_granularity, DATE_GRANULARITY_SET)
    return {
      kind: 'property',
      property_id: typeof obj.property_id === 'string' ? obj.property_id : '',
      order_mode: asEnum<GroupOrderMode>(obj.order_mode, GROUP_ORDER_MODE_SET) ?? 'configured',
      ...(order !== undefined ? { order } : {}),
      ...(granularity !== undefined ? { date_granularity: granularity } : {}),
      empty_placement: asEnum<EmptyPlacement>(obj.empty_placement, EMPTY_PLACEMENT_SET) ?? 'bottom',
      hide_empty_groups: typeof obj.hide_empty_groups === 'boolean' ? obj.hide_empty_groups : false
    }
  }

  switch (kind) {
    case 'structural':
      return { kind: 'structural' }
    case 'flat':
      return { kind: 'flat' }
    case 'property':
      return asProperty()
    case undefined:
      return 'property_id' in obj ? asProperty() : { kind: 'structural' }
    default:
      return { kind: 'structural' }
  }
}

/** The sidecar `views[]` element. Loose ⇒ foreign keys survive a rewrite (cloud-sync /
 *  agent-legibility); scalar fields mirror Swift's defensive `try? … ?? default` decode. */
export const savedView = z.looseObject({
  id: z.string().catch(''),
  name: z.string().catch('Table'),
  icon: z.string().optional(),
  type: z.enum(VIEW_TYPES).catch('table'),
  property_order: z.array(z.string()).catch([]),
  hidden_properties: z.array(z.string()).catch([]),
  column_widths: z.record(z.string(), z.number()).optional(),
  column_alignments: z.record(z.string(), z.enum(COLUMN_ALIGNS)).optional(),
  column_styles: z.record(z.string(), columnStyle).catch({}).optional(),
  collapsed_groups: z.array(z.string()).optional(),
  card_size: z.enum(CARD_SIZES).optional(),
  show_cover: z.boolean().optional(),
  show_banner: z.boolean().optional(),
  hide_page_icons: z.boolean().optional(),
  hide_borders: z.boolean().optional(),
  sort: z.array(sortCriterion).optional(),
  filter: filterGroup.optional(),
  group: z.unknown().transform(decodeGroupConfig).optional(),
  // Element-filtering, never whole-array catch: one bad entry drops alone, the good ids survive.
  group_order: z
    .array(z.unknown())
    .catch([])
    .transform((a) => a.filter((x): x is string => typeof x === 'string'))
    .optional()
})

/** Shared on-disk prefix for view ids (`view_<ulid>`); single-sourced so the sentinel and the
 *  minted id can't drift. */
export const VIEW_ID_PREFIX = 'view_'

/** Sentinel id for a freshly-minted default view. `shared/` can't import `main/ids`, so main swaps
 *  this for a real `view_<ulid>` on first save (see crud/views). */
export const DEFAULT_VIEW_ID = `${VIEW_ID_PREFIX}default`

/** Mint a default Table view for a container with no saved views: Title-first, all user props
 *  visible, structural grouping, no sort, no `_modified_at` column. Carries the sentinel id. */
export function mintDefaultView(schema: PropertyDefinition[]): SavedView {
  return {
    id: DEFAULT_VIEW_ID,
    name: 'Table',
    icon: 'tablecells',
    type: 'table',
    property_order: [RESERVED_PROPERTY_ID.title, ...schema.map((d) => d.id)],
    hidden_properties: [],
    group: { kind: 'structural' }
  }
}
