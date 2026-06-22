// Per-machine sidebar disclosure (expand/collapse) state. Transient UI chrome — regeneratable, not
// portable content — so it lives in app-level localStorage (mirrors Swift IconFavorites → UserDefaults),
// not `.nexus/`. Keyed by entity id (containers) or a `tier:*` string (structural tiers). Storage is a
// parameter so the behavior is testable without a DOM; callers pass `window.localStorage`.

type OpenMap = Record<string, boolean>

export const DISCLOSURE_KEY = 'pommora.sidebar.disclosure'

function readMap(storage: Pick<Storage, 'getItem'>): OpenMap {
  try {
    const raw = storage.getItem(DISCLOSURE_KEY)
    const parsed: unknown = raw ? JSON.parse(raw) : null
    return parsed !== null && typeof parsed === 'object' ? (parsed as OpenMap) : {}
  } catch {
    return {}
  }
}

/** A disclosure's saved open state, or `fallback` when unset. */
export function loadOpen(storage: Pick<Storage, 'getItem'>, key: string, fallback: boolean): boolean {
  const value = readMap(storage)[key]
  return typeof value === 'boolean' ? value : fallback
}

/** Persist a disclosure's open state, merged into the existing map. */
export function saveOpen(storage: Pick<Storage, 'getItem' | 'setItem'>, key: string, open: boolean): void {
  try {
    storage.setItem(DISCLOSURE_KEY, JSON.stringify({ ...readMap(storage), [key]: open }))
  } catch {
    // Best-effort chrome: localStorage may be unavailable / over quota.
  }
}
