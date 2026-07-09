// The mutate IPC contract — renderer→main write requests. Paths are nexus-relative POSIX
// (main resolves them under the session root via resolveUnderRoot); entities are addressed
// by path, never by a renderer-supplied absolute path. Kept in its own shared file (not
// types.ts) so it can import the data-layer Result/error shape.

import type { PommoraError } from './result'
import type { PropertyValue } from './propertyValue'

/** The base name a "New …" action gives a fresh entity (main disambiguates collisions). */
export const DEFAULT_NEW_NAME = 'Untitled'

/** Entity kinds a mutation can target — every NodeKind except the code-keyed `saved`. */
export type MutableKind = 'page' | 'collection' | 'set' | 'area' | 'topic' | 'project'

/** The entities that can own a banner image: Collections + Sets + the three context tiers
 *  (folder sidecars), the homepage singleton (`.nexus/homepage.json`), and a page (whose banner
 *  is the Swift-compatible `cover` field in its `.md` frontmatter). */
export type BannerOwnerKind = 'collection' | 'set' | 'area' | 'topic' | 'project' | 'homepage' | 'page'

/** A folder container a page or sub-container can be created inside. These match their
 *  SidecarKind names exactly, so main passes them straight to createFolderEntity. */
export type MutableContainerKind = 'collection' | 'set'

/** Top-level order groups, persisted in `.nexus/state.json` — top Collections + the three
 *  context tiers. Single source for the union spelled across the engine, store, and IPC
 *  (and re-used in main). */
export type StateOrderKey =
  | 'collection_order'
  | 'area_order'
  | 'topic_order'
  | 'project_order'
/** Within-container child-order keys carried by reorderChildren — collections on a vault, sets on a collection. */
export type ChildOrderKey = 'collection_order' | 'set_order'

/** A renderer→main write request. `parentPath: ''` targets the nexus root (new vault). */
export type MutateRequest =
  | { op: 'createPage'; parentPath: string; name: string }
  | { op: 'createContainer'; parentPath: string; kind: MutableContainerKind; name: string }
  | { op: 'createContext'; tier: 1 | 2 | 3; name: string }
  | { op: 'rename'; path: string; kind: MutableKind; newName: string }
  | { op: 'delete'; path: string; kind: MutableKind }
  // Set/clear the nexus profile image (sidebar header avatar). dataUrl set ⇒ decode + copy
  // into `.nexus/assets/<nexusID>/profile-<token>.<ext>` + record the rel path in
  // `settings.profile_image`; null ⇒ clear the field + delete the file. Matches Swift.
  | { op: 'setProfileImage'; dataUrl: string | null }
  // Set the nexus profile subtitle (≤30 chars, enforced) in `settings.profile_subtitle`. Parked: the
  // sidebar NexusHeader that edited it is gone (ribbon rework); the field + op are retained for the
  // eventual homepage/settings surface — NOT dead code.
  | { op: 'setProfileSubtitle'; subtitle: string }
  // Set or clear an entity's banner. dataUrl set ⇒ decode + copy into `.nexus/assets/<key>/
  // banner.<ext>` + record that path in the owner's config (folder sidecar, homepage.json, or — for
  // a page — the `cover` key in its `.md` frontmatter); null ⇒ clear the field + delete the file.
  | { op: 'setBanner'; path: string; kind: BannerOwnerKind; dataUrl: string | null }
  // Set or clear an entity's icon — a bare symbol id (any Lucide id). A page carries it in its `.md`
  // frontmatter `icon`; a container/context in its JSON sidecar. `null` clears the field. The one write
  // for every entity kind that has an icon (pages, collections, sets, and the three context tiers);
  // property + view icons ride their own writers (properties.json / views.save). Foreign keys survive.
  | { op: 'setIcon'; path: string; kind: MutableKind; icon: string | null }
  // Set or clear one property in a page's `.md` frontmatter `properties` map (id-keyed PropertyValue);
  // `null` clears the key. Foreign frontmatter + body survive. Drives table cross-group reassignment
  // (D-4) + later inline edits — the single typed property write.
  | { op: 'setProperty'; path: string; propertyId: string; value: PropertyValue | null }
  // Set a page's tier-N context links — the BARE ULID array at the frontmatter root
  // (`tier1`/`tier2`/`tier3`), never a `$ctx` property. Written whole; empty = clear.
  | { op: 'setTier'; path: string; tier: number; contextIds: string[] }
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
  // Reorder a top-level group (held in `.nexus/state.json`): top Collections or a context tier.
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
