import type { CollectionNode, NexusTree, SetNode } from '@shared/types'
import type { BannerOwnerKind } from '@shared/mutate'

// Resolving a selection to the entity it points at, and the banner owner for any view. The
// renderer's analog of Swift's DetailScope — the seam between "what's selected" and "what renders".

/** A banner-capable view's owner: which entity holds the banner + its current image path. */
export interface BannerOwner {
  path: string
  kind: BannerOwnerKind
  name: string
  banner?: string
}

/** Every top Collection across ungrouped + user sections. */
function allCollections(tree: NexusTree): CollectionNode[] {
  return [...(tree.collections ?? []), ...tree.userSections.flatMap((s) => s.collections ?? [])]
}

/** Find a top Collection by id (ungrouped + user sections). */
export function findCollection(tree: NexusTree | null, id: string): CollectionNode | undefined {
  if (!tree) return undefined
  return allCollections(tree).find((c) => c.id === id)
}

/** Find a Set by id at any depth under the tree's Collections (recursive). */
export function findSet(tree: NexusTree | null, id: string): SetNode | undefined {
  if (!tree) return undefined
  const search = (sets: SetNode[] | undefined): SetNode | undefined => {
    for (const s of sets ?? []) {
      if (s.id === id) return s
      const deep = search(s.sets)
      if (deep) return deep
    }
    return undefined
  }
  for (const c of allCollections(tree)) {
    const hit = search(c.sets)
    if (hit) return hit
  }
  return undefined
}

/** The Collection that owns a Set's inherited schema — the top Collection whose set tree contains
 *  `setId` (a Set has no schema of its own; properties live only on the Collection). */
export function findCollectionForSet(tree: NexusTree | null, setId: string): CollectionNode | undefined {
  if (!tree) return undefined
  const has = (sets: SetNode[] | undefined): boolean => {
    for (const set of sets ?? []) {
      if (set.id === setId) return true
      if (has(set.sets)) return true
    }
    return false
  }
  return allCollections(tree).find((c) => has(c.sets))
}

/** Resolve a context id to its banner owner, scanning the three tiers (the kind is whichever holds it). */
export function findContext(tree: NexusTree | null, id: string): BannerOwner | null {
  if (!tree) return null
  const area = tree.contexts.areas.find((n) => n.id === id)
  if (area) return { path: area.path, kind: 'area', name: area.title, banner: area.banner }
  const topic = tree.contexts.topics.find((n) => n.id === id)
  if (topic) return { path: topic.path, kind: 'topic', name: topic.title, banner: topic.banner }
  const project = tree.contexts.projects.find((n) => n.id === id)
  if (project) return { path: project.path, kind: 'project', name: project.title, banner: project.banner }
  return null
}

/** The banner owner for a page container (Collection or Set) — same shape; kind from the node. */
export function containerOwner(node: CollectionNode | SetNode): BannerOwner {
  return { path: node.path, kind: node.kind, name: node.title, banner: node.banner }
}
