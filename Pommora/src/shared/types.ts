// Single source of truth for the cross-process contract.
// Imported by main, preload, and renderer — NO fs, NO React here.

import type { PropertyDefinition } from './properties'
import type { PageFrontmatter } from './schemas'
import type { SavedView } from './views'

export type NodeKind =
  | 'saved'
  | 'area'
  | 'topic'
  | 'project'
  | 'collection'
  | 'set'
  | 'page'

// Contexts tier-1 (Area) color palette — 10 cases, written once as the single source for
// both the type and the runtime membership check (the reader + the areaSidecar schema both
// derive from this). KEEP DISTINCT from the Settings accent palette (ACCENT_COLORS below).
export const AREA_COLORS = [
  'gray',
  'brown',
  'orange',
  'yellow',
  'green',
  'blue',
  'purple',
  'pink',
  'red',
  'accent'
] as const
export type AreaColor = (typeof AREA_COLORS)[number]

// Settings accent palette — the spectrum solids usable as the app accent, plus
// `system` (follow the OS accent). Names mirror the renderer's vars.color.solid
// keys (color.css.ts); greyDefault is excluded (it's the chip "Default" neutral,
// not an accent). resolveAccent (renderer) maps each name to its hex.
export const ACCENT_COLORS = [
  'red',
  'orange',
  'yellow',
  'green',
  'lightBlue',
  'cyan',
  'blue',
  'purple',
  'lavender',
  'grey'
] as const
export type AccentColor = (typeof ACCENT_COLORS)[number]

/** The `accent` value in .nexus/settings.json: a spectrum solid, or follow-the-OS. */
export type AccentSetting = AccentColor | 'system'

/**
 * Default accent when settings.json omits or has an invalid `accent`. A concrete
 * spectrum color (never `system`) so it always resolves to a hex and can seed the
 * static `--accent`. Users opt into `system` explicitly.
 */
export const DEFAULT_ACCENT: AccentColor = 'lavender'

/** Connection color — the inline [[Title]] connection link color. `'accent'` (the default) tracks
 *  the app accent live via `--connection: var(--accent)`; a spectrum solid pins it to that color. */
export type ConnectionColorSetting = AccentColor | 'accent'
export const DEFAULT_CONNECTION_COLOR: ConnectionColorSetting = 'accent'

/** The `time_format` value in .nexus/settings.json — the nexus-wide clock for the datetime
 *  picker (twelveHour = AM/PM segments, the default; twentyFourHour = flat HH:MM). */
export type TimeFormatSetting = 'twelveHour' | 'twentyFourHour'
export const DEFAULT_TIME_FORMAT: TimeFormatSetting = 'twelveHour'

/** Entity kinds that carry a nexus-wide default icon; an entity's own `icon` still overrides it. */
export const ENTITY_ICON_KINDS = ['collection', 'set', 'area', 'topic', 'project', 'page'] as const
export type EntityIconKind = (typeof ENTITY_ICON_KINDS)[number]

/** Where a container's child folders sit relative to its loose pages in the sidebar. `top` (default)
 *  keeps folders above pages; `bottom` drops them below. A full folder↔page interleave is the eventual
 *  model — this flag is the interim: folders stay one contiguous block, just relocatable. */
export type FolderPlacement = 'top' | 'bottom'

/** Which surface the sidebar content column renders. Homepage is a selection, not a mode. */
export type SidebarMode = 'collections' | 'contexts' | 'agenda'

/** A read-only agenda entity for the sidebar list (main → renderer). Dates are ISO strings or absent. */
export interface AgendaEntry {
  id: string
  title: string
  kind: 'task' | 'event'
  icon?: string
  dueAt?: string
  startAt?: string
  endAt?: string
}

/** The `agenda:list` IPC envelope — tasks + events, or an error. */
export type AgendaListResult =
  | { ok: true; tasks: AgendaEntry[]; events: AgendaEntry[] }
  | { ok: false; error: string }

/** Nexus-wide interface personalization — the `personalization` object in `.nexus/settings.json`
 *  (canonical, synced). Every field optional; absent = the built-in default. One schema behind one
 *  apply-map + one setter — a new toggle is a field here plus an apply-map row. Icon names are bare
 *  strings (the renderer resolves them to symbols) so this stays free of renderer types. */
