import { useCallback, useEffect, useMemo } from 'react'
import type { NavTarget } from '@shared/types'
import { useSession, type SelectTarget } from '../store'
import { buildResolveIndex, resolveFavorites, resolveRecents, resolveWith, type ResolvedNav } from './navResolve'
import { buildNavIndex, filterNav, type SearchEntry } from './navSearch'

export interface SearchResult {
  entry: SearchEntry
  /** Resolved display, or null for an unresolvable hit (agenda kinds — listed but not yet routable). */
  resolved: ResolvedNav | null
}

/** Split search results into the NavList shape both surfaces render: resolved hits become selectable
 *  `items`; unresolvable ones (agenda) become inert `extras`. */
export function splitSearch(results: SearchResult[]): { items: ResolvedNav[]; extras: { key: string; title: string; kind: string }[] } {
  return {
    items: results.map((r) => r.resolved).filter((r): r is ResolvedNav => r !== null),
    extras: results.filter((r) => r.resolved === null).map((r) => ({ key: r.entry.key, title: r.entry.title, kind: r.entry.target.kind }))
  }
}

// Agenda kinds route nowhere until Agenda ships (E-9b) — search-listable, not selectable.
const isTreeTarget = (t: NavTarget): t is SelectTarget => t.kind !== 'task' && t.kind !== 'event'

/** The shared read side both NavPane + NavMenu render from — one source, two presentations. The tree
 *  index is memoized on (tree, agenda), so search filters per keystroke WITHOUT re-walking the tree. */
export function useNavData(): {
  resolvedRecents: ResolvedNav[]
  resolvedFavorites: ResolvedNav[]
  search: (query: string) => SearchResult[]
  go: (target: NavTarget, onDone?: () => void) => void
} {
  const tree = useSession((s) => s.tree)
  const recents = useSession((s) => s.recents)
  const favorites = useSession((s) => s.favorites)
  const agenda = useSession((s) => s.agendaSnapshot)
  const select = useSession((s) => s.select)
  const ensureAgendaSnapshot = useSession((s) => s.ensureAgendaSnapshot)

  // Re-warm the agenda snapshot whenever it's null while a nav surface is open (a mid-open tree push
  // invalidates it) — otherwise agenda hits silently drop from search until reopen.
  useEffect(() => {
    if (agenda === null) void ensureAgendaSnapshot()
  }, [agenda, ensureAgendaSnapshot])

  const resolveIndex = useMemo(() => (tree ? buildResolveIndex(tree) : null), [tree])
  const searchIndex = useMemo(() => (tree ? buildNavIndex(tree, agenda ?? undefined) : []), [tree, agenda])
  const resolvedRecents = useMemo(() => (resolveIndex ? resolveRecents(resolveIndex, recents) : []), [resolveIndex, recents])
  const resolvedFavorites = useMemo(() => (resolveIndex ? resolveFavorites(resolveIndex, favorites) : []), [resolveIndex, favorites])

  const search = useCallback(
    (query: string): SearchResult[] => {
      if (!resolveIndex || !query.trim()) return []
      return filterNav(searchIndex, query).map((entry) => ({ entry, resolved: resolveWith(resolveIndex, entry.target) }))
    },
    [searchIndex, resolveIndex]
  )

  const go = useCallback(
    (target: NavTarget, onDone?: () => void): void => {
      if (!isTreeTarget(target)) return
      void select(target)
      onDone?.()
    },
    [select]
  )

  return { resolvedRecents, resolvedFavorites, search, go }
}
