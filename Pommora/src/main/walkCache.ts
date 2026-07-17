// The walk's parse gate: absolute path → the value parsed at a known (mtime, size).
// Every walk still enumerates every directory and stats every file it encounters — the
// walk IS the verification pass, so tree-vs-disk drift is unrepresentable — but the
// expensive tier (file reads + YAML/JSON parsing) runs only for files whose metadata
// moved. Entries a walk doesn't touch are pruned at walk end, so a deleted file's
// value can't linger; a root switch drops everything.

import { stat } from 'node:fs/promises'

// A hit is refused while the parse happened within this window of the file's own mtime —
// a same-tick edit on a coarse-mtime volume (exFAT/SMB) is invisible to (mtime, size),
// so hot files re-parse until they cool. git's racy-index rule.
const RACY_WINDOW_MS = 2000

type Entry = { mtimeMs: number; size: number; verifiedAt: number; gen: number; value: unknown }

let cacheRoot: string | null = null
let gen = 0
const entries = new Map<string, Entry>()

/** Open a walk over `root`: bumps the generation stamp and drops the cache on a root switch. */
export function beginWalk(root: string): void {
  if (root !== cacheRoot) {
    entries.clear()
    cacheRoot = root
  }
  gen++
}

/** Close a walk: prune every entry the walk didn't touch (its file no longer exists). */
export function endWalk(): void {
  for (const [key, e] of entries) if (e.gen < gen) entries.delete(key)
}

/** Parse-through cache: stat `absPath`, serve the cached value while (mtime, size) hold
 *  and the racy window has passed, else run `parse` and remember it. A failed stat
 *  falls through to `parse` uncached so the parser's own error semantics decide. */
export async function cachedParse<T>(absPath: string, parse: () => Promise<T>): Promise<T> {
  let s: { mtimeMs: number; size: number }
  try {
    s = await stat(absPath)
  } catch {
    return parse()
  }
  const e = entries.get(absPath)
  if (
    e &&
    e.mtimeMs === s.mtimeMs &&
    e.size === s.size &&
    e.verifiedAt - s.mtimeMs > RACY_WINDOW_MS
  ) {
    e.gen = gen
    return e.value as T
  }
  const value = await parse()
  entries.set(absPath, { mtimeMs: s.mtimeMs, size: s.size, verifiedAt: Date.now(), gen, value })
  return value
}