export interface Personalization {
  accent?: AccentSetting
  connectionColor?: ConnectionColorSetting
  hideChevrons?: boolean
  outlinerLines?: boolean
  defaultIcons?: Partial<Record<EntityIconKind, string>>
  /** Icons the user favorited in the Icon Picker — bare Lucide ids (kebab), in display/reorder order. */
  favoriteIcons?: string[]
  /** Depth-1 Sets vs their Collection's loose pages. */
  setPlacement?: FolderPlacement
  /** Sub-Sets (depth-2+) vs their parent Set's loose pages. */
  subSetPlacement?: FolderPlacement
  /** The sidebar ribbon's active mode (which content the column shows). Absent = 'collections'. */
  sidebarMode?: SidebarMode
  /** Ribbon icon order below the pinned Homepage — bare icon keys, in display order. */
  ribbonOrder?: string[]
  /** The window zoom the nexus opens at (and ⌘0 resets to). Absent = 1.0. Set by hand in
   *  settings.json for now; ⌘ +/− nudge live from it. Applied main-side (webContents zoom). */
  defaultViewScale?: number
}

/** The per-nexus default window zoom (`personalization.defaultViewScale`). Clamped so a hand-typed
 *  settings.json value can't make the window unusable; absent/invalid → 1.0 (100%). */
export const VIEW_SCALE_DEFAULT = 1
export const VIEW_SCALE_MIN = 0.5
export const VIEW_SCALE_MAX = 3
export function coerceViewScale(v: unknown): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) return VIEW_SCALE_DEFAULT
  return Math.min(VIEW_SCALE_MAX, Math.max(VIEW_SCALE_MIN, v))
}

/** Nexus-wide keyboard commands — the `commands` object in `.nexus/settings.json`. Keys are
 *  command ids, values are shortcut specs ("cmd+e"); an absent id falls back to its default here.
 *  Every future rebindable shortcut registers as a row in this map. */
export const DEFAULT_COMMANDS: Record<string, string> = {
  'toggle-ribbon': 'cmd+e'
}

export interface BaseNode {
  id: string
  kind: NodeKind
  /** Derived from the file/folder basename — never stored on disk. */
  title: string
  /** Optional per-entity icon override (a symbol name). */
  icon?: string
}

/**
 * A node backed by a real file or folder on disk, carrying its nexus-relative
 * POSIX path so a mutation can address it: the renderer sends `path` back and
 * main resolves it under the session root (the renderer must never reconstruct
 * the on-disk path — that layout is main's to know). Pages + every container are
 * PathNodes; only the code-keyed SavedNode (homepage/calendar/recents) is not.
 */
export interface PathNode extends BaseNode {
  /** Nexus-relative POSIX path to the entity on disk (forward slashes). */
  path: string
  /** Nexus-relative POSIX path to this entity's banner image, if set. Only banner-bearing
   *  owners (Collections/Sets + contexts) populate it, surfaced from the sidecar `banner` field
   *  (a page's future banner rides here too — distinct from the page-level `cover`). */
  banner?: string
}

export interface SavedNode extends BaseNode {
  kind: 'saved'
  /** Code-fixed identity; label is renameable, key is not. */
  key: 'homepage' | 'calendar' | 'recents'
}

export interface AreaNode extends PathNode {
  kind: 'area'
  color?: AreaColor
}

export interface TopicNode extends PathNode {
  kind: 'topic'
}

export interface ProjectNode extends PathNode {
  kind: 'project'
}

export interface PageNode extends PathNode {
  kind: 'page'
}

/** How a page opens from its collection — full-view or a hovering preview window. Collection-owned;
 *  a Set proxies its parent Collection's value. */
export type OpenIn = 'full-page' | 'page-preview'
/** The ViewDropdown button presentation: icon-only vs icon + view name (Show/Hide Title). */
export type ViewButton = 'icon' | 'labeled'
/** The view-switcher presentation: the dropdown or the inline ViewBar (Prospect). */
export type ViewStyle = 'dropdown' | 'toolbar'

export interface SetNode extends PathNode {
  kind: 'set'
  /** Child Sets nested at any depth (2-tier recursion). Optional during the migration
   *  window; populated by the recursive read. */
  sets?: SetNode[]
  pages: PageNode[]
  /** Saved views from the sidecar `views[]` (depth-1 Sets only; deeper Sub-Sets ignore them). */
  views?: SavedView[]
  /** Per-container ViewDropdown presentation (sidecar `view_button` / `view_style`). */
  viewButton?: ViewButton
  viewStyle?: ViewStyle
}

