// SavedView — the portable, on-disk view config stored in a Collection/Set sidecar's
// `views[]`. Keys mirror the Swift build's SavedView key-for-key (snake_case on disk) so a
// view round-trips across both builds. `savedView` (zod) is the codec; the exported
// interfaces are the canonical types consumers use.
//
// Deliberate React-ahead supersets of Swift, documented here (not "ports"):
//   - `sort` is the full array (multi-key, priority = array order). Swift's pipeline reads
//     only the first criterion today; a multi-key array still round-trips its decode.
//   - `filter.rules` may nest a FilterGroup for mixed AND/OR; Swift's rules are flat. A flat
//     filter is byte-identical across builds; a nested one is React-ahead until Swift aligns.
//   - The gallery keys (`card_banner`, `hide_location`, `wrap_titles`, `set_cards`, and the
//     numeric `card_size` scale factor) are React-ahead; Swift's small/medium/large
//     `card_size` still decodes, mapped to its factor.
//
// Each enum has ONE source: an `as const` array drives both the TS type (indexed access) and
// the zod codec / runtime membership Set — never re-listed (the AREA_COLORS idiom in types.ts).

import { z } from 'zod'
import { columnStyle, type ColumnStyle } from './columnStyles'
import { type PropertyDefinition, RESERVED_PROPERTY_ID } from './properties'

const VIEW_TYPES = ['table', 'cards', 'list', 'gallery', 'calendar', 'timeline'] as const
export type ViewType = (typeof VIEW_TYPES)[number]

const VIEW_FORMATS = ['standard', 'compact'] as const
export type ViewFormat = (typeof VIEW_FORMATS)[number]

// Legacy card_size enum — decode-only; a stored name maps onto the slider's scale factor.
const CARD_SIZES = ['small', 'medium', 'large'] as const
const LEGACY_CARD_SIZE: Record<(typeof CARD_SIZES)[number], number> = {
  small: 0.75,
  medium: 1,
  large: 1.25,
}

const CARD_BANNERS = ['cover', 'preview', 'none'] as const
export type CardBanner = (typeof CARD_BANNERS)[number]

const COLUMN_ALIGNS = ['left', 'center', 'right'] as const
export type ColumnAlign = (typeof COLUMN_ALIGNS)[number]

const SORT_DIRECTIONS = ['ascending', 'descending'] as const
const MATCH_MODES = ['all', 'any', 'none'] as const
export type MatchMode = (typeof MATCH_MODES)[number]

const GROUP_ORDER_MODES = ['configured', 'reversed', 'manual'] as const
export type GroupOrderMode = (typeof GROUP_ORDER_MODES)[number]

const DATE_GRANULARITIES = ['day', 'week', 'month', 'year'] as const
export type DateGranularity = (typeof DATE_GRANULARITIES)[number]

const EMPTY_PLACEMENTS = ['top', 'bottom'] as const
export type EmptyPlacement = (typeof EMPTY_PLACEMENTS)[number]

const STRUCTURAL_ORDER_MODES = ['custom', 'location'] as const
export type StructuralOrderMode = (typeof STRUCTURAL_ORDER_MODES)[number]

const DATE_SEPARATORS = ['dash', 'slash'] as const
export type DateSeparator = (typeof DATE_SEPARATORS)[number]

/** Location-mode sub-grouping — a property bucketing INSIDE each top-level set band. View-level
 *  (like group_order): the one `group` slot is replaced on a Group By switch, so anything that
 *  must survive the round trip can't live on the config object. */
export interface SubGroupConfig {
  property_id: string
  order_mode: GroupOrderMode
  order?: string[]
  date_granularity?: DateGranularity
}

/** One sort criterion; `direction` raw strings match Swift on-disk. `order` is the Custom option
 *  ranking for select/status — present means rank by this sequence (unknowns last), direction moot. */
export interface SortCriterion {
  property_id: string
  direction: (typeof SORT_DIRECTIONS)[number]
  order?: string[]
}

/** One filter rule. `op` is a snake_case raw string (see FILTER_OPS in pipeline/filter.ts);
 *  `value` is the single serialized operand; `values` is the multi-operand set (chip ops:
 *  contains_all / contains_any / any-of Is / none-of Isn't). Both absent for presence ops. */
export interface FilterRule {
  property_id: string
  op: string
  value?: string
  values?: string[]
}

