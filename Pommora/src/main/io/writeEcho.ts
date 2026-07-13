// Self-write echo suppression: the watcher exists for EXTERNAL changes — the
// app's own writes must not re-trigger it (every tree-relevant in-app write
// already refetches explicitly; the echo was pure redundancy, and block/body
// writes made it hot). The atomic-write funnel records each path; the watcher
// skips events landing inside the window. Renames/moves/trash aren't funneled
// and still walk — they're per-action and genuinely tree-relevant.

const recent = new Map<string, number>()
const WINDOW_MS = 2000

export function recordWrite(absPath: string): void {
  recent.set(absPath, Date.now())
  if (recent.size > 256) {
    const cutoff = Date.now() - WINDOW_MS
    for (const [p, t] of recent) if (t < cutoff) recent.delete(p)
  }
}

export function isRecentWrite(absPath: string): boolean {
  const t = recent.get(absPath)
  if (t === undefined) return false
  if (Date.now() - t > WINDOW_MS) {
    recent.delete(absPath)
    return false
  }
  return true
}