export interface CollectionNode extends PathNode {
  kind: 'collection'
  sets: SetNode[] // rendered before pages
  pages: PageNode[]
  /** The property schema every Page inside inherits (2-tier top tier). Read from the
   *  Collection sidecar's `properties`. */
  properties?: PropertyDefinition[]
  /** Saved views from the sidecar `views[]`. */
  views?: SavedView[]
  /** Collection-owned page-open behavior (sidecar `open_in`). */
  openIn?: OpenIn
  /** Per-container ViewDropdown presentation (sidecar `view_button` / `view_style`). */
  viewButton?: ViewButton
  viewStyle?: ViewStyle
}

export interface UserSection {
  id: string
  label: string
  /** Top-tier Collections grouped into this user section. */
  collections: CollectionNode[]
}

/** A user-facing entity name in both forms (mirrors Swift `LabelPair`). */
export interface LabelPair {
  singular: string
  plural: string
}

/** Per-Nexus UI labels (read from `settings.labels.{area,topic,project,page_collection,page_set,agenda_task,agenda_event}`).
 *  All three context tiers are first-class LabelPairs; sidebar section headers derive from the plurals
 *  (Areas ← area.plural, Topics ← topic.plural, Collections ← pageCollection.plural). "Sub-Set" is
 *  derived as `"Sub-" + pageSet.singular`, never stored. */
export interface NexusLabels {
  area: LabelPair
  topic: LabelPair
  project: LabelPair
  pageCollection: LabelPair
  pageSet: LabelPair
  agendaTask: LabelPair
  agendaEvent: LabelPair
}

export interface NexusTree {
  /** `name` is the root folder's basename (filename = title). `profileImage` is a
   *  nexus-relative path into `.nexus/assets/<id>/` (or null) and `profileSubtitle` a
   *  ≤30-char blurb — both from `.nexus/settings.json`, matching Swift (not nexus.json). */
  nexus: { id: string; rootPath: string; name: string; profileImage: string | null; profileSubtitle: string }
  /** Homepage singleton (`.nexus/homepage.json`) — v1 surfaces just its optional banner. */
  homepage: { banner?: string }
  saved: SavedNode[]
  contexts: {
    projects: ProjectNode[]
    topics: TopicNode[]
    areas: AreaNode[]
  }
  /** Ungrouped top-tier Collections (those not assigned to a user section). */
  collections: CollectionNode[]
  userSections: UserSection[]
  labels: NexusLabels
  /** Resolved app accent from .nexus/settings.json (defaults to DEFAULT_ACCENT). */
  accent: AccentSetting
  /** Nexus-wide time format (.nexus/settings.json `time_format`) — drives the datetime picker's
   *  segment set. Defaults to twelveHour (AM/PM). */
  timeFormat: TimeFormatSetting
  /** Nexus-wide interface personalization (`settings.json` `personalization`) — the DRY config the
   *  renderer's apply-map consumes. Accent is surfaced separately as `accent` above (resolved,
   *  back-compat with the legacy top-level `accent_color`). */
  personalization: Personalization
  /** Nexus-wide keyboard commands (`settings.json` `commands`) — DEFAULT_COMMANDS overlaid with
   *  the user's on-disk overrides, so every id always resolves to a spec. */
  commands: Record<string, string>
  /** Every registry definition, in the nexus-wide cosmetic order (order-listed first,
   *  unlisted appended) — reserved ids included; consumers filter (E-1/E-5). */
  registry: PropertyDefinition[]
}

/**
 * The renderer's view of what's open, from the `nexus:state` read. `empty` = no
 * nexus open (show the empty state, not an error); `open` = open + read OK;
 * `error` = a nexus is open but its tree couldn't be read. Never throws across IPC.
 */
export type NexusState =
  | { status: 'empty' }
  | { status: 'open'; tree: NexusTree }
  | { status: 'error'; error: string }

/** On-demand single-page read result envelope — never throws across the boundary. */
export type PageResult =
  | { ok: true; page: PageDetail }
  | { ok: false; error: string }

