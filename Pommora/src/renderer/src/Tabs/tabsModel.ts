// Pure tab-list logic for the Multi-Tab Nexus — no store, no IPC, no DOM (unit-tested in isolation).
// `tabs` is the UNPINNED set (what tabs.json persists, C-6); pinned tabs are derived live from the
// pins slice (derivePinnedTabs) and passed in wherever an open/dedup/cycle decision must see them. Each
// Tab owns its own Back/Forward history (D-7); every open funnels through openTab's one dedup-then-
// predicate path (D-3b).

import type { PinEntry, SelectTarget, Tab, TabTarget } from '@shared/types'
import type { MutableKind } from '@shared/mutate'
import { navKey } from '../Navigation/navRecents'
import { byOrder, cleanPinTarget } from '../Navigation/navPins'

/** The new-tab sentinel value (maps to NavView / the `'none'` detail branch). */
export const NEWTAB: TabTarget = { kind: 'newtab' }

/** Identity key for a tab target — reuses navKey; the newtab sentinel collapses to a single 'newtab'
 *  key so I-1 keeps at most one NavView tab. */
export function tabKey(target: TabTarget): string {
  return target.kind === 'newtab' ? 'newtab' : navKey(target)
}

/** A pinned tab's stable id — derived from its pin identity so it's consistent across renders and can
 *  never collide with a generated unpinned-tab id. */
export function pinTabId(target: SelectTarget): string {
  return `pin:${navKey(target)}`
}

/** The pinned tabs, derived from the pins slice (sorted by fractional order). Agenda pins (a legacy
 *  migration can hold them) are skipped — `select` can't drive task/event, so they'd be unrenderable
 *  tabs. A pinned tab never navigates in place (D-2), so its history is just the pin target. */
export function derivePinnedTabs(pins: PinEntry[]): Tab[] {
  return [...pins]
    .sort(byOrder)
    .map(cleanPinTarget)
    .filter((t): t is SelectTarget => t.kind !== 'task' && t.kind !== 'event')
    .map((target) => tabFor(pinTabId(target), target))
}

/** Whether an entity is already open — as an unpinned tab or a pin (a derived pinned tab). Drives
 *  the stateful "Open" vs "Open in New Tab" menu labels (I-1). */
export function isOpenInTabs(tabs: Tab[], pins: PinEntry[], target: SelectTarget): boolean {
  const key = navKey(target)
  return tabs.some((t) => t.target.kind !== 'newtab' && navKey(t.target) === key) || pins.some((p) => navKey(p) === key)
}

/** Map a context-menu target to its drivable selection (area/topic/project collapse to `context`). */
export function contextTargetToSelect(t: { kind: MutableKind; id: string; path: string }): SelectTarget {
  switch (t.kind) {
    case 'page':
      return { kind: 'page', id: t.id, path: t.path }
    case 'set':
      return { kind: 'set', id: t.id, path: t.path }
    case 'collection':
      return { kind: 'collection', id: t.id }
    default:
      return { kind: 'context', id: t.id }
  }
}

/** The active tab restricted to the UNPINNED set — the Back/Forward owner (a pinned or newtab active
 *  tab carries no history, so its consumers read undefined and disable). */
export function activeUnpinnedTab(tabs: Tab[], activeTabId: string): Tab | undefined {
  return tabs.find((t) => t.id === activeTabId)
}

/** Whether a tab is pinned — derived from the pins set, never stored (C-6). The newtab sentinel is
 *  never pinned. */
export function isPinned(target: TabTarget, pins: PinEntry[]): boolean {
  if (target.kind === 'newtab') return false
  const key = navKey(target)
  return pins.some((p) => navKey(p) === key)
}

/** A tab seeded with `target` as its sole history entry (pinnedness is derived externally). */
function tabFor(id: string, target: SelectTarget): Tab {
  return { id, target, navStack: [target], navIndex: 0 }
}

/** A fresh NavView (new-tab) tab — empty history. */
export function newTabTab(id: string): Tab {
  return { id, target: NEWTAB, navStack: [], navIndex: -1 }
}

