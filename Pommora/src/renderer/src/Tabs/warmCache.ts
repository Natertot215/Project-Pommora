// The session-only warm cache behind warm tabs (B-2/B-3): serialized editor state (undo history via
// CM6's historyField), scroll position, and the cached PageDetail, keyed (tabId → navKey) so a tab's
// whole Back/Forward stack stays warm (I-7) without cross-tab bleed — two tabs can hold the same
// entity in their histories, each with its own undo. Module state, not store state: none of it is
// render state, and it must survive React remounts while dying with the session (quit resets, D-8).
//
// Entries have two writers under one key: the STORE captures pageDetail at switch-initiation (before
// `select` nulls it), and the editor captures editorState/scrollTop at unmount under keys frozen at
// its mount. A capture landing under an already-closed tabId leaves one inert entry (never readable —
// tab ids are never reused); the nexus-switch clear reaps it.

import type { PageDetail } from '@shared/types'

export interface WarmEntry {
  /** `EditorState.toJSON({ history: historyField })` payload — opaque here, parsed only by the seam. */
  editorState?: unknown
  scrollTop?: number
  pageDetail?: PageDetail
}

/** Warm depth per tab (I-7): Back/Forward restores warm this many entries deep; beyond it, cold. */
const WARM_CAP_PER_TAB = 20

const cache = new Map<string, Map<string, WarmEntry>>()

/** Merge a partial capture under (tabId, navKey), refreshing its LRU slot; the per-tab cap evicts the
 *  stalest entry (Map insertion order = recency, since every capture re-inserts). */
export function captureWarm(tabId: string, navKey: string, patch: Partial<WarmEntry>): void {
  let tabMap = cache.get(tabId)
  if (!tabMap) {
    tabMap = new Map()
    cache.set(tabId, tabMap)
  }
  const merged = { ...tabMap.get(navKey), ...patch }
  tabMap.delete(navKey)
  tabMap.set(navKey, merged)
  while (tabMap.size > WARM_CAP_PER_TAB) {
    const oldest = tabMap.keys().next().value
    if (oldest === undefined) break
    tabMap.delete(oldest)
  }
}

export function readWarm(tabId: string, navKey: string): WarmEntry | undefined {
  return cache.get(tabId)?.get(navKey)
}

/** Drop a closed tab's whole warm stack. */
export function dropWarmTab(tabId: string): void {
  cache.delete(tabId)
}

/** Wholesale reset — nexus switch (I-10). */
export function clearWarm(): void {
  cache.clear()
}
