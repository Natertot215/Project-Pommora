// Single source of truth for the cross-process contract.
// Imported by main, preload, and renderer — NO fs, NO React here.

import type { PropertyDefinition } from './properties'

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

export interface SetNode extends PathNode {
  kind: 'set'
  /** Child Sets nested at any depth (2-tier recursion). Optional during the migration
   *  window; populated by the recursive read. */
  sets?: SetNode[]
  pages: PageNode[]
}

export interface CollectionNode extends PathNode {
  kind: 'collection'
  sets: SetNode[] // rendered before pages
  pages: PageNode[]
  /** The property schema every Page inside inherits (2-tier top tier). Read from the
   *  Collection sidecar's `properties`. */
  properties?: PropertyDefinition[]
}

export interface UserSection {
  id: string
  label: string
  /** Top-tier Collections grouped into this user section. */
  collections: CollectionNode[]
}

export interface NexusLabels {
  areas: string
  topics: string
  projects: string
  collection: string
  set: string
}

export interface NexusTree {
  /** `name` is the root folder's basename (filename = title); `description` is the
   *  user-set blurb persisted in `.nexus/nexus.json` ('' when unset). */
  nexus: { id: string; rootPath: string; name: string; description: string; photo: string | null }
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
  areas: 'Areas',
  topics: 'Topics',
  projects: 'Projects',
  collection: 'Collection',
  set: 'Set'
}