export interface OpenResult {
  tabs: Tab[]
  activeTabId: string
}

/** openTab (D-3b): dedup first (I-1 — an already-open entity just focuses its tab), else one predicate
 *  decides spawn-vs-replace. Spawns append RIGHT and hold order (D-12); a replace overwrites the active
 *  UNPINNED tab in place and pushes onto its Back/Forward stack. `pinned` is the derived pinned set
 *  (read-only context — pinning/unpinning is a separate op). */
export function openTab(
  tabs: Tab[],
  activeTabId: string,
  pinned: Tab[],
  target: SelectTarget,
  opts: { newTab?: boolean },
  newId: string,
): OpenResult {
  const key = navKey(target)
  const all = [...pinned, ...tabs]
  const existing = all.find((t) => t.target.kind !== 'newtab' && navKey(t.target) === key)
  if (existing) return { tabs, activeTabId: existing.id }

  const active = all.find((t) => t.id === activeTabId)
  const activeIsPinned = active ? pinned.some((p) => p.id === active.id) : false
  // Spawn when the open is explicit, the active tab is pinned (protected, D-2), or there's no active
  // tab; otherwise reuse the active unpinned tab (D-1) — which includes replacing a NavView scratch (E-2).
  if (opts.newTab || activeIsPinned || !active) {
    return { tabs: [...tabs, tabFor(newId, target)], activeTabId: newId }
  }
  const nextTabs = tabs.map((t) =>
    t.id === active.id
      ? { ...t, target, navStack: [...t.navStack.slice(0, t.navIndex + 1), target], navIndex: t.navIndex + 1 }
      : t,
  )
  return { tabs: nextTabs, activeTabId: active.id }
}

/** openNewTab (E-1): the `+` / ⌘N — focus the existing NavView if one is open (I-1, no duplicate),
 *  else append one. So pressing ⌘N while already in a new tab is a no-op (you're there). */
export function openNewTab(tabs: Tab[], newId: string): OpenResult {
  const existing = tabs.find((t) => t.target.kind === 'newtab')
  if (existing) return { tabs, activeTabId: existing.id }
  return { tabs: [...tabs, newTabTab(newId)], activeTabId: newId }
}

/** Push a tab id to the front of the MRU stack (deduped) — every activation records here (D-9). */
export function pushMru(mru: string[], id: string): string[] {
  return [id, ...mru.filter((m) => m !== id)]
}

export interface CloseResult {
  tabs: Tab[]
  activeTabId: string
  mru: string[]
}

/** closeTab: drop an unpinned tab. Closing the active tab focuses the MRU top still open (D-9), falling
 *  back to the spatial neighbor when the MRU is empty (a cold relaunch). Closing the very last tab —
 *  no pinned, no unpinned left — reseeds a lone NavView (I-5). Pinned tabs aren't closable here (their
 *  `×` is gated off; unpin first), so a pinned id is a no-op. */
export function closeTab(
  tabs: Tab[],
  activeTabId: string,
  mru: string[],
  pinnedIds: string[],
  id: string,
  newId: string,
): CloseResult {
  const idx = tabs.findIndex((t) => t.id === id)
  if (idx === -1) return { tabs, activeTabId, mru }
  const nextTabs = tabs.filter((t) => t.id !== id)
  const nextMru = mru.filter((m) => m !== id)

  if (nextTabs.length === 0 && pinnedIds.length === 0) {
    return { tabs: [newTabTab(newId)], activeTabId: newId, mru: [newId] }
  }
  if (id !== activeTabId) return { tabs: nextTabs, activeTabId, mru: nextMru }

  const live = new Set([...pinnedIds, ...nextTabs.map((t) => t.id)])
  const mruTop = nextMru.find((m) => live.has(m))
  const spatial = nextTabs[Math.min(idx, nextTabs.length - 1)]?.id ?? pinnedIds[pinnedIds.length - 1]
  return { tabs: nextTabs, activeTabId: mruTop ?? spatial, mru: nextMru }
}

