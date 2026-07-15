// Pure recents-stream logic for the Navigation layer. Storage is a plain MRU list (newest first);
// the `pinned` flag is a marker only — pinned entries FLOAT to the top at render (navResolve), never
// in storage, so the stored order stays honest history. Cap roll-off drops the oldest UN-pinned
// entries; pinned entries are deliberate and never roll off. All functions are pure (no store, no
// IPC) so they unit-test without a DOM.

import type { NavTarget, RecentEntry } from '@shared/types'

/** Generous default history depth (D-8: deep history + a tunable cap, not a tight ~50). */
export const RECENTS_CAP = 100

/** Identity of a nav target — kind+id, or bare kind for the id-less homepage. Shared by the history
 *  dedupe, the recents stream, and favorites membership so all three collapse the same targets. */
export function navKey(t: NavTarget): string {
  return 'id' in t ? `${t.kind}:${t.id}` : t.kind
}

/** Record a visit: dedupe by key (carrying any existing pinned flag onto the fresh front entry),
 *  move-to-front, then roll off the oldest un-pinned beyond `cap`. */
export function recordRecent(recents: RecentEntry[], target: NavTarget, cap = RECENTS_CAP): RecentEntry[] {
  const key = navKey(target)
  const existing = recents.find((r) => navKey(r) === key)
  const front: RecentEntry = existing?.pinned ? { ...target, pinned: true } : { ...target }
  return capRecents([front, ...recents.filter((r) => navKey(r) !== key)], cap)
}

/** Flip the pin on the entry with `key`. Pinning sets `pinned: true`; un-pinning DELETES the key
 *  (absent = un-pinned — no `pinned: false` ever reaches disk). */
export function togglePinned(recents: RecentEntry[], key: string): RecentEntry[] {
  return recents.map((r) => {
    if (navKey(r) !== key) return r
    if (!r.pinned) return { ...r, pinned: true }
    const { pinned: _drop, ...rest } = r
    return rest as RecentEntry
  })
}

/** Roll off oldest un-pinned entries (tail-first) until length ≤ cap. Pinned entries are exempt (so
 *  an all-pinned list can legitimately exceed the cap), and index 0 — the entry just recorded — is
 *  never its own eviction victim (else recording into an all-pinned list would drop the fresh visit). */
function capRecents(recents: RecentEntry[], cap: number): RecentEntry[] {
  let excess = recents.length - cap
  if (excess <= 0) return recents
  const keep = [...recents]
  for (let i = keep.length - 1; i >= 1 && excess > 0; i--) {
    if (!keep[i].pinned) {
      keep.splice(i, 1)
      excess--
    }
  }
  return keep
}
