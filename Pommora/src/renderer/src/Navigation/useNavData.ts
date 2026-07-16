import { useCallback, useEffect, useMemo } from 'react'
import type { NavTarget } from '@shared/types'
import { useSession, type SelectTarget } from '../store'
import { reconcileSelection } from '../selection'
import { buildResolveIndex, resolveFavorites, resolvePins, resolveRecents, resolveWith, type ResolvedNav } from './navResolve'
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

/** The shared read side both NavWindow + NavPane render from — one source, two presentations. The tree
 *  index is memoized on (tree, agenda), so search filters per keystroke WITHOUT re-walking the tree. */
export function useNavData(): {
  resolvedRecents: ResolvedNav[]
  resolvedFavorites: ResolvedNav[]
  resolvedPins: ResolvedNav[]
  search: (query: string) => SearchResult[]
  go: (target: NavTarget, onDone?: () => void) => void
} {
  const tree = useSession((s) => s.tree)
  const recents = useSession((s) => s.recents)
  const favorites = useSession((s) => s.favorites)
  const pins = useSession((s) => s.pins)
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
  const resolvedPins = useMemo(() => (resolveIndex ? resolvePins(resolveIndex, pins) : []), [resolveIndex, pins])
  const pinnedKeys = useMemo(() => new Set(resolvedPins.map((p) => p.key)), [resolvedPins])
  // Recents dedupe against pins — a pinned entity shows once, in the pins section, not twice.
  const resolvedRecents = useMemo(
    () => (resolveIndex ? resolveRecents(resolveIndex, recents).filter((r) => !pinnedKeys.has(r.key)) : []),
    [resolveIndex, recents, pinnedKeys]
  )
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
      // A durable pin's stored path can be stale (its entity moved/renamed since) — reconcile by id
      // against the live tree before opening, as Back/Forward do. If reconcile can't resolve it
      // (`none` — a genuinely-gone entity, or a reconcile miss), fall back to the original target so
      // the click still navigates rather than silently doing nothing.
      const reconciled = tree ? reconcileSelection(tree, target) : target
      void select(reconciled.kind === 'none' ? target : reconciled)
      onDone?.()
    },
    [select, tree]
  )

  return { resolvedRecents, resolvedFavorites, resolvedPins, search, go }
}
