// The mutate IPC contract — renderer→main write requests. Paths are nexus-relative POSIX
// (main resolves them under the session root via resolveUnderRoot); entities are addressed
// by path, never by a renderer-supplied absolute path. Kept in its own shared file (not
// types.ts) so it can import the data-layer Result/error shape.

import type { PommoraError } from './result'

/** The base name a "New …" action gives a fresh entity (main disambiguates collisions). */
export const DEFAULT_NEW_NAME = 'Untitled'

/** Entity kinds a mutation can target — every NodeKind except the code-keyed `saved`. */
export type MutableKind = 'page' | 'pageType' | 'collection' | 'set' | 'area' | 'topic' | 'project'

/** The entities that can own a banner image: the vault + collections + the three context tiers
 *  (folder sidecars), plus the homepage singleton (`.nexus/homepage.json`). */
export type BannerOwnerKind = 'pageType' | 'collection' | 'area' | 'topic' | 'project' | 'homepage'

/** A folder container a page or sub-container can be created inside. These match their
 *  SidecarKind names exactly, so main passes them straight to createFolderEntity. */
export type MutableContainerKind = 'pageType' | 'collection' | 'set'

/** Top-level order groups, persisted in `.nexus/state.json` — vaults + the three context tiers.
 *  Single source for the union spelled across the engine, store, and IPC (and re-used in main). */
export type StateOrderKey = 'vault_order' | 'area_order' | 'topic_order' | 'project_order'
/** Within-container child-order keys carried by reorderChildren — collections on a vault, sets on a collection. */
export type ChildOrderKey = 'collection_order' | 'set_order'

/** A renderer→main write request. `parentPath: ''` targets the nexus root (new vault). */
export type MutateRequest =
  | { op: 'createPage'; parentPath: string; name: string }
  | { op: 'createContainer'; parentPath: string; kind: MutableContainerKind; name: string }
  | { op: 'createContext'; tier: 1 | 2 | 3; name: string }
  | { op: 'rename'; path: string; kind: MutableKind; newName: string }
  | { op: 'delete'; path: string; kind: MutableKind }
  // Set the nexus description, written into `.nexus/nexus.json` (merged, not clobbered).
  | { op: 'setNexusDescription'; description: string }
  // Set or clear an entity's banner. dataUrl set ⇒ decode + copy into `.nexus/assets/<key>/
  // banner.<ext>` + record that path in the owner's config (folder sidecar, or homepage.json for
  // the homepage singleton); null ⇒ clear the field + delete the file (delete-after-write).
  | { op: 'setBanner'; path: string; kind: BannerOwnerKind; dataUrl: string | null }
  // `order`: the destination container's full page-id order after the drop (renderer-
  // computed). Absent = legacy append (order falls back to title/creation). Same parent +
  // order = a pure reorder. Stale ids in a source container self-drop on the next read.
  | { op: 'movePage'; path: string; newParentPath: string; order?: string[] }
  // Move a set between collections (within its vault) or reorder it among a collection's sets:
  // `fs.rename` the set folder into `newParentPath` (a no-op when that's its current collection),
  // then write the destination collection's `set_order`. movePage's shape, one level up.
  | { op: 'moveSet'; path: string; newParentPath: string; order: string[] }
  // Reorder a folder's child containers in place: `collection_order` on a vault, `set_order`
  // on a collection. `order` is the full ordered id list (renderer-computed). No file move.
  | { op: 'reorderChildren'; parentPath: string; key: ChildOrderKey; order: string[] }
  // Reorder a top-level group (held in `.nexus/state.json`): vaults or a context tier.
  | { op: 'reorderTop'; key: StateOrderKey; order: string[] }

/**
 * The mutate result envelope (never throws across IPC). On a create, returns the new
 * entity's id + nexus-relative path so the renderer can select it after refetching the tree.
 */
export type MutateResult =
  | { ok: true; created?: { id: string; path: string } }
  | { ok: false; error: PommoraError }

/** What the renderer hands main to pop a native context menu for one sidebar entity. */
export interface ContextTarget {
  kind: MutableKind
  /** Nexus-relative POSIX path (PathNode.path). */
  path: string
  title: string
}