/** What the renderer currently has open: a container, a page, or nothing. */
export type SelectionState =
  | { kind: 'none' }
  | { kind: 'homepage' }
  | { kind: 'context'; id: string }
  | { kind: 'collection'; id: string }
  /** A depth-1 Set (direct child of a Collection) — the only selectable Set; deeper
   *  Sub-Sets are expand-only. Carries `path` for rename-safe reconciliation, like a page. */
  | { kind: 'set'; id: string; path: string }
  | { kind: 'page'; id: string; path: string }

/** Per-nexus Subfield (footer) config — persisted as a foreign `subfield` key in settings.json
 *  (Swift ignores unknown keys, so it round-trips safely). */
export interface SubfieldConfig {
  /** Per-view-kind ordered item ids; absent kinds fall back to the built-in defaults. */
  order: Partial<Record<SelectionState['kind'], string[]>>
  /** App-level expanded/collapsed flag (all views share one). */
  expanded: boolean
}

/** A single page's full content, read on demand for the detail view. */
export interface PageDetail {
  id: string
  title: string
  /** Nexus-relative POSIX path to the `.md` file (forward slashes). */
  path: string
  frontmatter: Record<string, unknown>
  body: string
}

/** How a vault's pages are laid out in the detail pane. */
export type ViewMode = 'table' | 'gallery'

// ---------- View pipeline seam types (filter → group → sort) ----------

/**
 * One row fed to the view pipeline. Carries the intrinsic PageNode fields plus the page's
 * parsed `frontmatter` (the source of property-keyed column values). `frontmatter` is
 * REQUIRED: when values aren't loaded yet, the flatten step supplies a minimal `{ id }` so the
 * row still sorts/groups/filters on intrinsic fields. `parentSetId` is the id of the Set the
 * page lives in (undefined for a container-root page), used to build structural disclosure
 * groups. Pure data — no fs, no React.
 */
export interface ViewRow {
  id: string
  title: string
  icon?: string
  path: string
  parentSetId?: string
  frontmatter: PageFrontmatter
}

/** What a resolved column renders from. `title`/`tier`/`modified` are reserved columns;
 *  `property` is a user-defined schema property. (Width + the group/sort hoist are Part-2
 *  render concerns, not modeled here.) */
export type ColumnKind = 'title' | 'property' | 'tier' | 'modified'

/** A resolved table column — the stable seam Part 2's table routes to. `id` is the property id
 *  (reserved `_title`/`_tierN`/`_modified_at`, or a `prop_*`); `kind` picks the cell renderer. */
export interface ResolvedColumn {
  id: string
  kind: ColumnKind
}

/** How a resolved group was formed. `structural-set` = a Set/Sub-Set disclosure group;
 *  `property` = grouped by a property value; `ungrouped` = the no-value / flat band. */
export type GroupKind = 'structural-set' | 'property' | 'ungrouped'

/** A resolved bucket of rows produced by the pipeline. `children` nests Sub-Set groups under a
 *  Set group (structural grouping); `items` holds this group's own rows. `key` is the group's
 *  identity (a property value, a Set id, or `'_ungrouped'`) — round-trips `collapsed_groups`.
 *  Header labels are derived at render time (Part 2) from `key` + schema, not stored here. */
export interface ResolvedGroup {
  key: string
  kind: GroupKind
  items: ViewRow[]
  children?: ResolvedGroup[]
  isCollapsed: boolean
  /** Sub-group bands only: the raw bucket value (`key` is the composite set/bucket collapse id). */
  bucket?: string
}

/** The reserved `key` for the no-value / flat / structural-root band. Stored on disk in
 *  `collapsed_groups`, so it round-trips across builds — the single source the pipeline and the
 *  Part-2 render code both match group keys against. */
export const UNGROUPED = '_ungrouped'

export const DEFAULT_LABELS: NexusLabels = {
  area: { singular: 'Area', plural: 'Areas' },
  topic: { singular: 'Topic', plural: 'Topics' },
  project: { singular: 'Project', plural: 'Projects' },
  pageCollection: { singular: 'Collection', plural: 'Collections' },
  pageSet: { singular: 'Set', plural: 'Sets' },
  agendaTask: { singular: 'Task', plural: 'Tasks' },
  agendaEvent: { singular: 'Event', plural: 'Events' }
}

/** The derived Sub-Set label (deeper Sets); never stored — Swift derives it the same way. */
export function subSetLabel(labels: NexusLabels): string {
  return 'Sub-' + labels.pageSet.singular
}
