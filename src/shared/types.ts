// Single source of truth for the cross-process contract.
// Imported by main, preload, and renderer — NO fs, NO React here.

export type NodeKind =
  | 'saved'
  | 'area'
  | 'topic'
  | 'project'
  | 'pageType'
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

/** Default accent when settings.json omits or has an invalid `accent`. */
export const DEFAULT_ACCENT: AccentSetting = 'lavender'

export interface BaseNode {
  id: string
  kind: NodeKind
  /** Derived from the file/folder basename — never stored on disk. */
  title: string
  /** Optional per-entity icon override (a symbol name). */
  icon?: string
}

export interface SavedNode extends BaseNode {
  kind: 'saved'
  /** Code-fixed identity; label is renameable, key is not. */
  key: 'homepage' | 'calendar' | 'recents'
}

export interface AreaNode extends BaseNode {
  kind: 'area'
  color?: AreaColor
}

export interface TopicNode extends BaseNode {
  kind: 'topic'
}

export interface ProjectNode extends BaseNode {
  kind: 'project'
}

export interface PageNode extends BaseNode {
  kind: 'page'
  /** frontmatter id, or a synthesized `adopted-<hash>` when absent. */
  /** Nexus-relative POSIX path to the `.md` file (forward slashes). */
  path: string
}

export interface SetNode extends BaseNode {
  kind: 'set'
  selectable: false
  pages: PageNode[]
}

export interface CollectionNode extends BaseNode {
  kind: 'collection'
  sets: SetNode[] // rendered before pages
  pages: PageNode[]
}

export interface PageTypeNode extends BaseNode {
  kind: 'pageType'
  collections: CollectionNode[] // rendered before pages
  pages: PageNode[]
}

export interface UserSection {
  id: string
  label: string
  vaults: PageTypeNode[]
}

export interface NexusLabels {
  vaults: string
  areas: string
  topics: string
  collection: string
  set: string
}

export interface NexusTree {
  nexus: { id: string; rootPath: string }
  saved: SavedNode[]
  contexts: {
    projects: ProjectNode[]
    topics: TopicNode[]
    areas: AreaNode[]
  }
  /** Ungrouped PageTypes (those not assigned to a user section). */
  vaults: PageTypeNode[]
  userSections: UserSection[]
  labels: NexusLabels
  /** Resolved app accent from .nexus/settings.json (defaults to DEFAULT_ACCENT). */
  accent: AccentSetting
}

/** Single IPC read result envelope — never throws across the boundary. */
export type OpenResult =
  | { ok: true; tree: NexusTree }
  | { ok: false; error: string }

/** On-demand single-page read result envelope — never throws across the boundary. */
export type PageResult =
  | { ok: true; page: PageDetail }
  | { ok: false; error: string }

/** What the renderer currently has open: a container, a page, or nothing. */
export type SelectionState =
  | { kind: 'none' }
  | { kind: 'vault'; id: string }
  | { kind: 'page'; id: string; path: string }

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

// ---------- View pipeline (filter → group → sort) ----------

/**
 * One row fed to the view pipeline. Carries the intrinsic PageNode fields the
 * sidebar already loads, plus an OPTIONAL `frontmatter` bag for frontmatter-keyed
 * columns. Today the loaded NexusTree only supplies the intrinsic fields, so
 * frontmatter is absent and frontmatter-keyed fields resolve to `undefined`
 * (rows still sort/group/filter on the intrinsic fields). When a later stage
 * fetches per-page frontmatter, populating `frontmatter` lights up richer
 * columns with NO pipeline change. Pure data — no fs, no React.
 */
export interface ViewRow {
  id: string
  title: string
  icon?: string
  path: string
  frontmatter?: Record<string, unknown>
}

/**
 * Names an addressable value on a ViewRow. `title` | `icon` | `path` read the
 * intrinsic field; any other string reads `frontmatter[field]` (undefined when
 * frontmatter is absent or lacks the key).
 */
export type ViewField = 'title' | 'icon' | 'path' | (string & {})

export type SortDirection = 'asc' | 'desc'

export interface SortSpec {
  field: ViewField
  direction: SortDirection
}

/** Comparison operators for a single filter rule (string-oriented, case-insensitive). */
export type FilterOperator = 'equals' | 'notEquals' | 'contains' | 'isEmpty' | 'isNotEmpty'

export interface FilterRule {
  field: ViewField
  operator: FilterOperator
  /** Ignored by isEmpty / isNotEmpty. */
  value?: string
}

/** A full view definition the pipeline resolves against a set of rows. */
export interface ViewSpec {
  /** All rules must pass (AND). Empty / omitted ⇒ no filtering. */
  filters?: FilterRule[]
  /** Field to group by. Omitted ⇒ a single implicit group. */
  groupBy?: ViewField
  /** Sort applied WITHIN each group. Omitted ⇒ original order preserved. */
  sort?: SortSpec
}

/** A resolved bucket of rows produced by the pipeline. */
export interface ResolvedGroup {
  /**
   * The group's identity. The grouped field's value as a string, `''` for the
   * empty/absent bucket, or `'__all__'` for the single implicit group when no
   * `groupBy` is set.
   */
  key: string
  /** Human label for the group header (`key`, or 'All' / 'Empty' for sentinels). */
  label: string
  rows: ViewRow[]
}

export const DEFAULT_LABELS: NexusLabels = {
  vaults: 'Vaults',
  areas: 'Areas',
  topics: 'Topics',
  collection: 'Collection',
  set: 'Set'
}
