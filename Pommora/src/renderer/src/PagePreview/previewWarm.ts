// Session-only warmth for preview tabs (H-8/H-11): serialized editor state (undo via CM6's
// historyField) + scroll, keyed by preview-tab id — the app tabs' warmCache pattern, but flat:
// preview tabs have no Back/Forward, so one entry per tab. Module state, never render state.
// Tab ids re-mint at every summon/restore, so the map lives and dies with the OPEN window —
// window close/overtake/adopt clear it wholesale; a tab close drops its key. A capture landing
// under an already-closed id (the store-first close beats the unmount capture) leaves one inert
// entry — never readable, ids are never reused — reaped by the next wholesale clear.

export interface PreviewWarmEntry {
  editorState?: unknown
  /** The editor's INTERNAL scroller — always 0 in the preview (the body owns scroll there). */
  scrollTop?: number
  /** The preview body's scroll — the window captures it per tab (two scrollers, two fields). */
  bodyScrollTop?: number
}

const cache = new Map<string, PreviewWarmEntry>()

/** Merge a partial capture — the editor (state) and the window (body scroll) write under one key. */
export function capturePreviewWarm(tabId: string, patch: PreviewWarmEntry): void {
  cache.set(tabId, { ...cache.get(tabId), ...patch })
}

export function readPreviewWarm(tabId: string): PreviewWarmEntry | undefined {
  return cache.get(tabId)
}

export function dropPreviewWarm(tabId: string): void {
  cache.delete(tabId)
}

export function clearPreviewWarm(): void {
  cache.clear()
}

// Dev-only CDP probe (the store's __pommora twin) — lets a headless drive assert warm entries.
if (import.meta.env.DEV && typeof window !== 'undefined') {
  ;(window as unknown as { __pommoraWarm: unknown }).__pommoraWarm = cache
}
