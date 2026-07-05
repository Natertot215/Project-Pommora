// The per-file write lock shared by BOTH page-write paths, so a schema-op page cascade and a
// table cell edit on the SAME page can't clobber each other. The hot cell ops (mutate's
// setProperty/setTier) and the schema-op cascades (option rename/remove/clear, the [[link]]
// rename + tier-unlink cascades, and property delete/remove) all run their read-modify-write
// under serializeOnFile, so overlapping RMWs on one page serialize instead of racing — a stale
// snapshot losing to a fresh write, or a cascade dropping a value a concurrent edit just set.
// Chain per resolved path (the map holds one settled promise per touched file; negligible).

import { readFile } from 'node:fs/promises'
import { atomicWriteFile } from './atomicWrite'

const fileChains = new Map<string, Promise<unknown>>()

export function serializeOnFile<T>(path: string, fn: () => Promise<T>): Promise<T> {
  const run = (fileChains.get(path) ?? Promise.resolve()).then(fn, fn)
  fileChains.set(
    path,
    run.then(
      () => undefined,
      () => undefined
    )
  )
  return run
}

/** Rewrite ONE page under its file lock, reading FRESH inside the lock so a concurrent
 *  cell-write is never clobbered by a stale pre-read. `rewrite` maps current content → next
 *  content, or null to leave the page untouched. An unreadable file is skipped. Returns
 *  whether the page was written. */
export async function rewritePageSerialized(
  file: string,
  rewrite: (content: string) => string | null
): Promise<boolean> {
  return serializeOnFile(file, async () => {
    let content: string
    try {
      content = await readFile(file, 'utf8')
    } catch {
      return false
    }
    const next = rewrite(content)
    if (next === null) return false
    await atomicWriteFile(file, next)
    return true
  })
}
