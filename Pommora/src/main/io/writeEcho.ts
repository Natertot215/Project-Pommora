// Self-write echo suppression: the watcher exists for EXTERNAL changes — the
// app's own writes must not re-trigger it (every tree-relevant in-app write
// already refetches explicitly, so an echo only buys a redundant full walk).
// The funnel records every path the app writes, renames, moves, or trashes;
// the watcher skips events landing inside the window. A recorded FOLDER also
// suppresses its descendants — a folder rename/move echoes as child events too.

import { sep } from 'node:path'

const recent = new Map<string, number>()
const WINDOW_MS = 2000
// Descendant (prefix) suppression gets a tighter window: a folder rename's child echoes all land
// within chokidar's settle pipeline (~400ms), while every prefix-suppressed millisecond is also a
// blind spot for a genuine EXTERNAL write into that folder. Long enough for the echo, short
// enough that most-recent-wins staleness can't stretch to seconds.
const PREFIX_WINDOW_MS = 800

export function recordWrite(absPath: string): void {
  recent.set(absPath, Date.now())
  if (recent.size > 256) {
    const cutoff = Date.now() - WINDOW_MS
    for (const [p, t] of recent) if (t < cutoff) recent.delete(p)
  }
}

export function isRecentWrite(absPath: string): boolean {
  const now = Date.now()
  const t = recent.get(absPath)
  if (t !== undefined) {
    if (now - t <= WINDOW_MS) return true
    recent.delete(absPath)
  }
  // The map stays ≤256 entries (pruned on record), so the descendant scan is a bounded
  // sweep over a hot cache, never an O(vault) walk.
  for (const [p, tp] of recent) {
    if (now - tp > PREFIX_WINDOW_MS) continue
    if (absPath.startsWith(p + sep)) return true
  }
  return false
}
