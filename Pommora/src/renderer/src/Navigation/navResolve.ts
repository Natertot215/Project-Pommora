// Render-time resolution of stored recents/favorites against the LIVE tree. Every entry carries only
// {kind,id,path} — its title, icon, and location are resolved fresh here, so a rename/move is always
// current and never cached stale. An entry that no longer resolves (deleted, or a cross-nexus target
// against the wrong tree) is RENDER-PRUNED — dropped from the returned list, NEVER from storage (E-3:
// a cross-nexus switch resolves everything to null; auto-deleting would wipe the durable favorites).
// Agenda kinds (task/event) have no resolver/destination in v1 (E-9b) — absent from the index → null.
//
// Resolution goes through a display index built in ONE tree walk, so resolving a full recents list is
// O(tree + entries), not O(entries × tree) — the gallery must never re-flatten the tree per card.

import type { NavTarget, NexusTree, RecentEntry } from '@shared/types'
import { allCollections } from '../selection'
import { navKey } from './navRecents'

export interface ResolvedNav {
  key: string
  /** The clean nav target to select on click — exactly the entry's {kind,id,path}, no `pinned`. */
  target: NavTarget
  kind: NavTarget['kind']
  title: string
  /** Raw stored icon; the card applies the per-kind default (mirrors the sidebar). */
  icon?: string
  /** Where it lives — the container chain (page/set), the tier (context), or the nexus (collection). */
  location: string
  /** Recents only: drives the float-to-top at render. */
  pinned?: boolean
}

type NavCore = { title: string; icon?: string; location: string }
/** navKey → display core. Built once per tree; resolution is then an O(1) lookup per entry. */
export type ResolveIndex = Map<string, NavCore>

const TIER_KIND = { areas: 'area', topics: 'topic', projects: 'project' } as const

/** Flatten the tree into the display index in a single walk: homepage, every context (tier as its
 *  location), every Collection (nexus as location), every Set + Page (their container chain). */
export function buildResolveIndex(tree: NexusTree): ResolveIndex {
  const ix: ResolveIndex = new Map()
  ix.set('homepage', { title: tree.nexus.name, location: '' })
  for (const tier of ['areas', 'topics', 'projects'] as const) {
    const location = tree.labels[TIER_KIND[tier]].singular
    for (const c of tree.contexts[tier]) ix.set(`context:${c.id}`, { title: c.title, icon: c.icon, location })
  }
  const walkSets = (sets: NexusTree['collections'][number]['sets'] | undefined, parents: string[]): void => {
    for (const s of sets ?? []) {
      ix.set(`set:${s.id}`, { title: s.title, icon: s.icon, location: parents.join(' / ') })
      const chain = [...parents, s.title]
      for (const p of s.pages) ix.set(`page:${p.id}`, { title: p.title, location: chain.join(' / ') })
      walkSets(s.sets, chain)
    }
  }
  for (const col of allCollections(tree)) {
    ix.set(`collection:${col.id}`, { title: col.title, icon: col.icon, location: tree.nexus.name })
    for (const p of col.pages) ix.set(`page:${p.id}`, { title: p.title, location: col.title })
    walkSets(col.sets, [col.title])
  }
  return ix
}

/** Strip a recents entry down to its clean nav target (no `pinned`), for select-on-click + storage. */
function cleanTarget(entry: RecentEntry): NavTarget {
  const { pinned: _pinned, ...target } = entry
  return target as NavTarget
}

/** Resolve one entry against a prebuilt index, or null when it no longer resolves (render-prune). */
export function resolveWith(index: ResolveIndex, entry: RecentEntry): ResolvedNav | null {
  const key = navKey(entry)
  const core = index.get(key)
  if (!core) return null
  return { key, target: cleanTarget(entry), kind: entry.kind, title: core.title, icon: core.icon, location: core.location, pinned: entry.pinned }
}

/** Resolve one entry against the tree (single-entry convenience; builds an index for that one call). */
export function resolveNavEntry(tree: NexusTree, entry: RecentEntry): ResolvedNav | null {
  return resolveWith(buildResolveIndex(tree), entry)
}

/** Resolve the recents stream for render: prune gone entries, then float pinned to the top while
 *  preserving MRU order within each group (storage stays honest history; the float is render-only). */
export function resolveRecents(tree: NexusTree, recents: RecentEntry[]): ResolvedNav[] {
  const index = buildResolveIndex(tree)
  const resolved = recents.map((r) => resolveWith(index, r)).filter((r): r is ResolvedNav => r !== null)
  return [...resolved.filter((r) => r.pinned), ...resolved.filter((r) => !r.pinned)]
}

/** Resolve favorites for render: prune gone entries, preserve stored order (the durable sidebar list). */
export function resolveFavorites(tree: NexusTree, favorites: RecentEntry[]): ResolvedNav[] {
  const index = buildResolveIndex(tree)
  return favorites.map((f) => resolveWith(index, f)).filter((r): r is ResolvedNav => r !== null)
}