/** A group of filter rules combined by `match` (all = AND, any = OR). RECURSIVE: a child may
 *  itself be a FilterGroup, expressing mixed AND/OR like `(A AND B) OR C` (React-ahead of
 *  Swift's flat rules). `match: 'none'` is the pane's disable state, root-only by authorship —
 *  the pipeline skips filtering when the ROOT is none (rules persist untouched, wrapped as the
 *  root's single child group); a nested none evaluates as a pass. */
export interface FilterGroup {
  match: MatchMode
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
  /** Gallery card scale — the Layout slider's factor (0.5–1.5). Absent = 1. */
  card_size?: number
  /** Gallery card image source — the page banner (`cover`), the captured thumbnail (`preview`),
   *  or imageless compact cards (`none`). Absent = cover. */
  card_banner?: CardBanner
  /** Gallery: hide the card's Set / sub-Set location footing. */
  hide_location?: boolean
  /** Gallery: card titles may wrap; off = single-line overflow-scroll. */
  wrap_titles?: boolean
  /** Gallery: the leading Set Cards row. Absent = shown. */
  set_cards?: boolean
  show_banner?: boolean
  hide_page_icons?: boolean
  /** Table Layout "Column Icons" toggle — hide the type-icon in each column header (the title column
   *  never carries one). Render wiring is a follow-up; the flag persists today. Other view types
   *  surface this same flag under a different label (see Handoff: Column Icons ↔ Label Icons). */
  hide_column_icons?: boolean
  hide_borders?: boolean
  sort?: SortCriterion[]
  filter?: FilterGroup
  group?: GroupConfig
  /** Table density style — persisted per-view; drives a class on the table root (Compact CSS is a
   *  later cycle, so this is inert on read today). */
  format?: ViewFormat
  /** Manual structural band order — ONE flat set-id array covering every nesting level (ids are
   *  unique across the tree). View-level, not on `group`: the structural GroupConfig decoder
   *  drops extra fields. Unlisted sets trail in fs order; absent = derive from fs `set_order`. */
  group_order?: string[]
  /** Structural band-order source — 'location' mirrors the filesystem (drags write fs;
   *  group_order is preserved-but-ignored); absent/'custom' = the view-owned group_order. */
  structural_order_mode?: StructuralOrderMode
  /** Location-mode sub-grouping config — survives Group By switches by living view-level. */
  sub_group?: SubGroupConfig
  /** Global ungrouped-region placement — one view-level knob for every ungrouped tail; the
   *  property config's empty_placement stays decode parity. Absent = bottom. */
  ungrouped_placement?: EmptyPlacement
  /** Date group-heading separator under numeric formats. Absent = dash. */
  date_separator?: DateSeparator
}

// ---- zod codec (snake_case on-disk keys; enums reuse the const arrays above) ----

const sortCriterion = z.object({
  property_id: z.string(),
  direction: z.enum(SORT_DIRECTIONS),
  order: z.array(z.string()).optional(),
})

const filterRule = z.object({
  property_id: z.string(),
  op: z.string(),
  value: z.string().optional(),
  values: z.array(z.string()).optional(),
})

const filterGroup: z.ZodType<FilterGroup> = z.lazy(() =>
  z.object({
    match: z.enum(MATCH_MODES),
    rules: z.array(z.union([filterRule, filterGroup])),
  }),
)

const GROUP_ORDER_MODE_SET = new Set<string>(GROUP_ORDER_MODES)
const DATE_GRANULARITY_SET = new Set<string>(DATE_GRANULARITIES)
const EMPTY_PLACEMENT_SET = new Set<string>(EMPTY_PLACEMENTS)

/** Narrow an unknown to one of `allowed`'s members, else undefined — the single guard the
 *  lenient group decode reuses for every enum field. */
function asEnum<T extends string>(value: unknown, allowed: ReadonlySet<string>): T | undefined {
  return typeof value === 'string' && allowed.has(value) ? (value as T) : undefined
}

