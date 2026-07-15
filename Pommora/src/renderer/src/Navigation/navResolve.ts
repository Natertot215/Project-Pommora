// Render-time resolution of stored recents/favorites against the LIVE tree. Every entry carries only
// {kind,id,path} — its title, icon, and container path are resolved fresh here, so a rename/move is
// always current and never cached stale. An entry that no longer resolves (deleted, or a cross-nexus
// target against the wrong tree) is RENDER-PRUNED — dropped from the returned list, NEVER from storage
// (E-3: a cross-nexus switch resolves everything to null; auto-deleting would wipe durable favorites).
// Agenda kinds (task/event) have no destination in v1 (E-9b) — absent from the index → null.
//
// Resolution goes through a display index built in ONE tree walk, so resolving a full recents list is
// O(tree + entries), not O(entries × tree) — the gallery must never re-flatten the tree per row.

import { defaultEntityIcon, iconNameOr } from '@renderer/design-system/symbols'
import type { NavTarget, NexusTree, RecentEntry } from '@shared/types'
import { allCollections } from '../selection'
import { navKey } from './navRecents'

/** One container in an entry's path — its resolved icon glyph + title (chevron-joined at render). */
export interface PathCrumb {
  icon: string
  title: string
}

export interface ResolvedNav {
  key: string
  /** The clean nav target to select on click — exactly the entry's {kind,id,path}, no `pinned`. */
  target: NavTarget
  kind: NavTarget['kind']
  title: string
  /** The entry's own resolved icon glyph. */
  icon: string
  /** The container chain the entry lives under (empty for a top-level Collection / Homepage). */
  path: PathCrumb[]
  /** Recents only: drives the float-to-top at render. */
  pinned?: boolean
}

type NavCore = { icon: string; title: string; path: PathCrumb[] }
/** navKey → display core. Built once per tree; resolution is then an O(1) lookup per entry. */
export type ResolveIndex = Map<string, NavCore>

const TIER_KIND = { areas: 'area', topics: 'topic', projects: 'project' } as const

/** Flatten the tree into the display index in a single walk: homepage, every context (its tier as the
 *  path), every Collection, every Set + Page (their resolved container chain). Icons resolve against
 *  the Nexus's default-icon overrides, matching the sidebar. */
export function buildResolveIndex(tree: NexusTree): ResolveIndex {
  const ix: ResolveIndex = new Map()
  const di = tree.personalization.defaultIcons
  const colIcon = (n: { icon?: string }): string => iconNameOr(n.icon, defaultEntityIcon('collection', di))
  const setIcon = (n: { icon?: string }): string => iconNameOr(n.icon, defaultEntityIcon('set', di))

  ix.set('homepage', { icon: 'house', title: tree.nexus.name, path: [] })
  for (const tier of ['areas', 'topics', 'projects'] as const) {
    const kind = TIER_KIND[tier]
    const tierCrumb: PathCrumb = { icon: defaultEntityIcon(kind, di), title: tree.labels[kind].singular }
    for (const c of tree.contexts[tier]) ix.set(`context:${c.id}`, { icon: iconNameOr(c.icon, defaultEntityIcon(kind, di)), title: c.title, path: [tierCrumb] })
  }
  const walkSets = (sets: NexusTree['collections'][number]['sets'] | undefined, parents: PathCrumb[]): void => {
    for (const s of sets ?? []) {
      ix.set(`set:${s.id}`, { icon: setIcon(s), title: s.title, path: parents })
      const chain = [...parents, { icon: setIcon(s), title: s.title }]
      for (const p of s.pages) ix.set(`page:${p.id}`, { icon: defaultEntityIcon('page', di), title: p.title, path: chain })
      walkSets(s.sets, chain)
    }
  }
  for (const col of allCollections(tree)) {
    ix.set(`collection:${col.id}`, { icon: colIcon(col), title: col.title, path: [] })
    const colCrumb: PathCrumb = { icon: colIcon(col), title: col.title }
    for (const p of col.pages) ix.set(`page:${p.id}`, { icon: defaultEntityIcon('page', di), title: p.title, path: [colCrumb] })
    walkSets(col.sets, [colCrumb])
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
  return { key, target: cleanTarget(entry), kind: entry.kind, title: core.title, icon: core.icon, path: core.path, pinned: entry.pinned }
}

/** Resolve one entry against the tree (single-entry convenience; builds an index for that one call). */
export function resolveNavEntry(tree: NexusTree, entry: RecentEntry): ResolvedNav | null {
  return resolveWith(buildResolveIndex(tree), entry)
}

/** Resolve the recents stream for render against a prebuilt index: prune gone entries, then float
 *  pinned to the top while preserving MRU order within each group (the float is render-only). */
export function resolveRecents(index: ResolveIndex, recents: RecentEntry[]): ResolvedNav[] {
  const resolved = recents.map((r) => resolveWith(index, r)).filter((r): r is ResolvedNav => r !== null)
  return [...resolved.filter((r) => r.pinned), ...resolved.filter((r) => !r.pinned)]
}

/** Resolve favorites against a prebuilt index: prune gone entries, preserve stored order. */
export function resolveFavorites(index: ResolveIndex, favorites: RecentEntry[]): ResolvedNav[] {
  return favorites.map((f) => resolveWith(index, f)).filter((r): r is ResolvedNav => r !== null)
}