/** reorderWithinZone: a plain move inside the unpinned strip (D-4b). Pinned reorder is the pins slice's
 *  reorderPin, handled at the store layer. */
export function reorderWithinZone(tabs: Tab[], fromId: string, toIndex: number): Tab[] {
  const from = tabs.findIndex((t) => t.id === fromId)
  if (from === -1) return tabs
  const to = Math.max(0, Math.min(toIndex, tabs.length - 1))
  if (from === to) return tabs
  const next = tabs.slice()
  const [moved] = next.splice(from, 1)
  next.splice(to, 0, moved)
  return next
}

/** D-11 promote-to-front: an unpinned entity enters the strip at the front (left), or just behind the
 *  active tab when the active tab is itself the front one (so it keeps its spot). */
export function insertUnpinned(tabs: Tab[], activeTabId: string, tab: Tab): Tab[] {
  const at = tabs[0] && tabs[0].id === activeTabId ? 1 : 0
  return [...tabs.slice(0, at), tab, ...tabs.slice(at)]
}

export interface ReconcileTabsResult {
  tabs: Tab[]
  activeTabId: string
  mru: string[]
  changed: boolean
}

/** I-2a: reconcile EVERY tab against a fresh tree, not just the active selection. A rename/move
 *  refreshes targets + history entries in place; a deleted entity closes its unpinned tab (active →
 *  MRU focus, D-9) and drops its dead history entries; everything gone with no pins reseeds a lone
 *  NavView (I-5). Reference-preserving: untouched tabs keep their identity and `changed: false`
 *  means the caller can skip the state write entirely. `reconcile` returns the live target
 *  (possibly re-pathed) or null when the entity is gone — built off a one-shot tree index, never a
 *  per-tab walk. */
export function reconcileTabs(
  tabs: Tab[],
  activeTabId: string,
  mru: string[],
  pinnedIds: string[],
  reconcile: (t: SelectTarget) => SelectTarget | null,
  newId: string,
): ReconcileTabsResult {
  let changed = false
  const nextTabs: Tab[] = []
  for (const t of tabs) {
    if (t.target.kind === 'newtab') {
      nextTabs.push(t)
      continue
    }
    const target = reconcile(t.target)
    if (target === null) {
      changed = true // deleted entity — the unpinned tab closes (I-2)
      continue
    }
    const stack: SelectTarget[] = []
    let navIndex = -1
    let stackChanged = false
    for (let i = 0; i < t.navStack.length; i++) {
      const r = reconcile(t.navStack[i])
      if (r === null) {
        stackChanged = true
        continue
      }
      if (r !== t.navStack[i]) stackChanged = true
      stack.push(r)
      if (i === t.navIndex) navIndex = stack.length - 1
    }
    if (navIndex === -1) navIndex = stack.length - 1
    if (target === t.target && !stackChanged) {
      nextTabs.push(t)
      continue
    }
    changed = true
    nextTabs.push({ ...t, target, navStack: stack, navIndex })
  }
  if (!changed) return { tabs, activeTabId, mru, changed: false }

  const live = new Set([...pinnedIds, ...nextTabs.map((t) => t.id)])
  const nextMru = mru.filter((id) => live.has(id))
  if (live.has(activeTabId)) return { tabs: nextTabs, activeTabId, mru: nextMru, changed: true }
  const focus = nextMru[0] ?? nextTabs[0]?.id ?? pinnedIds[pinnedIds.length - 1]
  if (focus !== undefined) return { tabs: nextTabs, activeTabId: focus, mru: nextMru, changed: true }
  const seeded = newTabTab(newId)
  return { tabs: [seeded], activeTabId: seeded.id, mru: [seeded.id], changed: true }
}

/** Ctrl+Tab cycling over the full visual order (pinned then unpinned), wrapping both ways (I-11). */
export function cycle(orderedIds: string[], activeTabId: string, dir: 1 | -1): string {
  if (orderedIds.length === 0) return activeTabId
  const i = orderedIds.indexOf(activeTabId)
  if (i === -1) return orderedIds[0]
  return orderedIds[(i + dir + orderedIds.length) % orderedIds.length]
}
