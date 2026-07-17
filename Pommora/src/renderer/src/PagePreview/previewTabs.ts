import type { PreviewTabTarget } from '@shared/types'

// The preview window's tab model (Decision Log H) — pure functions, no store. The close/spawn
// bodies are bespoke (NOT tabsModel's): the last tab closing kills the WINDOW (H-6, no NavView
// reseed), and there are no pins (H-5).

export interface PreviewTab {
  id: string
  target: PreviewTabTarget
}

export interface PreviewState {
  /** 'page' = summoned from a page open; 'nav' = the NavWindow flavor (map-tab sentinel first). */
  flavor: 'page' | 'nav'
  /** The durable set's key (H-3); re-parents to the left-most survivor on origin close (H-6). */
  originId: string
  tabs: PreviewTab[]
  activeTabId: string
}

const targetPageId = (t: PreviewTabTarget): string | null => (t.kind === 'page' ? t.id : null)

/** Dedup-focus an existing tab for the page, else append + activate (H-1). */
export function openTabIn(
  p: PreviewState,
  makeId: () => string,
  target: { id: string; path: string },
): PreviewState {
  const existing = p.tabs.find((t) => targetPageId(t.target) === target.id)
  if (existing) {
    return existing.id === p.activeTabId ? p : { ...p, activeTabId: existing.id }
  }
  const tab: PreviewTab = { id: makeId(), target: { kind: 'page', ...target } }
  return { ...p, tabs: [...p.tabs, tab], activeTabId: tab.id }
}

/** Drag-reorder a page tab onto another's slot. The map sentinel is immovable AND un-landable —
 *  it holds slot 1 (H-2), so a move that names it either way is refused. */
export function reorderTabIn(p: PreviewState, activeId: string, overId: string): PreviewState {
  const from = p.tabs.findIndex((t) => t.id === activeId)
  const to = p.tabs.findIndex((t) => t.id === overId)
  if (from === -1 || to === -1 || from === to) return p
  if (p.tabs[from].target.kind === 'navwindow' || p.tabs[to].target.kind === 'navwindow') return p
  const tabs = p.tabs.slice()
  const [moved] = tabs.splice(from, 1)
  tabs.splice(to, 0, moved)
  return { ...p, tabs }
}

/** Close a tab: the active falls to its left neighbor; the origin re-parents to the left-most
 *  surviving page tab; the last tab closing kills the window (null). */
export function closeTabIn(p: PreviewState, id: string): PreviewState | null {
  const idx = p.tabs.findIndex((t) => t.id === id)
  if (idx === -1) return p
  if (p.tabs[idx].target.kind === 'navwindow') return p // the map tab is perma-pinned (H-2)
  const tabs = p.tabs.filter((t) => t.id !== id)
  if (tabs.length === 0) return null
  const activeTabId = p.activeTabId === id ? tabs[Math.max(0, idx - 1)].id : p.activeTabId
  const firstPage = tabs.find((t) => targetPageId(t.target) !== null)
  const closedOrigin = targetPageId(p.tabs[idx].target) === p.originId
  const originId =
    closedOrigin && firstPage ? (targetPageId(firstPage.target) as string) : p.originId
  if (!firstPage && p.flavor === 'page') return null
  return { ...p, tabs, activeTabId, originId }
}

/** The window's shown page — the active tab when it's a page (the nav sentinel shows the gallery). */
export function deriveTarget(p: PreviewState | null): { id: string; path: string } | null {
  if (!p) return null
  const active = p.tabs.find((t) => t.id === p.activeTabId)
  return active && active.target.kind === 'page'
    ? { id: active.target.id, path: active.target.path }
    : null
}
