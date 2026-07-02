// Structural sharing for watcher pushes. Every 'nexus:changed' arrives as a WHOLE fresh tree —
// IPC strips object identity, so without this every push re-rendered every consumer even when
// nothing (or something unrelated) changed. `stabilize` recycles the prior tree's subobjects
// wherever the new content is deep-equal: an unchanged container keeps reference identity (its
// open table's pipeline memo holds), and an echo push returns the previous tree itself (a
// zustand no-op — zero re-renders). Pure over JSON-safe data (the IPC contract): plain objects,
// arrays, primitives only.

const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v)

export function stabilize<T>(next: T, prev: unknown): T {
  if (Object.is(next, prev)) return next
  if (Array.isArray(next) && Array.isArray(prev)) {
    let same = next.length === prev.length
    const out = next.map((n, i) => {
      const s = stabilize(n, prev[i])
      if (!Object.is(s, prev[i])) same = false
      return s
    })
    return same ? (prev as T) : (out as T)
  }
  if (isPlainObject(next) && isPlainObject(prev)) {
    const keys = Object.keys(next)
    let same = keys.length === Object.keys(prev).length
    const out: Record<string, unknown> = {}
    for (const k of keys) {
      const s = stabilize(next[k], prev[k])
      out[k] = s
      if (!Object.is(s, prev[k])) same = false
    }
    return same ? (prev as T) : (out as T)
  }
  return next
}
