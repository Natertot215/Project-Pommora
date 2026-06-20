import type { CollectionNode, NexusTree, PageTypeNode } from '@shared/types'
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

/** Find a vault (PageTypeNode) by id across the ungrouped vaults + user sections. */
export function findVault(tree: NexusTree | null, id: string): PageTypeNode | undefined {
  if (!tree) return undefined
  const inDefault = tree.vaults.find((v) => v.id === id)
  if (inDefault) return inDefault
  for (const sec of tree.userSections) {
    const hit = sec.vaults.find((v) => v.id === id)
    if (hit) return hit
  }
  return undefined
}

/** Find a collection by id across every vault's collections (ungrouped + user sections). */
export function findCollection(tree: NexusTree | null, id: string): CollectionNode | undefined {
  if (!tree) return undefined
  for (const v of [...tree.vaults, ...tree.userSections.flatMap((s) => s.vaults)]) {
    const col = v.collections.find((c) => c.id === id)
    if (col) return col
  }
  return undefined
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

/** The banner owner for a page container (vault or collection) — same shape; kind from the node. */
export function containerOwner(node: PageTypeNode | CollectionNode): BannerOwner {
  return { path: node.path, kind: node.kind, name: node.title, banner: node.banner }
}
