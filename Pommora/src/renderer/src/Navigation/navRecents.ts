// Pure recents-stream logic for the Navigation layer. Storage is a plain MRU list (newest first).
// Durable pins are their OWN list now (navPins / `.nexus/pins/`) — recents carry no pin state, so cap
// roll-off simply drops the oldest. All functions are pure (no store, no IPC) so they unit-test
// without a DOM. RecentEntry keeps an optional `pinned` only so a legacy sidecar reads + migrates.

import type { NavTarget, RecentEntry } from '@shared/types'

/** Generous default history depth (D-8: deep history + a tunable cap, not a tight ~50). */
export const RECENTS_CAP = 100

/** Identity of a nav target — kind+id, or bare kind for the id-less homepage. Shared by the history
 *  dedupe, the recents stream, and favorites/pins membership so all collapse the same targets. */
export function navKey(t: NavTarget): string {
  return 'id' in t ? `${t.kind}:${t.id}` : t.kind
}

/** Record a visit: dedupe by key, move-to-front, then roll off the oldest beyond `cap`. */
export function recordRecent(recents: RecentEntry[], target: NavTarget, cap = RECENTS_CAP): RecentEntry[] {
  const key = navKey(target)
  return capRecents([{ ...target }, ...recents.filter((r) => navKey(r) !== key)], cap)
}

/** Keep the newest `cap` entries (the list is newest-first, so the front — the just-recorded visit —
 *  always survives). */
function capRecents(recents: RecentEntry[], cap: number): RecentEntry[] {
  return recents.length <= cap ? recents : recents.slice(0, cap)
}
