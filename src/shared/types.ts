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

// Contexts tier-1 (Area) color palette — 10 cases. KEEP DISTINCT from the
// Settings accent palette (a separate 8-case enum) — do not conflate.
export type AreaColor =
  | 'gray'
  | 'brown'
  | 'orange'
  | 'yellow'
  | 'green'
  | 'blue'
  | 'purple'
  | 'pink'
  | 'red'
  | 'accent'

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
}

/** Single IPC read result envelope — never throws across the boundary. */
export type OpenResult =
  | { ok: true; tree: NexusTree }
  | { ok: false; error: string }

export const DEFAULT_LABELS: NexusLabels = {
  vaults: 'Vaults',
  areas: 'Areas',
  topics: 'Topics',
  collection: 'Collection',
  set: 'Set'
}