/** Lenient sub_group decode (the decodeGroupConfig discipline): malformed → undefined, never throws. */
export function decodeSubGroup(raw: unknown): SubGroupConfig | undefined {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return undefined
  const s = raw as Record<string, unknown>
  if (typeof s.property_id !== 'string' || s.property_id === '') return undefined
  const order = Array.isArray(s.order)
    ? (s.order.filter((x) => typeof x === 'string') as string[])
    : undefined
  const granularity = asEnum<DateGranularity>(s.date_granularity, DATE_GRANULARITY_SET)
  return {
    property_id: s.property_id,
    order_mode: asEnum<GroupOrderMode>(s.order_mode, GROUP_ORDER_MODE_SET) ?? 'configured',
    ...(order !== undefined ? { order } : {}),
    ...(granularity !== undefined ? { date_granularity: granularity } : {}),
  }
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
      hide_empty_groups: typeof obj.hide_empty_groups === 'boolean' ? obj.hide_empty_groups : false,
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
  card_size: z
    .union([z.number(), z.enum(CARD_SIZES).transform((v) => LEGACY_CARD_SIZE[v])])
    .optional()
    .catch(undefined),
  card_banner: z.enum(CARD_BANNERS).optional().catch(undefined),
  hide_location: z.boolean().optional(),
  wrap_titles: z.boolean().optional(),
  set_cards: z.boolean().optional(),
  show_banner: z.boolean().optional(),
  hide_page_icons: z.boolean().optional(),
  hide_column_icons: z.boolean().optional(),
  hide_borders: z.boolean().optional(),
  sort: z.array(sortCriterion).optional(),
  filter: filterGroup.optional(),
  group: z.unknown().transform(decodeGroupConfig).optional(),
  format: z.enum(VIEW_FORMATS).optional().catch(undefined),
  // Element-filtering, never whole-array catch: one bad entry drops alone, the good ids survive.
  group_order: z
    .array(z.unknown())
    .catch([])
    .transform((a) => a.filter((x): x is string => typeof x === 'string'))
    .optional(),
  structural_order_mode: z.enum(STRUCTURAL_ORDER_MODES).optional().catch(undefined),
  sub_group: z.unknown().transform(decodeSubGroup).optional(),
  ungrouped_placement: z.enum(EMPTY_PLACEMENTS).optional().catch(undefined),
  date_separator: z.enum(DATE_SEPARATORS).optional().catch(undefined),
})

/** Shared on-disk prefix for view ids (`view_<ulid>`); single-sourced so the sentinel and the
 *  minted id can't drift. */
export const VIEW_ID_PREFIX = 'view_'

/** Sentinel id for a freshly-minted default view. `shared/` can't import `main/ids`, so main swaps
 *  this for a real `view_<ulid>` on first save (see crud/views). */
export const DEFAULT_VIEW_ID = `${VIEW_ID_PREFIX}default`

/** The fields every minted view shares — sentinel id, table type, structural grouping, table glyph.
 *  Legacy `'tablecells'` sidecars still resolve via each consumer's `iconNameOr(view.icon, 'table')`. */
const mintBase = (name: string) => ({
  id: DEFAULT_VIEW_ID,
  name,
  icon: 'table',
  type: 'table' as const,
  group: { kind: 'structural' as const },
})

/** Title-only visibility for a `+`-minted view of a given type — the per-ViewType seam (only Table
 *  ships; a future type adds its own case). Table hides every schema id and all three tiers, so the
 *  guaranteed Title is the sole column (verified through resolveColumns). */
function mintVisibility(
  type: ViewType,
  schema: PropertyDefinition[],
): Pick<SavedView, 'property_order' | 'hidden_properties'> {
  switch (type) {
    default:
      return {
        property_order: [RESERVED_PROPERTY_ID.title],
        hidden_properties: [
          ...schema.map((d) => d.id),
          RESERVED_PROPERTY_ID.tier1,
          RESERVED_PROPERTY_ID.tier2,
          RESERVED_PROPERTY_ID.tier3,
        ],
      }
  }
}

/** Mint the seeded/entry-minted default Table view (all user props visible, no sort, no
 *  `_modified_at` column). Carries the sentinel id until first save. */
export function mintDefaultView(schema: PropertyDefinition[]): SavedView {
  return {
    ...mintBase('Table'),
    property_order: [RESERVED_PROPERTY_ID.title, ...schema.map((d) => d.id)],
    hidden_properties: [],
  }
}

/** Mint a `+`-created view: title-only (every assigned property + the default-on tiers hidden), routed
 *  through the per-type visibility seam. Carries the sentinel id until first save. */
export function mintNewView(name: string, schema: PropertyDefinition[]): SavedView {
  return { ...mintBase(name), ...mintVisibility('table', schema) }
}
