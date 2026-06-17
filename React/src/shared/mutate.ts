// The mutate IPC contract — renderer→main write requests. Paths are nexus-relative POSIX
// (main resolves them under the session root via resolveUnderRoot); entities are addressed
// by path, never by a renderer-supplied absolute path. Kept in its own shared file (not
// types.ts) so it can import the data-layer Result/error shape.

import type { PommoraError } from './result'

/** The base name a "New …" action gives a fresh entity (main disambiguates collisions). */
export const DEFAULT_NEW_NAME = 'Untitled'

/** Entity kinds a mutation can target — every NodeKind except the code-keyed `saved`. */
export type MutableKind = 'page' | 'pageType' | 'collection' | 'set' | 'area' | 'topic' | 'project'

/** A folder container a page or sub-container can be created inside. These match their
 *  SidecarKind names exactly, so main passes them straight to createFolderEntity. */
export type MutableContainerKind = 'pageType' | 'collection' | 'set'

/** A renderer→main write request. `parentPath: ''` targets the nexus root (new vault). */
export type MutateRequest =
  | { op: 'createPage'; parentPath: string; name: string }
  | { op: 'createContainer'; parentPath: string; kind: MutableContainerKind; name: string }
  | { op: 'createContext'; tier: 1 | 2 | 3; name: string }
  | { op: 'rename'; path: string; kind: MutableKind; newName: string }
  | { op: 'delete'; path: string; kind: MutableKind }
  | { op: 'movePage'; path: string; newParentPath: string }

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
