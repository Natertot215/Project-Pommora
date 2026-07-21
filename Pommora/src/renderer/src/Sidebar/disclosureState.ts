// Per-machine sidebar disclosure (expand/collapse) state. Transient UI chrome — regeneratable, not
// portable content — so it lives in app-level localStorage (mirrors Swift IconFavorites → UserDefaults),
// not `.nexus/`. Keyed by entity id (containers) or a `tier:*` string (structural tiers). Storage is a
// parameter so the behavior is testable without a DOM; callers pass `window.localStorage`.

type OpenMap = Record<string, boolean>

export const DISCLOSURE_KEY = 'pommora.sidebar.disclosure'

// The map is parsed once per storage object and mutated through saveOpen thereafter — expanding a
// container mounts one Disclosure per child, and a full-blob JSON.parse per mount is the kind of
// per-mount cost that adds up fast. A different storage (each test passes a fresh fake) misses the
// cache and re-reads.
let cached: { storage: Pick<Storage, 'getItem'>; map: OpenMap } | null = null

function readMap(storage: Pick<Storage, 'getItem'>): OpenMap {
  if (cached?.storage === storage) return cached.map
  let map: OpenMap = {}
  try {
    const raw = storage.getItem(DISCLOSURE_KEY)
    const parsed: unknown = raw ? JSON.parse(raw) : null
    if (parsed !== null && typeof parsed === 'object') map = parsed as OpenMap
  } catch {
    // unreadable/corrupt map — start empty
  }
  cached = { storage, map }
  return map
}

/** A disclosure's saved open state, or `fallback` when unset. */
export function loadOpen(
  storage: Pick<Storage, 'getItem'>,
  key: string,
  fallback: boolean,
): boolean {
  const value = readMap(storage)[key]
  return typeof value === 'boolean' ? value : fallback
}

/** Persist a disclosure's open state, merged into the existing map. */
export function saveOpen(
  storage: Pick<Storage, 'getItem' | 'setItem'>,
  key: string,
  open: boolean,
): void {
  const map = readMap(storage)
  map[key] = open
  try {
    storage.setItem(DISCLOSURE_KEY, JSON.stringify(map))
  } catch {
    // Best-effort chrome: localStorage may be unavailable / over quota.
  }
}
